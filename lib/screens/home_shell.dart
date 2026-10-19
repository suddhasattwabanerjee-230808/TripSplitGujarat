import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'balance_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';
import 'trip_home_screen.dart';
import 'trip_list_screen.dart';

/// The signed-in app: Home, Add expense, Balance, Statistics, Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Tab indexes into the bar; "Add expense" (1) is an action, not a page.
  static const _home = 0, _add = 1, _balance = 2, _stats = 3, _profile = 4;
  int _tab = _home;

  /// Tabs are built the first time they're opened, then kept alive.
  final _visited = <int>{_home};

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

  /// Picks the trip (skipped when there's only one), then opens the form.
  Future<void> _addExpense() async {
    final store = TripStore.instance;
    if (store.trips == null) await store.refresh();
    if (!mounted) return;
    final trips = store.trips ?? const <Trip>[];
    if (trips.isEmpty) {
      await showNewTripMenu(context);
      return;
    }
    Trip? trip = trips.length == 1 ? trips.first : null;
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
    _home => TripListScreen(onPayNow: () => _select(_balance)),
    _balance => BalanceScreen(onOpenTrip: (id) => openTripById(context, id)),
    _stats => const StatsScreen(),
    _profile => const ProfileScreen(embedded: true),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          for (final index in [_home, _balance, _stats, _profile])
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
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
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
