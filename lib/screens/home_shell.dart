import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../city_photo.dart';
import '../expense_notifier.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'balance_screen.dart';
import 'stats_screen.dart';
import 'expense_screen.dart';
import 'expenses_screen.dart';
import 'profile_screen.dart';
import 'settle_screen.dart';
import 'trip_home_screen.dart';
import 'trips_ui.dart';

/// The signed-in app: Trip (the current trip's dashboard — where the app
/// opens), its Expenses, Add expense, Balance, Statistics, on a floating bar.
/// The profile opens from the user's photo at the top of the Trip page.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Tab indexes into the bar; "Add expense" (2) is an action, not a page.
  // The app opens on the current trip's page, which is its dashboard.
  static const _trip = 0, _expenses = 1, _add = 2, _balance = 3, _stats = 4;
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
    _startNotifications();
    CityPhoto.instance.start();
  }

  static bool _launchHandled = false;

  /// Expense notifications on: permission, background check, and the
  /// expense whose notification opened the app (once per launch).
  Future<void> _startNotifications() async {
    unawaited(ExpenseNotifier.start().catchError((Object _) {}));
    if (_launchHandled) return;
    _launchHandled = true;
    final target = await ExpenseNotifier.launchTarget().catchError((Object _) => null);
    if (target != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => target.settle
              ? SettleScreen(tripId: target.tripId, otherId: target.id)
              : ExpenseScreen(tripId: target.tripId, expenseId: target.id),
        ),
      );
    }
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

  /// Picking a trip anywhere (Profile, Balance, the bell) brings up the Trip
  /// tab; switching trips on the Expenses tab stays there.
  void _onStore() {
    if (!mounted) return;
    final id = _store.currentTripId;
    setState(() {
      if (id != null && _shownTripId != null && id != _shownTripId && _tab != _expenses) {
        _tab = _trip;
        _visited.add(_trip); // it may not have been built yet (the app opens on Home)
      }
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
      title: 'Add An Expense To…',
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
                        style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
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
    _expenses => _expensesPage(),
    _balance => BalanceScreen(onOpenTrip: _store.selectTrip),
    _stats => const StatsScreen(),
    _ => const SizedBox.shrink(),
  };

  Widget _tripPage() {
    final trip = _store.currentTrip;
    if (trip != null) {
      return TripHomeScreen(
        key: ValueKey(trip.id),
        tripId: trip.id,
        tripName: trip.name,
        embedded: true,
        onOpenExpenses: () => _select(_expenses),
      );
    }
    return _noTrip();
  }

  Widget _expensesPage() {
    final trip = _store.currentTrip;
    if (trip != null) return ExpensesScreen(key: ValueKey(trip.id), tripId: trip.id);
    return _noTrip();
  }

  Widget _noTrip() {
    if (_store.trips == null) {
      return _store.error == null
          ? Center(child: CircularProgressIndicator(color: accent))
          : _message(Icons.cloud_off_outlined, 'Can’t Reach The Server', _store.error!, retry: true);
    }
    return _message(
      Icons.luggage_outlined,
      'No Trips Yet',
      'Start a trip, or join one with an invite code from a friend.',
    );
  }

  Widget _message(IconData icon, String title, String body, {bool retry = false}) => SafeArea(
    child: Stack(
      children: [
        // The profile (and sign-out) stays reachable without a trip.
        const Positioned(top: 8, right: 14, child: ProfileButton()),
        Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconCircle(icon: icon, size: 64),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13)),
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
                    label: const Text('Join Trip'),
                    style: secondaryButton(),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () => showCreateTrip(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Trip'),
                    style: primaryButton(),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      // The pages run on under the floating bar.
      extendBody: true,
      body: Stack(
        children: [
          for (final index in [_trip, _expenses, _balance, _stats])
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

/// The floating bar: a frosted pill above the bottom edge, with Add raised
/// in the middle.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.luggage_outlined, Icons.luggage_rounded, 'Trip'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Expenses'),
    (Icons.add_rounded, Icons.add_rounded, 'Add'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Balance'),
    (Icons.insights_outlined, Icons.insights_rounded, 'Stats'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.instance.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(color: (dark ? Colors.black : wineDeep).withValues(alpha: dark ? .5 : .16), blurRadius: 28, offset: const Offset(0, 10)),
              BoxShadow(color: (dark ? Colors.black : wineDeep).withValues(alpha: .06), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 66,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: surface.withValues(alpha: dark ? .86 : .9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: dark ? Colors.white.withValues(alpha: .07) : line.withValues(alpha: .8)),
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(child: i == 2 ? _addButton() : _item(i)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The main action, in the middle of the bar.
  Widget _addButton() => Center(
    child: GestureDetector(
      onTap: () => onSelect(2),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [logoOrange, wineBright],
          ),
          boxShadow: [BoxShadow(color: wine.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28, semanticLabel: 'Add Expense'),
      ),
    ),
  );

  Widget _item(int i) {
    final selected = current == i;
    return InkResponse(
      onTap: () => onSelect(i),
      radius: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(selected ? _items[i].$2 : _items[i].$1, size: 22, color: selected ? accent : muted),
          ),
          const SizedBox(height: 2),
          Text(
            _items[i].$3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? ink : muted,
            ),
          ),
        ],
      ),
    );
  }
}
