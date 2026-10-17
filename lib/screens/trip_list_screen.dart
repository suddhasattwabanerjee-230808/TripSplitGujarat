import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../update_service.dart';
import 'login_screen.dart';
import 'trip_home_screen.dart';
import 'update_dialog.dart';

class TripListScreen extends StatefulWidget {
  const TripListScreen({super.key});

  @override
  State<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends State<TripListScreen> with WidgetsBindingObserver {
  static const _owe = Color(0xFFD1805C);

  List<Trip>? _trips;
  Map<int, double?> _myNet = {};
  String? _error;
  static const _upiSettings = MethodChannel('tripsplit/upi_settings');

  bool _upiDetection = true;
  bool _upiAlertsOn = true;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkUpiDetection();
    _loadPackageInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the Settings app where SMS may have just been allowed —
    // re-check so the "Auto-add UPI payments" banner clears itself.
    if (state == AppLifecycleState.resumed) _checkUpiDetection();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
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

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final trips = await ApiClient.instance.listTrips();
      if (!mounted) return;
      setState(() => _trips = trips);
      final nets = await Future.wait(trips.map((t) => _netFor(t.id)));
      if (mounted) setState(() => _myNet = {for (var i = 0; i < trips.length; i++) trips[i].id: nets[i]});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<double?> _netFor(int tripId) async {
    try {
      final me = ApiClient.instance.currentUser?.id;
      for (final b in await ApiClient.instance.getBalances(tripId)) {
        if (b.userId == me) return b.netBalance;
      }
      return 0;
    } on ApiException {
      return null;
    }
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripHomeScreen(tripId: trip.id, tripName: trip.name)),
    );
    _load();
  }

  Future<void> _createTrip() async {
    final created = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateTripSheet(),
    );
    if (created != null) {
      await _load();
      if (mounted) _openTrip(created);
    }
  }

  Future<void> _joinTrip() async {
    final joined = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JoinTripSheet(),
    );
    if (joined != null) {
      await _load();
      if (mounted) _openTrip(joined);
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    }
  }

  Future<void> _logOut() async {
    await ApiClient.instance.logOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TRIPSPLIT',
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                                letterSpacing: 2.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Hi, ${user?.name ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Check for updates',
                            onPressed: _checkForUpdate,
                            icon: const Icon(Icons.system_update_rounded, color: muted),
                          ),
                          if (_packageInfo != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFEDE3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  child: Text(
                                    'v${_packageInfo!.version} · build ${_packageInfo!.buildNumber}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Log out',
                        onPressed: _logOut,
                        icon: const Icon(Icons.logout_rounded, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (_trips != null && _trips!.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(child: _overallCard()),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(child: _upiCard()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _joinTrip,
                          icon: const Icon(Icons.group_add_rounded, size: 18),
                          label: const Text('Join trip'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFE4E1D6)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _createTrip,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New trip'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 22, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'YOUR TRIPS',
                    style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_error != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(_error!, style: const TextStyle(color: _owe)),
                  ),
                )
              else if (_trips == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: teal)),
                )
              else if (_trips!.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'No trips yet — start one or join with an invite code.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: softShadow(ink, .05),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _trips!.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 72, color: Color(0xFFEDEBE3)),
                            _tripRow(_trips![i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overallCard() {
    final known = _myNet.values.whereType<double>();
    final owed = known.where((v) => v > 0).fold<double>(0, (a, b) => a + b);
    final owing = known.where((v) => v < 0).fold<double>(0, (a, b) => a - b);
    final net = owed - owing;
    final settled = net.abs() < 0.5;
    final color = settled ? teal : (net > 0 ? teal : _owe);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: softShadow()),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settled ? 'Overall' : (net > 0 ? 'Overall, you are owed' : 'Overall, you owe'),
                  style: const TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  settled ? 'All settled up' : money(net.abs()),
                  style: TextStyle(
                    color: settled ? ink : color,
                    fontSize: settled ? 20 : 26,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (owed > 0.5 && owing > 0.5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(color: muted, fontSize: 12),
                        children: [
                          const TextSpan(text: 'owed '),
                          TextSpan(text: money(owed), style: const TextStyle(color: teal, fontWeight: FontWeight.w700)),
                          const TextSpan(text: '  ·  you owe '),
                          TextSpan(text: money(owing), style: const TextStyle(color: _owe, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(Icons.account_balance_wallet_rounded, color: color, size: 22),
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
            ? 'On — you get a tap-to-add alert for each UPI payment.'
            : 'Off — UPI payments won’t send alerts.';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE3F1EC) : const Color(0xFFEFEDE3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (active ? teal : muted).withValues(alpha: .15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              active ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              color: active ? teal : muted,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPI payment alerts',
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: _setUpiAlerts,
            activeThumbColor: Colors.white,
            activeTrackColor: teal,
          ),
        ],
      ),
    );
  }

  Widget _tripRow(Trip trip) {
    final net = _myNet[trip.id];
    final settled = net != null && net.abs() < 0.5;
    final color = net == null || settled ? muted : (net > 0 ? teal : _owe);
    final tile = memberPalette[trip.id % memberPalette.length];
    return InkWell(
      onTap: () => _openTrip(trip),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tile.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.landscape_rounded, color: Color.lerp(tile, ink, .35), size: 22),
            ),
            const SizedBox(width: 14),
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
                    '${trip.memberCount} people${trip.destination == null ? '' : ' · ${trip.destination}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_myNet.containsKey(trip.id))
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    net == null
                        ? ''
                        : settled
                        ? 'settled up'
                        : (net > 0 ? 'you are owed' : 'you owe'),
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  if (net != null && !settled)
                    Text(
                      money(net.abs()),
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
          ],
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9DED8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Start a new trip',
              style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
            const SizedBox(height: 23),
            fieldLabel('TRIP NAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: appInputDecoration('e.g. Gujarat Trip', Icons.edit_rounded),
            ),
            const SizedBox(height: 18),
            fieldLabel('DESTINATION (OPTIONAL)'),
            const SizedBox(height: 8),
            TextField(
              controller: _destination,
              textCapitalization: TextCapitalization.words,
              decoration: appInputDecoration('e.g. Ahmedabad', Icons.location_on_rounded),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9DED8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Join a trip',
              style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
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
              decoration: appInputDecoration('e.g. HVHKBJ', Icons.key_rounded),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _join,
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
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
    );
  }
}
