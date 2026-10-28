import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_resume.dart';
import '../city_photo.dart';
import '../expense_notifier.dart';
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
/// opens), Add expense (a page with the form) and the trip's Expenses, on a
/// floating bar whose open tab drops its name while a page is scrolled. The profile opens from the
/// user's photo at the top of the Trip page; balances and stats from the
/// trip's quick actions.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  // Tab indexes into the bar. The app opens on the current trip's page,
  // which is its dashboard.
  static const _trip = 0, _add = 1, _expenses = 2;
  int _tab = _trip;

  /// The bar shows just its icons while the page is scrolled down. A notifier,
  /// so only the bar rebuilds, not the pages under it.
  final _compact = ValueNotifier(false);

  /// Bumped after each saved expense, for a fresh, empty form.
  int _addRound = 0;

  bool _onScroll(ScrollUpdateNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _compact.value = n.metrics.pixels > 24;
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
    AppResume.fresh.addListener(_openTrip);
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
    AppResume.fresh.removeListener(_openTrip);
    _compact.dispose();
    _expensesTop.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _store.refresh();
      _acceptInvites();
      CityPhoto.instance.check(force: true);
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

  /// What the shell itself shows from the store; only a change in it
  /// rebuilds the shell (the pages follow the store on their own), so a
  /// tripmate's new expense doesn't rebuild every page.
  Object? _shown;

  /// Picking a trip anywhere (Profile, Balance, the bell) brings up the Trip
  /// tab; switching trips on the Expenses tab stays there.
  void _onStore() {
    if (!mounted) return;
    final id = _store.currentTripId;
    final trips = _store.trips;
    final shown = (id, _store.currentTrip?.name, trips == null, trips?.isEmpty, _store.error);
    if (shown == _shown) return;
    _shown = shown;
    setState(() {
      if (id != null && _shownTripId != null && id != _shownTripId && _tab != _expenses) {
        _tab = _trip;
        _visited.add(_trip); // it may not have been built yet (the app opens on Home)
      }
      _shownTripId = id;
    });
  }

  /// Back after a while away: the Trip tab (its page scrolls itself to the top).
  void _openTrip() => _select(_trip);

  /// Fires to scroll the Expenses page to the top.
  final _expensesTop = ValueNotifier(0);

  /// A new expense saved: the Expenses tab, at the top where it's listed.
  void _showNewExpense() {
    _select(_expenses);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _expensesTop.value++;
    });
  }

  void _select(int index) {
    _compact.value = false;
    if (index == _tab) return;
    setState(() {
      _tab = index;
      _visited.add(index);
    });
  }

  Widget _page(int index) => switch (index) {
    _trip => _tripPage(),
    _add => _addPage(),
    _expenses => _expensesPage(),
    _ => const SizedBox.shrink(),
  };

  /// The expense form for the current trip; once saved it says so and goes
  /// back to the trip.
  Widget _addPage() {
    final trip = _store.currentTrip ?? _store.trips?.firstOrNull;
    if (trip == null) return _noTrip();
    return Scaffold(
      backgroundColor: paper,
      body: ExpenseSheet(
        key: ValueKey('add-${trip.id}-$_addRound'),
        tripId: trip.id,
        asPage: true,
        onSaved: () {
          if (!mounted) return;
          setState(() => _addRound++);
          _showNewExpense();
        },
      ),
    );
  }

  Widget _tripPage() {
    final trip = _store.currentTrip;
    if (trip != null) {
      return TripHomeScreen(
        key: ValueKey(trip.id),
        tripId: trip.id,
        tripName: trip.name,
        embedded: true,
        onOpenExpenses: () => _select(_expenses),
        onExpenseAdded: _showNewExpense,
      );
    }
    return _noTrip();
  }

  Widget _expensesPage() {
    final trip = _store.currentTrip;
    if (trip != null) return ExpensesScreen(key: ValueKey(trip.id), tripId: trip.id, toTop: _expensesTop);
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
            for (final index in [_trip, _add, _expenses])
              if (_visited.contains(index))
                Offstage(
                  offstage: _tab != index,
                  child: TickerMode(enabled: _tab == index, child: _page(index)),
                ),
          ],
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _compact,
        builder: (context, compact, _) => _NavBar(current: _tab, compact: compact, onSelect: _select),
      ),
    );
  }
}

/// The floating bar: a pill of its tabs, as in ShotDrop. Trip and Expenses
/// are icons; the open one grows into a filled pill with its name, while ＋
/// (Add expense) in the middle never changes. While a page is scrolled the
/// open tab drops its name too. Out of the way while the keyboard is up.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.current, required this.compact, required this.onSelect});
  final int current;
  final bool compact;
  final ValueChanged<int> onSelect;

  /// Room between the three buttons, so the bar breathes.
  static const _gap = 18.0;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final dark = AppTheme.instance.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Center(
          heightFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              // Solid, not a live blur: blurring what scrolls behind it on
              // every frame made scrolling stutter.
              color: surface,
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: dark ? Colors.white.withValues(alpha: .08) : line),
              boxShadow: [
                BoxShadow(
                  color: (dark ? Colors.black : wineDeep).withValues(alpha: dark ? .5 : .16),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NavItem(
                  icon: Icons.luggage_outlined,
                  activeIcon: Icons.luggage_rounded,
                  label: 'Trip',
                  selected: current == 0,
                  showLabel: current == 0 && !compact,
                  onTap: () => onSelect(0),
                ),
                const SizedBox(width: _gap),
                _AddButton(onTap: () => onSelect(1)),
                const SizedBox(width: _gap),
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Expenses',
                  selected: current == 2,
                  showLabel: current == 2 && !compact,
                  onTap: () => onSelect(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add expense: the same round button whichever tab is open.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add Expense',
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [logoOrange, wineBright],
          ),
          boxShadow: [BoxShadow(color: wine.withValues(alpha: .35), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    ),
  );
}

/// One tab: its icon, or, when it's the open one, a filled pill with the
/// icon and its name (the name folds away while the page is scrolled).
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final IconData icon, activeIcon;
  final String label;
  final bool selected, showLabel;
  final VoidCallback onTap;

  static const _motion = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: _motion,
        curve: Curves.easeOutCubic,
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: showLabel ? 20 : 18),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? activeIcon : icon, color: selected ? onAccent : ink, size: 24),
            AnimatedSize(
              duration: _motion,
              curve: Curves.easeOutCubic,
              child: showLabel
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(color: onAccent, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    ),
  );
}
