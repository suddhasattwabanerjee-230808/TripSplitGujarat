import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'location_service.dart';
import 'models.dart';
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
      colorScheme: ColorScheme.fromSeed(seedColor: teal),
      fontFamily: 'Roboto',
    ),
    home: const _UpiPopup(),
  );
}

/// Best-effort category from the payee / description so the totals stay useful.
String guessCategory(String text) {
  final t = text.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(['zomato', 'swiggy', 'restaurant', 'cafe', 'food', 'dhaba', 'pizza', 'bakery', 'chai', 'kitchen', 'lunch', 'dinner', 'breakfast'])) {
    return 'Food';
  }
  if (has(['uber', 'ola', 'rapido', 'irctc', 'railway', 'redbus', 'metro', 'petrol', 'fuel', 'indigo', 'airlines', 'cab', 'taxi', 'toll', 'fastag'])) {
    return 'Transport';
  }
  if (has(['oyo', 'airbnb', 'hotel', 'resort', 'stay', 'lodge', 'makemytrip', 'goibibo', 'booking'])) return 'Stay';
  if (has(['ticket', 'bookmyshow', 'museum', 'safari', 'entry', 'park'])) return 'Activities';
  return 'Other';
}

class _UpiPopup extends StatefulWidget {
  const _UpiPopup();

  @override
  State<_UpiPopup> createState() => _UpiPopupState();
}

class _UpiPopupState extends State<_UpiPopup> {
  final _description = TextEditingController();
  double _amount = 0;
  String? _payee;
  DateTime _time = DateTime.now();
  List<Trip> _trips = [];
  int? _tripId;
  String? _location;
  bool _locating = true;
  bool _loading = true;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
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
    fetchLocationLabel().then((label) {
      if (mounted) {
        setState(() {
          _location = label;
          _locating = false;
        });
      }
    });
    try {
      final trips = await ApiClient.instance.listTrips();
      final last = await ApiClient.instance.lastTripId();
      setState(() {
        _trips = trips;
        _tripId = trips.any((t) => t.id == last) ? last : (trips.isEmpty ? null : trips.first.id);
        _loading = false;
        if (trips.isEmpty) _error = 'Create or join a trip in TripSplit first.';
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _close() => _channel.invokeMethod('close');

  String get _tripName => _trips.firstWhere((t) => t.id == _tripId, orElse: () => _trips.first).name;

  Future<void> _save() async {
    if (_tripId == null) return;
    final typed = _description.text.trim();
    final description = typed.isNotEmpty ? typed : (_payee ?? 'UPI payment');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.createExpense(
        tripId: _tripId!,
        description: description,
        amount: _amount,
        category: guessCategory('$description ${_payee ?? ''}'),
        date: _time.toIso8601String(),
        location: _location,
      );
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
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
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _done ? _doneView() : _formView(),
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
          decoration: BoxDecoration(color: teal.withValues(alpha: .14), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: teal, size: 30),
        ),
        const SizedBox(height: 12),
        Text(
          'Added to $_tripName',
          style: const TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
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
          decoration: BoxDecoration(color: const Color(0xFFD9DED8), borderRadius: BorderRadius.circular(4)),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: teal.withValues(alpha: .14), shape: BoxShape.circle),
            child: const Icon(Icons.currency_rupee_rounded, color: teal, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPI payment detected',
                  style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
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
      const SizedBox(height: 4),
      Text(
        '${_payee == null ? '' : 'to $_payee · '}${formatDateTime(_time)}',
        style: const TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 16),
      if (_loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: teal)),
        )
      else if (_tripId != null) ...[
        TextField(
          controller: _description,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _save(),
          decoration: appInputDecoration(
            _payee == null ? 'What was it for?' : 'What was it for? (e.g. Lunch at $_payee)',
            Icons.edit_rounded,
          ),
        ),
        const SizedBox(height: 10),
        _infoRow(
          Icons.landscape_rounded,
          _trips.length > 1 ? null : 'Adding to $_tripName',
          trailing: _trips.length > 1 ? _tripPicker() : null,
        ),
        const SizedBox(height: 6),
        _infoRow(
          Icons.location_on_rounded,
          _locating ? 'Finding your location…' : (_location ?? 'Location unavailable'),
          trailing: _locating
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: teal))
              : null,
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12)),
        ),
      if (_tripId != null) ...[
        const SizedBox(height: 16),
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
                : Text('Add to $_tripName', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ],
  );

  Widget _infoRow(IconData icon, String? text, {Widget? trailing}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(icon, size: 17, color: teal),
        const SizedBox(width: 10),
        if (text != null)
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (trailing != null) text == null ? Expanded(child: trailing) : trailing,
      ],
    ),
  );

  Widget _tripPicker() => DropdownButtonHideUnderline(
    child: DropdownButton<int>(
      value: _tripId,
      isDense: true,
      isExpanded: true,
      style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
      items: [for (final t in _trips) DropdownMenuItem(value: t.id, child: Text('Adding to ${t.name}'))],
      onChanged: _busy ? null : (id) => setState(() => _tripId = id),
    ),
  );
}
