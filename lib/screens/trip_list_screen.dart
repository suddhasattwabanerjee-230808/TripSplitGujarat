import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'activity_screen.dart';
import 'trip_home_screen.dart';

/// Opens a trip and refreshes the shared data when the user comes back.
Future<void> openTrip(BuildContext context, Trip trip) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TripHomeScreen(tripId: trip.id, tripName: trip.name),
    ),
  );
  await TripStore.instance.refresh();
}

Future<void> openTripById(BuildContext context, int tripId) async {
  final trip = TripStore.instance.trips?.where((t) => t.id == tripId).firstOrNull;
  if (trip != null) await openTrip(context, trip);
}

/// The "+" button's menu: start a trip or join one with a code.
Future<void> showNewTripMenu(BuildContext context) async {
  final choice = await showAppSheet<String>(
    context,
    title: 'New split',
    children: (ctx) => [
      groupedCard([
        _menuRow(
          ctx,
          Icons.add_circle_outline_rounded,
          'Start a new trip or group',
          'Trip, flat, couple, event…',
          'new',
        ),
        _menuRow(
          ctx,
          Icons.group_add_outlined,
          'Join with an invite code',
          'Ask a friend for their 6-letter code',
          'join',
        ),
      ], indent: 64),
    ],
  );
  if (choice == null || !context.mounted) return;
  final trip = await showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => choice == 'new' ? const _CreateTripSheet() : const _JoinTripSheet(),
  );
  if (trip != null && context.mounted) {
    await TripStore.instance.refresh();
    if (context.mounted) await openTrip(context, trip);
  }
}

Widget _menuRow(BuildContext ctx, IconData icon, String title, String subtitle, String value) => InkWell(
  onTap: () => Navigator.pop(ctx, value),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        IconCircle(icon: icon, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: muted),
      ],
    ),
  ),
);

/// The Home tab.
class TripListScreen extends StatefulWidget {
  const TripListScreen({super.key, this.onPayNow});

  /// "Pay Bill Now" jumps to the Balance tab.
  final VoidCallback? onPayNow;

  @override
  State<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends State<TripListScreen> with WidgetsBindingObserver {
  static const _upiSettings = MethodChannel('tripsplit/upi_settings');
  static const _homeTripCount = 4;

  final _store = TripStore.instance;
  bool _upiDetection = true;
  bool _upiAlertsOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_onStore);
    _store.refresh();
    _checkUpiDetection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the Settings app where SMS may have just been allowed —
    // re-check so the "Auto-add UPI payments" banner clears itself.
    if (state == AppLifecycleState.resumed) {
      _checkUpiDetection();
      _store.refresh();
    }
  }

  Future<void> _checkUpiDetection() async {
    final granted = await Permission.sms.isGranted;
    bool on;
    try {
      on = await _upiSettings.invokeMethod<bool>('isEnabled') ?? true;
    } on Exception {
      on = true;
    }
    if (mounted) {
      setState(() {
        _upiDetection = granted;
        _upiAlertsOn = on;
      });
    }
  }

  /// The home screen's UPI alerts switch. Switching on without SMS access runs
  /// the set-up flow; the switch then reads on only once access is granted
  /// (re-checked on resume). Switching off keeps the permission, just silences
  /// the alerts in the native receiver.
  Future<void> _setUpiAlerts(bool on) async {
    setState(() => _upiAlertsOn = on);
    try {
      await _upiSettings.invokeMethod<void>('setEnabled', on);
    } on Exception {
      // Setting stays as it was; the switch re-syncs on the next check.
    }
    if (on && !_upiDetection) await _enableUpiDetection();
  }

  Future<void> _enableUpiDetection() async {
    final result = await [Permission.sms, Permission.notification].request();
    final sms = result[Permission.sms] ?? PermissionStatus.denied;
    // On a build installed from outside the Play Store, Play Protect treats SMS
    // as a restricted permission and auto-denies the request — the toggle in
    // Settings stays greyed out until the user turns on "Allow restricted
    // settings" first. A plain openAppSettings() drops them there with no clue
    // how to proceed, so when SMS didn't get granted we spell the steps out.
    if (!sms.isGranted && mounted) {
      await _showSmsHelpDialog();
    }
    await _checkUpiDetection();
  }

  Future<void> _showSmsHelpDialog() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Allow SMS access',
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: const Text(
        'Because TripSplit is installed outside the Play Store, Android keeps '
        'SMS access switched off and greys out the toggle. Turn it on by hand:\n\n'
        '1.  Tap “Open settings” below.\n'
        '2.  On the App info screen, tap ⋮ in the top-right corner.\n'
        '3.  Choose “Allow restricted settings”.\n'
        '4.  Open Permissions → SMS → Allow.\n\n'
        'Then come back here — the banner will disappear once it’s on.',
        style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now', style: TextStyle(color: muted)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  Future<void> _openActivity() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ActivityScreen(onOpenTrip: (id) => openTripById(context, id))));

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser;
    final trips = _store.trips;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: accent,
          onRefresh: _store.refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Home',
                              style: TextStyle(
                                color: ink,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                            if (user != null)
                              Text(
                                'Hi, ${user.name.split(' ').first}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: muted, fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                      _bell(),
                    ],
                  ),
                ),
              ),
              if (trips != null && trips.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _overviewCard()),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(child: _upiCard()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 22, 14, 10),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Your splits',
                    action: trips != null && trips.isNotEmpty ? 'See all splits' : null,
                    onAction: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AllTripsScreen())),
                  ),
                ),
              ),
              if (_store.error != null && trips == null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(_store.error!, style: const TextStyle(color: negative)),
                  ),
                )
              else if (trips == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: accent)),
                )
              else if (trips.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverToBoxAdapter(child: _emptyTrips()),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList.separated(
                    itemCount: trips.length.clamp(0, _homeTripCount),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => TripCard(trip: trips[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showNewTripMenu(context),
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'New split',
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _bell() {
    final unread = _store.unreadCount;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: _openActivity,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: negative,
        child: const Icon(Icons.notifications_none_rounded, color: ink, size: 26),
      ),
    );
  }

  Widget _overviewCard() {
    final totals = _store.totals;
    final net = totals.owed - totals.owing;
    final owing = totals.owing >= 0.5;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              IconCircle(icon: Icons.donut_large_outlined, size: 42),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your splits overview',
                  style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Total balance', style: TextStyle(color: muted, fontSize: 13)),
              const Spacer(),
              AmountPill(value: net, fontSize: 15),
            ],
          ),
          if (totals.owed >= 0.5 && owing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'You are owed ${money(totals.owed)} · you owe ${money(totals.owing)}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: line),
          ),
          InkWell(
            onTap: owing
                ? widget.onPayNow
                : () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Nothing to pay — you don’t owe anyone right now.'))),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.payments_outlined, size: 18, color: owing ? accent : muted),
                  const SizedBox(width: 8),
                  Text(
                    owing ? 'Pay bill now' : 'No bills to pay',
                    style: TextStyle(color: owing ? accent : muted, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (owing) const Icon(Icons.north_east_rounded, size: 16, color: accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upiCard() {
    final active = _upiDetection && _upiAlertsOn;
    final subtitle = !_upiDetection
        ? 'Needs SMS access — switch on to set it up.'
        : _upiAlertsOn
        ? 'On — a tap-to-add alert for each UPI payment.'
        : 'Off — UPI payments won’t send alerts.';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: cardDecoration(),
      child: Row(
        children: [
          IconCircle(
            icon: active ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            color: active ? accent : muted,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPI payment alerts',
                  style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 1),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    style: const TextStyle(color: muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: active, onChanged: _setUpiAlerts, activeThumbColor: Colors.white, activeTrackColor: accent),
        ],
      ),
    );
  }

  Widget _emptyTrips() => Container(
    padding: const EdgeInsets.all(20),
    decoration: cardDecoration(),
    child: Column(
      children: [
        const IconCircle(icon: Icons.luggage_outlined, size: 56),
        const SizedBox(height: 12),
        const Text(
          'No splits yet',
          style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Start a trip or join one with an invite code.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => showNewTripMenu(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New split'),
          style: primaryButton(),
        ),
      ],
    ),
  );
}

/// One trip on Home / "See all": icon by trip kind, date, total spent, then
/// the user's balance pill and the members' faces.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final net = TripStore.instance.myNet(trip.id);
    final kind = trip.tripKind;
    final date = trip.date;
    return AppCard(
      onTap: () => openTrip(context, trip),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                IconCircle(icon: kind.icon, color: kind.color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (date != null) formatDate(date),
                          if (trip.destination != null) trip.destination!,
                          if (date == null && trip.destination == null) kind.label,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(trip.totalSpent),
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text('spent', style: TextStyle(color: muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'Balance: ',
                          style: const TextStyle(color: muted, fontSize: 11.5),
                          children: [
                            TextSpan(
                              text: net == null
                                  ? '…'
                                  : net.abs() < 0.5
                                  ? 'Settled'
                                  : (net > 0 ? 'You’re owed' : 'You owe'),
                              style: const TextStyle(color: ink, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      if (net != null && net.abs() >= 0.5) ...[
                        const SizedBox(height: 5),
                        AmountPill(value: net, signed: false, fontSize: 12),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Sharing: ${trip.memberCount} ${trip.memberCount == 1 ? 'person' : 'persons'}',
                      style: const TextStyle(color: muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 4),
                    AvatarStack(members: trip.members, size: 22, max: 4),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "See all splits": every trip, filterable by kind.
class AllTripsScreen extends StatefulWidget {
  const AllTripsScreen({super.key});

  @override
  State<AllTripsScreen> createState() => _AllTripsScreenState();
}

class _AllTripsScreenState extends State<AllTripsScreen> {
  final _store = TripStore.instance;
  String? _kind;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final all = _store.trips ?? const <Trip>[];
    final kinds = {for (final t in all) t.tripKind.id};
    final shown = all
        .where((t) => _kind == null || t.tripKind.id == _kind)
        .where((t) => _query.isEmpty || t.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        surfaceTintColor: paper,
        title: const Text('All splits', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: accent,
        onRefresh: _store.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: appInputDecoration('Search splits', Icons.search_rounded),
            ),
            if (kinds.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip('All', null),
                    for (final k in tripKinds)
                      if (kinds.contains(k.id)) _chip(k.label, k.id, k.icon),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('No splits match.', style: TextStyle(color: muted)),
                ),
              ),
            for (final t in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TripCard(trip: t),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String? id, [IconData? icon]) {
    final selected = _kind == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? accent : muted),
        selected: selected,
        onSelected: (_) => setState(() => _kind = id),
        showCheckmark: false,
        backgroundColor: Colors.white,
        selectedColor: accentSoft,
        side: BorderSide(color: selected ? accent.withValues(alpha: .4) : line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(color: selected ? accent : ink, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet();

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _name = TextEditingController();
  final _destination = TextEditingController();
  String _kind = tripKinds.first.id;
  DateTime? _start;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the trip a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await ApiClient.instance.createTrip(
        name: name,
        destination: _destination.text.trim().isEmpty ? null : _destination.text.trim(),
        kind: _kind,
        startDate: _start == null
            ? null
            : '${_start!.year}-${_start!.month.toString().padLeft(2, '0')}-${_start!.day.toString().padLeft(2, '0')}',
      );
      if (mounted) Navigator.pop(context, trip);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 22),
              const Text(
                'Start a new split',
                style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
              ),
              const SizedBox(height: 23),
              fieldLabel('TRIP NAME'),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: appInputDecoration('e.g. Gujarat Trip', Icons.edit_outlined),
              ),
              const SizedBox(height: 18),
              fieldLabel('TYPE'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final k in tripKinds)
                    ChoiceChip(
                      label: Text(k.label),
                      avatar: Icon(k.icon, size: 16, color: _kind == k.id ? k.color : muted),
                      selected: _kind == k.id,
                      onSelected: (_) => setState(() => _kind = k.id),
                      showCheckmark: false,
                      backgroundColor: Colors.white,
                      selectedColor: k.color.withValues(alpha: .12),
                      side: BorderSide(color: _kind == k.id ? k.color.withValues(alpha: .45) : line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kind == k.id ? ink : muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              fieldLabel('STARTS (OPTIONAL)'),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _start ?? now,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) setState(() => _start = picked);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  decoration: cardDecoration(radius: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 18, color: muted),
                      const SizedBox(width: 10),
                      Text(
                        _start == null ? 'Today' : formatDate(_start!),
                        style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              fieldLabel('DESTINATION (OPTIONAL)'),
              const SizedBox(height: 8),
              TextField(
                controller: _destination,
                textCapitalization: TextCapitalization.words,
                decoration: appInputDecoration('e.g. Ahmedabad', Icons.location_on_outlined),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  style: primaryButton(radius: 16),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create trip', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinTripSheet extends StatefulWidget {
  const _JoinTripSheet();

  @override
  State<_JoinTripSheet> createState() => _JoinTripSheetState();
}

class _JoinTripSheetState extends State<_JoinTripSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter an invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await ApiClient.instance.joinTrip(code);
      if (mounted) Navigator.pop(context, trip);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 22),
              const Text(
                'Join a trip',
                style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
              ),
              const SizedBox(height: 5),
              const Text(
                'Ask whoever created the trip for their invite code.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 23),
              fieldLabel('INVITE CODE'),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: appInputDecoration('e.g. HVHKBJ', Icons.key_outlined),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _join,
                  style: primaryButton(radius: 16),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Join trip', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
