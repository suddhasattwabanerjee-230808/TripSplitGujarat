import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../category_guess.dart';
import '../city_photo.dart';
import '../ledger.dart';
import '../location_service.dart';
import '../models.dart';
import '../receipt_scanner.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../upi_alerts.dart';
import '../widgets.dart';
import 'activity_screen.dart';
import 'location_picker_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';
import 'trip_insights.dart';
import 'trip_people.dart';
import 'trips_ui.dart';

class TripHomeScreen extends StatefulWidget {
  const TripHomeScreen({
    super.key,
    required this.tripId,
    required this.tripName,
    this.embedded = false,
    this.onOpenExpenses,
  });
  final String tripId;
  final String tripName;

  /// Shown as the Trip tab: a trip switcher and the bell instead of a back arrow.
  final bool embedded;

  /// Opens the Expenses tab (where this trip's expenses are listed).
  final VoidCallback? onOpenExpenses;

  @override
  State<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends State<TripHomeScreen> {
  Trip? _trip;
  List<TripExpense> _expenses = [];
  List<Balance> _balances = [];
  List<Settlement> _settlements = [];
  bool _loading = true;
  String? _error;
  bool _fabExtended = true;

  final _store = TripStore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _expensesSub;
  bool _gotExpenses = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.rememberTrip(widget.tripId);
    _trip = _store.trips?.where((t) => t.id == widget.tripId).firstOrNull;
    _store.addListener(_onStore);
    _expensesSub = ApiClient.instance.watchExpenseSnapshots(widget.tripId).listen(_onExpenses, onError: _onError);
    if (_trip == null) _loadAll();
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _store.removeListener(_onStore);
    super.dispose();
  }

  /// Trip details (members, name) arrive live through the store; the bell
  /// repaints from it too.
  void _onStore() {
    if (!mounted) return;
    final trip = _store.trips?.where((t) => t.id == widget.tripId).firstOrNull;
    setState(() {
      if (trip != null) _trip = trip;
      _recompute();
    });
  }

  void _onExpenses(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    setState(() {
      _expenses = snap.docs.map(TripExpense.fromDoc).toList();
      _gotExpenses = true;
      _error = null;
      _recompute();
    });
    // Fix the trip's running totals if they drifted, using server-confirmed data only.
    if (_trip != null && !snap.metadata.isFromCache && !snap.metadata.hasPendingWrites) {
      ApiClient.instance.repairTotals(_trip!, _expenses).catchError((Object _) {});
    }
  }

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e is ApiException ? e.message : 'Couldn’t load this trip.';
      _loading = false;
    });
  }

  /// Balances come straight from the expenses (the source of truth).
  void _recompute() {
    final trip = _trip;
    _loading = trip == null || !_gotExpenses;
    if (trip == null) return;
    final totals = totalsFromExpenses(_expenses);
    _balances = balancesFor(trip.members, totals.paid, totals.owed);
    _settlements = settlementsFor(_balances);
  }

  /// Everything is live; this only re-reads the trip itself (pull to refresh,
  /// or when it isn't in the store yet).
  Future<void> _loadAll() async {
    try {
      final trip = await ApiClient.instance.getTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _recompute();
      });
    } on ApiException catch (e) {
      _onError(e);
    }
  }

  Future<void> _refreshEverything() => _loadAll();

  /// Money spent on the trip, not counting settle-up payments.
  double get total => _expenses.where((e) => !e.isSettlement).fold(0, (acc, item) => acc + item.amount);

  Future<void> _addExpense({bool scan = false}) async {
    if (_trip == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExpenseSheet(tripId: widget.tripId, startWithScan: scan),
    );
    if (created == true) {
      await _loadAll();
    }
  }

  AppUser? get _me => ApiClient.instance.currentUser;

  Balance? get _myBalance {
    for (final b in _balances) {
      if (b.userId == _me?.id) return b;
    }
    return null;
  }

  String _memberName(String id) {
    if (id == _me?.id) return 'You';
    return _trip?.member(id)?.name ?? 'Someone';
  }

  Widget _avatarFor(String userId, {double size = 30, double ring = 0}) {
    final member = _trip?.member(userId);
    return member != null
        ? MemberAvatar.of(member, size: size, ring: ring, tripId: widget.tripId)
        : MemberAvatar(id: userId, name: _memberName(userId), size: size, ring: ring);
  }

  /// The user's debts on this trip, in the shape the shared Pay flow takes.
  List<Debt> get _myDebts {
    final me = _me;
    if (me == null || _trip == null) return [];
    return [
      for (final s in _settlements)
        if (s.fromUserId == me.id)
          Debt(trip: _trip!, settlement: s, iOwe: true)
        else if (s.toUserId == me.id)
          Debt(trip: _trip!, settlement: s, iOwe: false),
    ];
  }

  bool _onScroll(UserScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.direction == ScrollDirection.reverse && _fabExtended) {
      setState(() => _fabExtended = false);
    } else if ((notification.direction == ScrollDirection.forward || notification.metrics.pixels <= 0) &&
        !_fabExtended) {
      setState(() => _fabExtended = true);
    }
    return false;
  }

  Future<void> _sheet(String title, List<Widget> children) =>
      showAppSheet<void>(context, title: title, children: (_) => children);

  Widget _sheetCard(List<Widget> rows) => groupedCard(rows, indent: 58);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: paper,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    if (_error != null || _trip == null) {
      return Scaffold(
        backgroundColor: paper,
        appBar: AppBar(backgroundColor: paper, actions: const [ThemeToggle()]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Could not load this trip.', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton(onPressed: _loadAll, style: primaryButton(), child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }
    final trip = _trip!;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: accent,
          onRefresh: _refreshEverything,
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 6, 0),
                  sliver: SliverToBoxAdapter(child: _topBar(trip)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
                  sliver: SliverToBoxAdapter(child: _title(trip)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(child: _balanceCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  sliver: SliverToBoxAdapter(child: _quickOperations(trip)),
                ),
                if (_expenses.any((e) => !e.isSettlement))
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 26),
                    sliver: SliverToBoxAdapter(child: TripInsights(trip: trip, expenses: _expenses)),
                  ),
                // The expenses themselves live on the Expenses tab.
                if (_expenses.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 0),
                    sliver: SliverToBoxAdapter(child: _emptyExpenses()),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    sliver: SliverToBoxAdapter(child: _expensesLink()),
                  ),
                // Clear of the floating nav bar and the Add expense button.
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 84)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        isExtended: _fabExtended,
        backgroundColor: ink,
        foregroundColor: paper,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _topBar(Trip trip) => Row(
    children: [
      if (widget.embedded)
        TextButton.icon(
          onPressed: () => showTripSwitcher(context),
          icon: const Icon(Icons.swap_horiz_rounded, size: 20),
          label: const Text('Switch Trip'),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        )
      else
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: ink),
        ),
      const Spacer(),
      const ThemeToggle(),
      if (widget.embedded) _bell(),
      IconButton(
        tooltip: 'Trip Details',
        onPressed: () => _openDetails(trip),
        icon: Icon(Icons.info_outline_rounded, color: ink),
      ),
      if (widget.embedded) const Padding(padding: EdgeInsets.only(left: 4, right: 6), child: ProfileButton()),
    ],
  );

  Widget _bell() {
    final unread = _store.unreadCount;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ActivityScreen()),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: negative,
        child: Icon(Icons.notifications_none_rounded, color: ink),
      ),
    );
  }

  Widget _title(Trip trip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        trip.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.6, height: 1.15),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(trip.tripKind.icon, size: 15, color: trip.tripKind.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              [
                trip.tripKind.label,
                formatDate(DateTime.now()), // today, not the trip's start
                if (trip.destination != null) trip.destination!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    ],
  );

  void _openDetails(Trip trip) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailsScreen(tripId: trip.id)));

  /// The trip at a glance: what it cost (the one big number), your share and
  /// what you paid, where you stand, and anything you need to settle.
  Widget _balanceCard() {
    final trip = _trip!;
    final mine = _myBalance;
    final debts = _myDebts;
    return Column(
      children: [
        TripHeroCard(
          trip: trip,
          total: total,
          expenseCount: _expenses.where((e) => !e.isSettlement).length,
          share: mine?.totalOwed ?? 0,
          paid: mine?.totalPaid ?? 0,
          net: mine?.netBalance ?? 0,
          onSettle: () => _showBalances(trip),
          onMembers: () => _openDetails(trip),
        ),
        if (debts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: cardDecoration(radius: 20),
            child: Column(
              children: [
                for (final (i, d) in debts.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 60, color: line),
                  DebtRow(debt: d, onPaid: _loadAll),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _quickOperations(Trip trip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(padding: EdgeInsets.only(left: 2, bottom: 12), child: SectionHeader(title: 'Quick Operations')),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _operation('Balance', Icons.account_balance_wallet_outlined, () => _showBalances(trip)),
          // UPI payment alerts on or off: filled while on.
          ListenableBuilder(
            listenable: UpiAlerts.instance,
            builder: (context, _) {
              final on = UpiAlerts.instance.on;
              return _operation(
                on ? 'UPI Alerts On' : 'UPI Alerts Off',
                on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                () => UpiAlerts.instance.set(context, !on),
                active: on,
              );
            },
          ),
          _operation('Scan Receipt', Icons.document_scanner_outlined, () => _addExpense(scan: true)),
          _operation(
            'View Stats',
            Icons.insights_outlined,
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatsScreen(trip: trip, expenses: _expenses)),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _operation(String label, IconData icon, VoidCallback onTap, {bool active = false}) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: active ? accent : surface,
                shape: BoxShape.circle,
                border: Border.all(color: active ? accent : line),
                boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: .3), blurRadius: 12, offset: const Offset(0, 4))] : null,
              ),
              child: Icon(icon, color: active ? onAccent : accent, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ),
  );

  /// "All expenses": how many there are and the latest, opening the Expenses tab.
  Widget _expensesLink() {
    final latest = _expenses.reduce((a, b) => b.dateTime.isAfter(a.dateTime) ? b : a);
    final mine = _expenses.where((e) => e.paidBy == _me?.id).length;
    final open = widget.onOpenExpenses;
    return AppCard(
      onTap: open,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
        children: [
          const IconCircle(icon: Icons.receipt_long_rounded, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All ${_expenses.length} Expense${_expenses.length == 1 ? '' : 's'}',
                  style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Latest: ${latest.description} · ${timeAgo(latest.dateTime)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                Text(
                  '$mine Added By You · Search, Filter, Trip Mates',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (open != null) Icon(Icons.chevron_right_rounded, color: accent, size: 26),
        ],
      ),
    );
  }

  Widget _emptyExpenses() => Column(
    children: [
      const IconCircle(icon: Icons.receipt_long_outlined, size: 64),
      const SizedBox(height: 14),
      Text('No Expenses Yet', style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        'Add the first one — or scan a bill — and it’s split with everyone on the trip.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );

  void _showBalances(Trip trip) {
    final debts = _myDebts;
    final others = _settlements.where((s) => !debts.any((d) => identical(d.settlement, s))).toList();
    _sheet('Balance', [
      if (_settlements.isEmpty)
        _sheetCard([
          ListTile(
            leading: Icon(Icons.check_circle_outline_rounded, color: positive),
            title: Text('Everyone’s Settled Up', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          ),
        ])
      else ...[
        fieldLabel('SETTLE UP'),
        const SizedBox(height: 8),
        _sheetCard([
          for (final d in debts) DebtRow(debt: d, onPaid: () {
            Navigator.of(context).maybePop();
            _loadAll();
          }),
          for (final s in others)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  s.fromUserId != null ? _avatarFor(s.fromUserId!, size: 28) : MemberAvatar(id: s.fromUser, name: s.fromUser, size: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                  ),
                  s.toUserId != null ? _avatarFor(s.toUserId!, size: 28) : MemberAvatar(id: s.toUser, name: s.toUser, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${s.fromUser} → ${s.toUser}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(money(s.amount), style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          'The fewest payments that settle the whole trip. “Pay” opens your UPI app; the payment is recorded so balances update.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
      const SizedBox(height: 18),
      fieldLabel('EVERYONE'),
      const SizedBox(height: 8),
      _sheetCard([for (final m in trip.members) _balanceRow(m)]),
    ]);
  }

  Widget _balanceRow(TripMember member) {
    final b = _balances.firstWhere(
      (b) => b.userId == member.id,
      orElse: () => Balance(userId: member.id, name: member.name, totalPaid: 0, totalOwed: 0, netBalance: 0),
    );
    final isMe = member.id == _me?.id;
    return InkWell(
      onTap: () => openMember(context, widget.tripId, member.id),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          MemberAvatar.of(member, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${member.name} (You)' : member.name,
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Paid ${money(b.totalPaid)} · Share ${money(b.totalOwed)}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          AmountPill(value: b.netBalance, fontSize: 12),
        ],
      ),
      ),
    );
  }
}


/// The trip's hero card (the city photo on the brand gradient): the trip
/// total with everyone's faces beside it, your share and what you paid, and
/// where you stand.
class TripHeroCard extends StatelessWidget {
  const TripHeroCard({
    super.key,
    required this.trip,
    required this.total,
    required this.expenseCount,
    required this.share,
    required this.paid,
    required this.net,
    this.onSettle,
    this.onMembers,
  });
  final Trip trip;
  final double total, share, paid, net;
  final int expenseCount;
  final VoidCallback? onSettle, onMembers;

  @override
  Widget build(BuildContext context) {
    final settled = net.abs() < 0.5;
    final count = expenseCount;
    // The city the phone is in, blended into the brand gradient.
    return CityBackdrop(
      borderRadius: BorderRadius.circular(26),
      boxShadow: [BoxShadow(color: wine.withValues(alpha: .3), blurRadius: 30, offset: const Offset(0, 14))],
      child: Stack(
        children: [
          Positioned(right: -60, top: -70, child: _glow(200)),
          Positioned(right: 40, bottom: -90, child: _glow(160)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Trip Total',
                      style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    _heroChip('${trip.memberCount} People · $count Expense${count == 1 ? '' : 's'}'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(total),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Everyone on the trip: tap for the trip details page.
                    GestureDetector(
                      onTap: onMembers,
                      child: AvatarStack(
                        members: trip.members,
                        size: 32,
                        max: 4,
                        ringColor: Colors.white.withValues(alpha: .9),
                        extraColor: wineDeep,
                        extraTextColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _glass('Your Share', money(share))),
                    const SizedBox(width: 10),
                    Expanded(child: _glass('You Paid', money(paid))),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Icon(
                        settled ? Icons.check_circle_rounded : (net > 0 ? Icons.south_west_rounded : Icons.north_east_rounded),
                        size: 18,
                        color: settled ? const Color(0xFF0F8A4C) : (net > 0 ? const Color(0xFF0F8A4C) : const Color(0xFFD7344A)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          settled ? 'You’re All Settled Up' : (net > 0 ? 'You Get Back ${money(net)}' : 'You Owe ${money(-net)}'),
                          style: const TextStyle(color: Color(0xFF0F1222), fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ),
                      FilledButton(
                        onPressed: onSettle,
                        style: FilledButton.styleFrom(
                          backgroundColor: wine,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Settle Up', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [Colors.white.withValues(alpha: .14), Colors.white.withValues(alpha: 0)]),
    ),
  );

  Widget _heroChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
  );

  Widget _glass(String label, String value) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, required this.tripId, this.existing, this.startWithScan = false});
  final String tripId;
  final TripExpense? existing;

  /// Opens the camera straight away ("Scan receipt").
  final bool startWithScan;

  bool get isEditing => existing != null;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  static const _customKey = 'trip_split.custom_categories.v1';

  late final _title = TextEditingController(text: widget.existing?.description ?? '');
  late final _amount = TextEditingController(
    text: widget.existing != null ? widget.existing!.amount.toStringAsFixed(0) : '',
  );
  late String _category = widget.existing?.category ?? 'Other';
  // A new expense's category follows the description until a chip is tapped
  // (see followDescription); an edit starts from its saved category.
  late bool _categoryAuto = !widget.isEditing;
  late String _lastTitle = _title.text;
  // Who it's split between; null until changed, meaning everyone (new) or
  // whoever the expense was already split between (edit).
  Set<String>? _splitWith;
  late DateTime _dateTime = widget.existing?.dateTime ?? DateTime.now();
  List<String> _custom = [];
  String? _location;
  bool _locatingNow = false;
  bool _scanning = false;
  String? _scanNote;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onTitleChanged);
    _location = widget.existing?.location;
    _loadCustomCategories();
    if (widget.isEditing) {
      _refreshLocation();
    } else if (widget.startWithScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan(fromCamera: true));
    } else {
      _refreshLocation();
    }
  }

  void _onTitleChanged() {
    // The controller also fires on cursor moves; only re-guess on new text.
    if (_title.text == _lastTitle) return;
    _lastTitle = _title.text;
    final next = followDescription(current: _category, auto: _categoryAuto, description: _title.text);
    if (next.category == _category && next.auto == _categoryAuto) return;
    setState(() {
      _category = next.category;
      _categoryAuto = next.auto;
    });
  }

  List<TripMember> get _members => _tripForSheet?.members ?? const [];

  Set<String> _chosen(List<TripMember> members) =>
      _splitWith ??
      {
        for (final m in members)
          if (widget.existing == null || widget.existing!.shares.any((s) => s.userId == m.id)) m.id,
      };

  void _toggleSplit(TripMember member) {
    final chosen = {..._chosen(_members)};
    if (!chosen.remove(member.id)) chosen.add(member.id);
    if (chosen.isEmpty) return; // someone has to owe it
    setState(() => _splitWith = chosen);
  }

  Future<void> _loadCustomCategories() async {
    final saved = (await SharedPreferences.getInstance()).getStringList(_customKey) ?? [];
    final current = widget.existing?.category;
    if (!mounted) return;
    setState(() {
      _custom = [
        ...saved,
        if (current != null && !isBuiltInCategory(current) && !saved.contains(current)) current,
      ];
    });
  }

  Future<void> _addCustomCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: const Text('New Category', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.words,
          decoration: appInputDecoration('e.g. Gifts, Tickets, Medicine', Icons.sell_outlined),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: primaryButton(radius: 12),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final existing = [...categoryOrder, ..._custom].firstWhere(
      (c) => c.toLowerCase() == name.toLowerCase(),
      orElse: () => '',
    );
    if (existing.isNotEmpty) {
      setState(() {
        _category = existing;
        _categoryAuto = false;
      });
      return;
    }
    setState(() {
      _custom = [..._custom, name];
      _category = name;
      _categoryAuto = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customKey, [...(prefs.getStringList(_customKey) ?? []), name]);
  }

  Future<void> _removeCustomCategory(String name) async {
    setState(() {
      _custom = _custom.where((c) => c != name).toList();
      if (_category == name) _category = 'Other';
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customKey, (prefs.getStringList(_customKey) ?? []).where((c) => c != name).toList());
  }

  Future<void> _scan({required bool fromCamera}) async {
    setState(() {
      _scanning = true;
      _scanNote = null;
    });
    try {
      final result = await ReceiptScanner.scan(fromCamera: fromCamera);
      if (!mounted) return;
      if (result == null) {
        setState(() => _scanning = false);
        if (widget.startWithScan && _title.text.isEmpty) _refreshLocation();
        return;
      }
      setState(() {
        _scanning = false;
        if (result.isEmpty) {
          _scanNote = 'Couldn’t read that bill — try a sharper, flatter photo, or fill it in.';
          return;
        }
        if (result.title != null && _title.text.trim().isEmpty) _title.text = result.title!;
        if (result.amount != null) _amount.text = _plainAmount(result.amount!);
        if (result.date != null) _dateTime = result.date!;
        if (result.category != null && result.category != 'Other') {
          _category = result.category!;
          _categoryAuto = true;
        }
        _scanNote = result.amount == null
            ? 'Read the bill, but couldn’t find the total — enter it below.'
            : 'Filled in from the bill — check the amount before saving.';
      });
      if (_location == null) _refreshLocation();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scanNote = e.code == 'camera_access_denied'
              ? 'Camera access is off — allow it in Settings to scan bills.'
              : 'Couldn’t scan that bill (${e.message ?? e.code}).';
        });
      }
    }
  }

  /// The trip from the live store, so saving works offline (no fetch needed).
  Trip? get _tripForSheet => TripStore.instance.trips?.where((t) => t.id == widget.tripId).firstOrNull;

  String _plainAmount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _refreshLocation() async {
    setState(() => _locatingNow = true);
    final label = await fetchLocationLabel();
    if (!mounted) return;
    setState(() {
      _locatingNow = false;
      if (label != null) _location = label;
    });
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLabel: _location)),
    );
    if (result != null && mounted) setState(() => _location = result);
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Widget _splitSection() {
    final members = _members;
    if (members.length < 2 || (widget.existing?.isSettlement ?? false)) return const SizedBox.shrink();
    final chosen = _chosen(members);
    final everyone = chosen.length == members.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            fieldLabel('SPLIT BETWEEN'),
            const Spacer(),
            if (!everyone)
              GestureDetector(
                onTap: () => setState(() => _splitWith = {for (final m in members) m.id}),
                child: Text('Everyone', style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [for (final m in members) _memberChip(m, chosen.contains(m.id))],
        ),
        const SizedBox(height: 8),
        Text(_splitSummary(members, chosen), style: TextStyle(color: muted, fontSize: 12)),
      ],
    );
  }

  Widget _memberChip(TripMember member, bool selected) {
    final isMe = member.id == ApiClient.instance.currentUser?.id;
    return FilterChip(
      avatar: Opacity(opacity: selected ? 1 : .35, child: MemberAvatar.of(member, size: 22)),
      label: Text(isMe ? 'You' : member.name.trim().split(RegExp(r'\s+')).first),
      selected: selected,
      onSelected: (_) => _toggleSplit(member),
      showCheckmark: false,
      selectedColor: accentSoft,
      backgroundColor: surface,
      side: BorderSide(color: selected ? accent.withValues(alpha: .55) : line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? ink : muted),
    );
  }

  /// "₹600 Each · 2 Of 3 People", or who alone owes it.
  String _splitSummary(List<TripMember> members, Set<String> chosen) {
    final me = ApiClient.instance.currentUser?.id;
    if (chosen.length == 1) {
      final only = members.firstWhere((m) => m.id == chosen.first);
      return only.id == me
          ? 'Only you — this won’t change anyone’s balance.'
          : 'Only ${only.name.trim().split(RegExp(r'\s+')).first} owes this — you’re paying on their behalf.';
    }
    final everyone = chosen.length == members.length;
    final notMe = me != null && !chosen.contains(me);
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    // A sentence before there's an amount, a Title Case phrase after.
    if (amount == null || amount <= 0) {
      final who = everyone ? 'everyone' : '${chosen.length} of ${members.length} people';
      return 'Split equally between $who${notMe ? ' (not you)' : ''}.';
    }
    final who = everyone ? 'Everyone' : '${chosen.length} Of ${members.length} People';
    return '${money(amount / chosen.length)} Each · $who${notMe ? ' (Not You)' : ''}';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time == null) return;
    setState(() {
      _dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _categoryChip(String c, {bool custom = false}) {
    final selected = _category == c;
    final color = colorForCategory(c);
    return GestureDetector(
      onLongPress: custom ? () => _confirmRemove(c) : null,
      child: ChoiceChip(
        label: Text(c),
        avatar: Icon(iconForCategory(c), size: 16, color: selected ? color : muted),
        selected: selected,
        onSelected: (_) => setState(() {
          _category = c;
          _categoryAuto = false;
        }),
        showCheckmark: false,
        selectedColor: color.withValues(alpha: .12),
        backgroundColor: surface,
        side: BorderSide(color: selected ? color.withValues(alpha: .45) : line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? ink : muted),
      ),
    );
  }

  Future<void> _confirmRemove(String c) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        title: Text('Remove “$c”?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('It disappears from this list. Expenses already saved with it keep it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: negative)),
          ),
        ],
      ),
    );
    if (remove == true) _removeCustomCategory(c);
  }

  Widget _pickerRow({required IconData icon, required Color iconColor, required String text, required VoidCallback onTap, Widget? trailing}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
          decoration: cardDecoration(radius: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, color: muted, size: 18),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      decoration: BoxDecoration(color: paper, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isEditing ? 'Edit Expense' : 'Add An Expense',
                          style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
                        ),
                        const SizedBox(height: 3),
                        Text('Split equally between the people you pick.', style: TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (!widget.isEditing)
                    PopupMenuButton<bool>(
                      tooltip: 'Scan Receipt',
                      enabled: !_scanning,
                      color: surface,
                      onSelected: (fromCamera) => _scan(fromCamera: fromCamera),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: true, child: Text('Take A Photo Of The Bill')),
                        PopupMenuItem(value: false, child: Text('Choose From Gallery')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: accentSoft, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _scanning
                                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                                : Icon(Icons.document_scanner_outlined, size: 17, color: accent),
                            const SizedBox(width: 6),
                            Text(
                              _scanning ? 'Reading…' : 'Scan',
                              style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _scanNote == null
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: accentSoft, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome_outlined, size: 16, color: accent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_scanNote!, style: TextStyle(color: ink, fontSize: 12.5))),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              fieldLabel('WHAT WAS IT?'),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: appInputDecoration('e.g. Dinner at Manek Chowk', Icons.edit_outlined),
              ),
              const SizedBox(height: 16),
              fieldLabel('AMOUNT'),
              const SizedBox(height: 8),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}), // keeps "₹… each" current
                decoration: appInputDecoration('₹  0', Icons.currency_rupee_rounded),
              ),
              _splitSection(),
              const SizedBox(height: 16),
              Row(
                children: [
                  fieldLabel('CATEGORY'),
                  if (_categoryAuto) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.auto_awesome_outlined, size: 11, color: accent),
                    const SizedBox(width: 3),
                    Text('auto', style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final c in categoryOrder) _categoryChip(c),
                  for (final c in _custom) _categoryChip(c, custom: true),
                  ActionChip(
                    label: const Text('New'),
                    avatar: Icon(Icons.add_rounded, size: 16, color: accent),
                    onPressed: _addCustomCategory,
                    backgroundColor: surface,
                    side: BorderSide(color: accent.withValues(alpha: .35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              fieldLabel('WHEN'),
              const SizedBox(height: 9),
              _pickerRow(
                icon: Icons.schedule_outlined,
                iconColor: muted,
                text: formatDateAndTime(_dateTime),
                onTap: _pickDateTime,
              ),
              const SizedBox(height: 16),
              fieldLabel('LOCATION'),
              const SizedBox(height: 9),
              _pickerRow(
                icon: Icons.location_on_outlined,
                iconColor: accent,
                text: _locatingNow ? 'Finding Your Location…' : (_location ?? 'Tap To Choose On Map'),
                onTap: _openLocationPicker,
                trailing: _locatingNow
                    ? SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                    : null,
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy || _scanning ? null : _save,
                  style: primaryButton(radius: 16),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
                        )
                      : Text(widget.isEditing ? 'Save Changes' : 'Save Expense'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (title.isEmpty || amount == null || amount <= 0) {
      setState(() => _error = 'Add a name and a valid amount to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isEditing) {
        await ApiClient.instance.updateExpense(
          existing: widget.existing!,
          trip: _tripForSheet,
          description: title,
          amount: amount,
          category: _category,
          date: _dateTime.toIso8601String(),
          location: _location,
          splitWith: _splitWith?.toList(),
        );
      } else {
        await ApiClient.instance.createExpense(
          tripId: widget.tripId,
          trip: _tripForSheet,
          description: title,
          amount: amount,
          category: _category,
          date: _dateTime.toIso8601String(),
          location: _location,
          splitWith: _splitWith?.toList(),
        );
      }
      TripStore.instance.refresh();
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
