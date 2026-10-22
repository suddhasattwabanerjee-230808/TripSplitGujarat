import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../city_photo.dart';
import '../expense_notifier.dart';
import '../models.dart';
import '../settle_watch.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'expense_screen.dart';
import 'expenses_screen.dart';
import 'profile_screen.dart';
import 'settle_screen.dart';
import 'trip_home_screen.dart';
import 'trips_ui.dart';

/// The signed-in app: Trip (the current trip's dashboard — where the app
/// opens), Add expense and the trip's Expenses, on a floating bar that
/// shrinks to its icons while a page is scrolled. The profile opens from the
/// user's photo at the top of the Trip page; balances and stats from the
/// trip's quick actions.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Tab indexes into the bar; "Add expense" (1) is an action, not a page.
  // The app opens on the current trip's page, which is its dashboard.
  static const _trip = 0, _add = 1, _expenses = 2;
  int _tab = _trip;

  /// The bar shows just its icons while the page is scrolled down.
  bool _compact = false;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final compact = n.metrics.pixels > 24;
    if (compact != _compact) setState(() => _compact = compact);
    return false;
  }

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
    // A settle-up paid while TripSplit was closed (or killed in the background).
    SettleWatch.instance.check();
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
      _compact = false;
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
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScroll,
        child: Stack(
          children: [
            for (final index in [_trip, _expenses])
              if (_visited.contains(index))
                Offstage(
                  offstage: _tab != index,
                  child: TickerMode(enabled: _tab == index, child: _page(index)),
                ),
          ],
        ),
      ),
      bottomNavigationBar: _NavBar(
        current: _tab,
        compact: _compact,
        onSelect: _select,
        onExpand: () => setState(() => _compact = false),
      ),
    );
  }
}

/// The floating bar: a frosted pill above the bottom edge, with Add raised
/// in the middle. Full width with names at the top of a page; while the page
/// is scrolled it shrinks to a smaller pill of icons (tap it to open it out).
class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.compact, required this.onSelect, required this.onExpand});
  final int current;
  final bool compact;
  final ValueChanged<int> onSelect;
  final VoidCallback onExpand;

  static const _items = [
    (Icons.luggage_outlined, Icons.luggage_rounded, 'Trip'),
    (Icons.add_rounded, Icons.add_rounded, 'Add'),
    (Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Expenses'),
  ];

  static const _motion = Duration(milliseconds: 320);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.instance.dark;
    final full = math.min(MediaQuery.sizeOf(context).width - 32, 420.0);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Center(
          heightFactor: 1,
          child: GestureDetector(
            // In its small form, a tap between the icons opens it out again.
            onTap: compact ? onExpand : null,
            child: AnimatedContainer(
              duration: _motion,
              curve: _curve,
              width: compact ? 196 : full,
              height: compact ? 54 : 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: (dark ? Colors.black : wineDeep).withValues(alpha: dark ? .5 : .16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(color: (dark ? Colors.black : wineDeep).withValues(alpha: .06), blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: surface.withValues(alpha: dark ? .86 : .9),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: dark ? Colors.white.withValues(alpha: .07) : line.withValues(alpha: .8)),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(child: i == 1 ? _addButton() : _item(i)),
                      ],
                    ),
                  ),
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
      onTap: () => onSelect(1),
      child: AnimatedContainer(
        duration: _motion,
        curve: _curve,
        width: compact ? 42 : 50,
        height: compact ? 42 : 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [logoOrange, wineBright],
          ),
          boxShadow: [BoxShadow(color: wine.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 26, semanticLabel: 'Add Expense'),
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
            child: Icon(
              selected ? _items[i].$2 : _items[i].$1,
              size: 22,
              color: selected ? accent : muted,
              semanticLabel: _items[i].$3,
            ),
          ),
          // The name, folded away in the small form.
          AnimatedSize(
            duration: _motion,
            curve: _curve,
            child: compact
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _items[i].$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? ink : muted,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
