import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'balance_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';
import 'trip_home_screen.dart';
import 'trips_ui.dart';

/// The signed-in app: Trip (the current trip — where the app opens), Add
/// expense, Balance, Statistics, Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Tab indexes into the bar; "Add expense" (1) is an action, not a page.
  static const _trip = 0, _add = 1, _balance = 2, _stats = 3, _profile = 4;
  int _tab = _trip;

  /// Tabs are built the first time they're opened, then kept alive.
  final _visited = <int>{_trip};
  final _store = TripStore.instance;
  String? _shownTripId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.addListener(_onStore);
    _store.refresh();
    _acceptInvites();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_onStore);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _store.refresh();
      _acceptInvites();
    }
  }

  bool _acceptingInvites = false;

  /// Someone invited this Gmail address by email: join their trip and open it.
  Future<void> _acceptInvites() async {
    if (_acceptingInvites) return;
    _acceptingInvites = true;
    try {
      final joined = await ApiClient.instance.acceptEmailInvites();
      if (!mounted || joined.isEmpty) return;
      final last = joined.last;
      _store.selectTrip(last.trip.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You’ve joined ${last.trip.name}, invited by ${last.invitedBy}.')),
      );
    } finally {
      _acceptingInvites = false;
    }
  }

  /// Picking a trip anywhere (Profile, Balance, the bell) brings up the Trip tab.
  void _onStore() {
    if (!mounted) return;
    final id = _store.currentTripId;
    setState(() {
      if (id != null && _shownTripId != null && id != _shownTripId) _tab = _trip;
      _shownTripId = id;
    });
  }

  void _select(int index) {
    if (index == _add) {
      _addExpense();
      return;
    }
    setState(() {
      _tab = index;
      _visited.add(index);
    });
  }

  /// Adds to the current trip; asks which trip only if none is picked yet.
  Future<void> _addExpense() async {
    final store = TripStore.instance;
    if (store.trips == null) await store.refresh();
    if (!mounted) return;
    final trips = store.trips ?? const <Trip>[];
    if (trips.isEmpty) {
      await showNewTripMenu(context);
      return;
    }
    Trip? trip = store.currentTrip ?? (trips.length == 1 ? trips.first : null);
    trip ??= await showAppSheet<Trip>(
      context,
      title: 'Add an expense to…',
      children: (ctx) => [
        groupedCard([
          for (final t in trips)
            InkWell(
              onTap: () => Navigator.pop(ctx, t),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    IconCircle(icon: t.tripKind.icon, color: t.tripKind.color, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                    AvatarStack(members: t.members, size: 20, max: 3),
                  ],
                ),
              ),
            ),
        ], indent: 64),
      ],
    );
    if (trip == null || !mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpenseSheet(tripId: trip!.id),
    );
    if (saved == true) await store.refresh();
  }

  Widget _page(int index) => switch (index) {
    _trip => _tripPage(),
    _balance => BalanceScreen(onOpenTrip: _store.selectTrip),
    _stats => const StatsScreen(),
    _profile => const ProfileScreen(embedded: true),
    _ => const SizedBox.shrink(),
  };

  Widget _tripPage() {
    final trip = _store.currentTrip;
    if (trip != null) {
      return TripHomeScreen(key: ValueKey(trip.id), tripId: trip.id, tripName: trip.name, embedded: true);
    }
    if (_store.trips == null) {
      return _store.error == null
          ? const Center(child: CircularProgressIndicator(color: accent))
          : _message(Icons.cloud_off_outlined, 'Can’t reach the server', _store.error!, retry: true);
    }
    return _message(
      Icons.luggage_outlined,
      'No trips yet',
      'Start a trip, or join one with an invite code from a friend.',
    );
  }

  Widget _message(IconData icon, String title, String body, {bool retry = false}) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconCircle(icon: icon, size: 64),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 18),
            if (retry)
              FilledButton(onPressed: _store.refresh, style: primaryButton(), child: const Text('Retry'))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showJoinTrip(context),
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: const Text('Join trip'),
                    style: secondaryButton(),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => showCreateTrip(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New trip'),
                    style: primaryButton(),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          for (final index in [_trip, _balance, _stats, _profile])
            if (_visited.contains(index))
              Offstage(
                offstage: _tab != index,
                child: TickerMode(enabled: _tab == index, child: _page(index)),
              ),
        ],
      ),
      bottomNavigationBar: _NavBar(current: _tab, onSelect: _select),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.luggage_outlined, Icons.luggage_rounded, 'Trip'),
    (Icons.add_circle_outline_rounded, Icons.add_circle_rounded, 'Add expense'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Balance'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Statistics'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: line)),
        boxShadow: softShadow(ink, .04),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    radius: 36,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                            color: current == i ? accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            current == i ? _items[i].$2 : _items[i].$1,
                            size: i == 1 ? 26 : 23,
                            color: current == i || i == 1 ? accent : muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: current == i ? FontWeight.w700 : FontWeight.w500,
                            color: current == i ? ink : muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
