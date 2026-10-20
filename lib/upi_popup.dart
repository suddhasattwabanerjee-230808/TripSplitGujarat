import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'category_guess.dart';
import 'location_service.dart';
import 'models.dart';
import 'screens/location_picker_screen.dart';
import 'theme.dart';

const _channel = MethodChannel('tripsplit/upi');

/// Standalone app shown by UpiPopupActivity when a "UPI payment detected"
/// notification is tapped — just the quick-add card, not the full app.
class UpiPopupApp extends StatelessWidget {
  const UpiPopupApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Colors.transparent,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: accent),
      fontFamily: 'Roboto',
    ),
    home: const _UpiPopup(),
  );
}

class _UpiPopup extends StatefulWidget {
  const _UpiPopup();

  @override
  State<_UpiPopup> createState() => _UpiPopupState();
}

class _UpiPopupState extends State<_UpiPopup> {
  final _description = TextEditingController();
  final _location = TextEditingController();
  double _amount = 0;
  String? _payee;
  DateTime _time = DateTime.now();
  Trip? _trip;
  String _category = 'Other';
  // True after the user taps a chip; the description can still take it back
  // (see followDescription).
  bool _categoryPicked = false;
  String _lastDescription = '';
  bool _locationEdited = false;
  bool _locating = true;
  bool _loading = true;
  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _hasDescription => _description.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescriptionChanged);
    _init();
  }

  @override
  void dispose() {
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    // The controller also fires on cursor moves; only re-guess on new text.
    if (_description.text == _lastDescription) return;
    _lastDescription = _description.text;
    final next = followDescription(
      current: _category,
      auto: !_categoryPicked,
      description: _description.text,
      payee: _payee,
    );
    setState(() {
      _category = next.category;
      _categoryPicked = !next.auto;
    });
  }

  Future<void> _init() async {
    final data = await _channel.invokeMapMethod<String, dynamic>('getTransaction') ?? {};
    _amount = (data['amount'] as num?)?.toDouble() ?? 0;
    _payee = data['payee'] as String?;
    _time = DateTime.fromMillisecondsSinceEpoch(data['time'] as int? ?? DateTime.now().millisecondsSinceEpoch);
    if (!await ApiClient.instance.restoreSession()) {
      setState(() {
        _loading = false;
        _error = 'Log in to TripSplit first, then try again.';
      });
      return;
    }
    _fillCurrentLocation();
    try {
      final trips = await ApiClient.instance.listTrips();
      final last = await ApiClient.instance.lastTripId();
      setState(() {
        _trip = _pickTrip(trips, last);
        _loading = false;
        if (_trip == null) _error = 'Create or join a trip in TripSplit first.';
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// UPI payments always go to the Gujarat trip; falls back to the last-opened trip
  /// only if there isn't one.
  Trip? _pickTrip(List<Trip> trips, String? lastId) {
    if (trips.isEmpty) return null;
    bool isGujarat(Trip t) => '${t.name} ${t.destination ?? ''}'.toLowerCase().contains('gujarat');
    final gujarat = trips.where(isGujarat).toList();
    if (gujarat.isNotEmpty) {
      return gujarat.firstWhere((t) => t.id == lastId, orElse: () => gujarat.first);
    }
    return trips.firstWhere((t) => t.id == lastId, orElse: () => trips.first);
  }

  Future<void> _fillCurrentLocation() async {
    setState(() => _locating = true);
    final label = await fetchLocationLabel();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (label != null && !_locationEdited) _location.text = label;
    });
  }

  Future<void> _openLocationPicker() async {
    FocusScope.of(context).unfocus();
    final current = _location.text.trim();
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLabel: current.isEmpty ? null : current)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _location.text = picked;
      _locationEdited = true;
    });
  }

  Future<void> _useCurrentLocation() async {
    _locationEdited = false;
    await _fillCurrentLocation();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: _time.subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_time));
    if (time == null) return;
    setState(() => _time = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _close() => _channel.invokeMethod('close');

  Future<void> _save() async {
    final trip = _trip;
    if (trip == null) return;
    final typed = _description.text.trim();
    final description = typed.isNotEmpty ? typed : (_payee ?? 'UPI payment');
    final location = _location.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.createExpense(
        tripId: trip.id,
        trip: trip,
        description: description,
        amount: _amount,
        category: _hasDescription ? _category : guessCategory(description),
        date: _time.toIso8601String(),
        location: location.isEmpty ? null : location,
      );
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      await _close();
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .4),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _close,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: const BoxDecoration(
                color: paper,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _done ? _doneView() : _formView(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _doneView() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: accent.withValues(alpha: .14), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: accent, size: 30),
        ),
        const SizedBox(height: 12),
        const Text(
          'Expense added',
          style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('Added to ${_trip?.name ?? 'your trip'}', style: const TextStyle(color: muted, fontSize: 12)),
      ],
    ),
  );

  Widget _formView() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(color: const Color(0xFFD5D8E2), borderRadius: BorderRadius.circular(4)),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: accent.withValues(alpha: .14), shape: BoxShape.circle),
            child: const Icon(Icons.currency_rupee_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _payee == null ? 'UPI payment detected' : 'Paid to $_payee',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  money(_amount),
                  style: const TextStyle(color: ink, fontSize: 26, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -.6),
                ),
              ],
            ),
          ),
          IconButton(onPressed: _busy ? null : _close, icon: const Icon(Icons.close_rounded, color: muted)),
        ],
      ),
      const SizedBox(height: 16),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: accent)),
        )
      else if (_trip != null) ...[
        fieldLabel('WHAT WAS IT FOR?'),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: appInputDecoration(
            _payee == null ? 'e.g. Lunch, auto, hotel' : 'e.g. Lunch at $_payee',
            Icons.edit_outlined,
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          // The surrounding AnimatedSize already animates the height change.
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
          child: _hasDescription ? _categorySection() : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 14),
        fieldLabel('WHERE'),
        const SizedBox(height: 8),
        TextField(
          controller: _location,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => _locationEdited = true,
          onSubmitted: (_) => _busy ? null : _save(),
          decoration: appInputDecoration(
            _locating ? 'Finding your location…' : 'Add a location',
            Icons.location_on_outlined,
          ).copyWith(
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_locating)
                  const Padding(
                    padding: EdgeInsets.all(15),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                  )
                else
                  IconButton(
                    tooltip: 'Use current location',
                    onPressed: _busy ? null : _useCurrentLocation,
                    icon: const Icon(Icons.my_location_outlined, size: 18, color: accent),
                  ),
                IconButton(
                  tooltip: 'Pick on map',
                  onPressed: _busy ? null : _openLocationPicker,
                  icon: const Icon(Icons.map_outlined, size: 18, color: accent),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        fieldLabel('WHEN'),
        const SizedBox(height: 8),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _busy ? null : _pickDateTime,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 18, color: muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fullDateTime(_time),
                      style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.edit_calendar_outlined, size: 17, color: accent),
                ],
              ),
            ),
          ),
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
        ),
      if (_trip != null) ...[
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: _busy || _loading ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save expense', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ],
  );

  Widget _categorySection() => Padding(
    key: const ValueKey('category'),
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            fieldLabel('CATEGORY'),
            if (!_categoryPicked) ...[
              const SizedBox(width: 6),
              const Icon(Icons.auto_awesome_outlined, size: 11, color: accent),
              const SizedBox(width: 3),
              const Text('auto', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w800)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final c in categoryOrder)
              ChoiceChip(
                label: Text(c),
                avatar: Icon(iconForCategory(c), size: 15, color: _category == c ? colorForCategory(c) : muted),
                selected: _category == c,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _category = c;
                        _categoryPicked = true;
                      }),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                selectedColor: colorForCategory(c).withValues(alpha: .16),
                backgroundColor: Colors.white,
                side: BorderSide(color: _category == c ? colorForCategory(c) : Colors.transparent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _category == c ? ink : muted,
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Fri, 16 Oct 2026 · 7:42 PM" — the popup shows the full date, not "Today".
String _fullDateTime(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${_weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year} · $h:$m $period';
}
