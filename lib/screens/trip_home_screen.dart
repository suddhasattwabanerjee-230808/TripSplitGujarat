import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../location_service.dart';
import '../models.dart';
import '../receipt_scanner.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'activity_screen.dart';
import 'location_picker_screen.dart';
import 'stats_screen.dart';
import 'trips_ui.dart';

class TripHomeScreen extends StatefulWidget {
  const TripHomeScreen({super.key, required this.tripId, required this.tripName, this.embedded = false});
  final int tripId;
  final String tripName;

  /// Shown as the Trip tab: a trip switcher and the bell instead of a back arrow.
  final bool embedded;

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
  late int _seenRevision = _store.revision;
  Future<void>? _inFlight;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.rememberTrip(widget.tripId);
    _store.addListener(_onStore);
    _loadAll();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  /// Reload when the shared data was refreshed elsewhere (a payment from the
  /// Balance tab, an expense added from the bottom bar); repaint for the bell.
  void _onStore() {
    if (!mounted) return;
    if (_store.revision != _seenRevision) {
      _seenRevision = _store.revision;
      _loadAll();
    } else {
      setState(() {});
    }
  }

  Future<void> _refreshEverything() async {
    await _store.refresh();
    await _loadAll();
  }

  /// One load at a time; callers arriving mid-load share it.
  Future<void> _loadAll() => _inFlight ??= _load().whenComplete(() => _inFlight = null);

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        ApiClient.instance.getTrip(widget.tripId),
        ApiClient.instance.listExpenses(widget.tripId),
        ApiClient.instance.getBalances(widget.tripId),
        ApiClient.instance.getSettlements(widget.tripId),
      ]);
      if (!mounted) return;
      setState(() {
        _trip = results[0] as Trip;
        _expenses = results[1] as List<TripExpense>;
        _balances = results[2] as List<Balance>;
        _settlements = results[3] as List<Settlement>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// Money spent on the trip, not counting settle-up payments.
  double get total => _expenses.where((e) => !e.isSettlement).fold(0, (sum, item) => sum + item.amount);

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

  Future<void> _editExpense(TripExpense expense) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExpenseSheet(tripId: widget.tripId, existing: expense),
    );
    if (updated == true) {
      await _loadAll();
    }
  }

  Future<void> _deleteExpense(TripExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text('“${expense.description}” — ${money(expense.amount)} will be removed for everyone on the trip.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: negative)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteExpense(widget.tripId, expense.id);
      await _loadAll();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  bool _requireOwnership(TripExpense expense) {
    if (expense.paidBy == ApiClient.instance.currentUser?.id) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You can only edit expenses you added.')),
    );
    return false;
  }

  Future<void> _quickEditDateTime(TripExpense expense) async {
    if (!_requireOwnership(expense)) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: expense.dateTime,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(expense.dateTime),
    );
    if (time == null || !mounted) return;
    final newDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ApiClient.instance.updateExpense(
        tripId: widget.tripId,
        expenseId: expense.id,
        description: expense.description,
        amount: expense.amount,
        category: expense.category,
        date: newDateTime.toIso8601String(),
        location: expense.location,
      );
      await _loadAll();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _quickEditLocation(TripExpense expense) async {
    if (!_requireOwnership(expense)) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initialLabel: expense.location)),
    );
    if (result == null || !mounted) return;
    try {
      await ApiClient.instance.updateExpense(
        tripId: widget.tripId,
        expenseId: expense.id,
        description: expense.description,
        amount: expense.amount,
        category: expense.category,
        date: expense.date,
        location: result,
      );
      await _loadAll();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showExpenseActions(TripExpense expense) async {
    final isOwn = expense.paidBy == ApiClient.instance.currentUser?.id;
    if (!isOwn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only edit or delete expenses you added.')),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: ink),
                title: const Text('Edit expense', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: negative),
                title: const Text(
                  'Delete expense',
                  style: TextStyle(fontWeight: FontWeight.w700, color: negative),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == 'edit') {
      await _editExpense(expense);
    } else if (action == 'delete') {
      await _deleteExpense(expense);
    }
  }

  static const _owe = negative;
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  AppUser? get _me => ApiClient.instance.currentUser;

  Balance? get _myBalance {
    for (final b in _balances) {
      if (b.userId == _me?.id) return b;
    }
    return null;
  }

  String _memberName(int id) {
    if (id == _me?.id) return 'You';
    return _trip?.member(id)?.name ?? 'Someone';
  }

  Widget _avatarFor(int userId, {double size = 30, double ring = 0}) {
    final member = _trip?.member(userId);
    return member != null
        ? MemberAvatar.of(member, size: size, ring: ring)
        : MemberAvatar(id: userId, name: _memberName(userId), size: size, ring: ring);
  }

  /// The user's debts on this trip, in the shape the shared Pay flow takes.
  List<Debt> get _myDebts {
    final me = _me;
    if (me == null || _trip == null) return [];
    return [
      for (final s in _settlements)
        if ((s.fromUserId ?? -1) == me.id || (s.fromUserId == null && s.fromUser == me.name))
          Debt(trip: _trip!, settlement: s, iOwe: true)
        else if ((s.toUserId ?? -1) == me.id || (s.toUserId == null && s.toUser == me.name))
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

  void _copyInvite(Trip trip) {
    Clipboard.setData(ClipboardData(text: trip.inviteCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invite code ${trip.inviteCode} copied — share it with your crew.')),
    );
  }

  Future<void> _sheet(String title, List<Widget> children) =>
      showAppSheet<void>(context, title: title, children: (_) => children);

  Widget _sheetCard(List<Widget> rows) => groupedCard(rows, indent: 58);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: paper,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }
    if (_error != null || _trip == null) {
      return Scaffold(
        backgroundColor: paper,
        appBar: AppBar(backgroundColor: paper),
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
                if (_expenses.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 0),
                    sliver: SliverToBoxAdapter(child: _emptyExpenses()),
                  )
                else
                  ..._monthSections(),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        isExtended: _fabExtended,
        backgroundColor: ink,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _topBar(Trip trip) => Row(
    children: [
      if (widget.embedded)
        TextButton.icon(
          onPressed: () => showTripSwitcher(context),
          icon: const Icon(Icons.swap_horiz_rounded, size: 20),
          label: const Text('Switch trip'),
          style: TextButton.styleFrom(
            foregroundColor: accent,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        )
      else
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: ink),
        ),
      const Spacer(),
      if (widget.embedded) _bell(),
      IconButton(
        tooltip: 'Copy invite code',
        onPressed: () => _copyInvite(trip),
        icon: const Icon(Icons.person_add_alt_outlined, color: ink),
      ),
    ],
  );

  Widget _bell() {
    final unread = _store.unreadCount;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ActivityScreen(onOpenTrip: _store.selectTrip)),
      ),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: negative,
        child: const Icon(Icons.notifications_none_rounded, color: ink),
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
        style: const TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.6, height: 1.15),
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
                if (trip.date != null) formatDate(trip.date!),
                if (trip.destination != null) trip.destination!,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          AvatarStack(members: trip.members, size: 20, max: 5),
        ],
      ),
    ],
  );

  Widget _balanceCard() {
    final mine = _myBalance;
    final net = mine?.netBalance ?? 0;
    final settled = net.abs() < 0.5;
    final debts = _myDebts;
    return Container(
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                IconCircle(
                  icon: settled ? Icons.check_circle_outline_rounded : Icons.account_balance_wallet_outlined,
                  color: settled ? positive : accent,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Balance summary', style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                      Text(
                        settled ? 'You’re all settled up' : (net > 0 ? 'You are owed' : 'You owe'),
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                AmountPill(value: net, fontSize: 15),
              ],
            ),
          ),
          if (debts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final d in debts) DebtRow(debt: d, onPaid: _loadAll),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Divider(height: 1, color: line),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                Expanded(child: _miniStat('Your share', money(mine?.totalOwed ?? 0))),
                Expanded(child: _miniStat('You paid', money(mine?.totalPaid ?? 0))),
                Expanded(child: _miniStat('Trip total', money(total))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _quickOperations(Trip trip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(padding: EdgeInsets.only(left: 2, bottom: 12), child: SectionHeader(title: 'Quick operations')),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _operation('Balance', Icons.account_balance_wallet_outlined, () => _showBalances(trip)),
          _operation('Add expense', Icons.post_add_rounded, _addExpense),
          _operation('Scan receipt', Icons.document_scanner_outlined, () => _addExpense(scan: true)),
          _operation(
            'View stats',
            Icons.insights_outlined,
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StatsScreen(trip: trip, expenses: _expenses)),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _operation(String label, IconData icon, VoidCallback onTap) => SizedBox(
    width: 76,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: line),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _emptyExpenses() => const Column(
    children: [
      IconCircle(icon: Icons.receipt_long_outlined, size: 64),
      SizedBox(height: 14),
      Text('No expenses yet', style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
      SizedBox(height: 4),
      Text(
        'Add the first one — or scan a bill — and it’s split with everyone on the trip.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );

  List<Widget> _monthSections() {
    final sorted = [..._expenses]..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final groups = <String, List<TripExpense>>{};
    for (final e in sorted) {
      final d = e.dateTime;
      groups.putIfAbsent('${_monthNames[d.month - 1]} ${d.year}', () => []).add(e);
    }
    return [
      for (final (index, entry) in groups.entries.indexed) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(18, index == 0 ? 24 : 18, 18, 10),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  index == 0 ? 'Expenses · ${entry.key}' : entry.key,
                  style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  money(entry.value.where((e) => !e.isSettlement).fold<double>(0, (sum, e) => sum + e.amount)),
                  style: const TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: entry.value.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _expenseCard(entry.value[i]),
          ),
        ),
      ],
    ];
  }

  Widget _expenseCard(TripExpense expense) {
    final iPaid = expense.paidBy == _me?.id;
    final share = expense.shareOf(_me?.id ?? -1);
    final delta = iPaid ? expense.amount - share : share;
    final involved = (iPaid || share > 0) && delta >= 0.5;
    final catColor = colorForCategory(expense.category);
    final city = cityFromLocation(expense.location);
    final people = [
      for (final s in expense.shares)
        _trip?.member(s.userId) ?? TripMember(id: s.userId, name: _memberName(s.userId)),
    ];
    final String title;
    final String detail;
    if (expense.isSettlement) {
      final to = expense.shares.isEmpty ? null : expense.shares.first.userId;
      title = '${_memberName(expense.paidBy)} paid ${to == null ? 'back' : _memberName(to)}';
      detail = expense.description;
    } else {
      title = expense.description;
      detail = '${iPaid ? 'You' : expense.paidByName} paid${city == null ? '' : ' · $city'}';
    }
    return AppCard(
      onTap: () => _showExpenseDetails(expense),
      onLongPress: () => _showExpenseActions(expense),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconCircle(icon: expense.icon, color: catColor, size: 42, outlined: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateAndTime(expense.dateTime),
                  style: const TextStyle(color: muted, fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 11.5),
                      ),
                    ),
                    if (involved && !expense.isSettlement) ...[
                      const SizedBox(width: 6),
                      Text(
                        iPaid ? 'you lent ${money(delta)}' : 'you owe ${money(delta)}',
                        style: TextStyle(
                          color: iPaid ? positive : _owe,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(expense.amount),
                style: const TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              AvatarStack(
                members: expense.isSettlement
                    ? [_trip?.member(expense.paidBy) ?? TripMember(id: expense.paidBy, name: expense.paidByName), ...people]
                    : people,
                size: 20,
                max: 3,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBalances(Trip trip) {
    final debts = _myDebts;
    final others = _settlements.where((s) => !debts.any((d) => identical(d.settlement, s))).toList();
    _sheet('Balance', [
      if (_settlements.isEmpty)
        _sheetCard([
          const ListTile(
            leading: Icon(Icons.check_circle_outline_rounded, color: positive),
            title: Text('Everyone’s settled up', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
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
                  s.fromUserId != null ? _avatarFor(s.fromUserId!, size: 28) : MemberAvatar(id: 0, name: s.fromUser, size: 28),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                  ),
                  s.toUserId != null ? _avatarFor(s.toUserId!, size: 28) : MemberAvatar(id: 1, name: s.toUser, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${s.fromUser} → ${s.toUser}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(money(s.amount), style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 8),
        const Text(
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
    return Padding(
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
                  isMe ? '${member.name} (you)' : member.name,
                  style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  'paid ${money(b.totalPaid)} · share ${money(b.totalOwed)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          AmountPill(value: b.netBalance, fontSize: 12),
        ],
      ),
    );
  }

  void _showExpenseDetails(TripExpense expense) {
    final isOwn = expense.paidBy == _me?.id;
    final catColor = colorForCategory(expense.category);
    final shares = [...expense.shares]..sort((a, b) => (a.userId == _me?.id ? 0 : 1) - (b.userId == _me?.id ? 0 : 1));
    _sheet(expense.description, [
      Row(
        children: [
          IconCircle(icon: expense.icon, color: catColor, size: 48, outlined: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  money(expense.amount),
                  style: const TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.6),
                ),
                Text(
                  '${isOwn ? 'You' : expense.paidByName} paid · ${expense.category ?? 'Other'}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _sheetCard([
        _detailRow(Icons.schedule_outlined, formatDateAndTime(expense.dateTime), isOwn
            ? () {
                Navigator.pop(context);
                _quickEditDateTime(expense);
              }
            : null),
        _detailRow(Icons.location_on_outlined, expense.location ?? 'No location', isOwn
            ? () {
                Navigator.pop(context);
                _quickEditLocation(expense);
              }
            : null),
      ]),
      const SizedBox(height: 18),
      fieldLabel(expense.isSettlement ? 'PAID TO' : 'SPLIT'),
      const SizedBox(height: 8),
      _sheetCard([
        for (final s in shares)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                _avatarFor(s.userId, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.userId == expense.paidBy
                        ? '${_memberName(s.userId)} paid ${money(expense.amount)}, owe${s.userId == _me?.id ? '' : 's'} ${money(s.shareAmount)}'
                        : '${_memberName(s.userId)} owe${s.userId == _me?.id ? '' : 's'} ${money(s.shareAmount)}',
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: s.userId == _me?.id ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ]),
      if (isOwn) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteExpense(expense);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _owe,
                  side: const BorderSide(color: Color(0xFFF3CDD2)),
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _editExpense(expense);
                },
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    ]);
  }

  Widget _detailRow(IconData icon, String text, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null) const Icon(Icons.edit_outlined, size: 15, color: muted),
        ],
      ),
    ),
  );
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, required this.tripId, this.existing, this.startWithScan = false});
  final int tripId;
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
  late String _category = widget.existing?.category ?? 'Food';
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
        backgroundColor: Colors.white,
        title: const Text('New category', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
      setState(() => _category = existing);
      return;
    }
    setState(() {
      _custom = [..._custom, name];
      _category = name;
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
        if (result.category != null && result.category != 'Other') _category = result.category!;
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
        onSelected: (_) => setState(() => _category = c),
        showCheckmark: false,
        selectedColor: color.withValues(alpha: .12),
        backgroundColor: Colors.white,
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
        backgroundColor: Colors.white,
        title: Text('Remove “$c”?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: const Text('It disappears from this list. Expenses already saved with it keep it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: negative)),
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
                  style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
                ),
              ),
              trailing ?? const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      decoration: const BoxDecoration(color: paper, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                          widget.isEditing ? 'Edit expense' : 'Add an expense',
                          style: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
                        ),
                        const SizedBox(height: 3),
                        const Text('Split equally across everyone on the trip.', style: TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (!widget.isEditing)
                    PopupMenuButton<bool>(
                      tooltip: 'Scan receipt',
                      enabled: !_scanning,
                      color: Colors.white,
                      onSelected: (fromCamera) => _scan(fromCamera: fromCamera),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: true, child: Text('Take a photo of the bill')),
                        PopupMenuItem(value: false, child: Text('Choose from gallery')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: accentSoft, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _scanning
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                                : const Icon(Icons.document_scanner_outlined, size: 17, color: accent),
                            const SizedBox(width: 6),
                            Text(
                              _scanning ? 'Reading…' : 'Scan',
                              style: const TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w700),
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
                            const Icon(Icons.auto_awesome_outlined, size: 16, color: accent),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_scanNote!, style: const TextStyle(color: ink, fontSize: 12.5))),
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
                decoration: appInputDecoration('₹  0', Icons.currency_rupee_rounded),
              ),
              const SizedBox(height: 16),
              fieldLabel('CATEGORY'),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final c in categoryOrder) _categoryChip(c),
                  for (final c in _custom) _categoryChip(c, custom: true),
                  ActionChip(
                    label: const Text('New'),
                    avatar: const Icon(Icons.add_rounded, size: 16, color: accent),
                    onPressed: _addCustomCategory,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: accent.withValues(alpha: .35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
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
                text: _locatingNow ? 'Finding your location…' : (_location ?? 'Tap to choose on map'),
                onTap: _openLocationPicker,
                trailing: _locatingNow
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                    : null,
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
                  onPressed: _busy || _scanning ? null : _save,
                  style: primaryButton(radius: 16),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(widget.isEditing ? 'Save changes' : 'Save expense'),
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
          tripId: widget.tripId,
          expenseId: widget.existing!.id,
          description: title,
          amount: amount,
          category: _category,
          date: _dateTime.toIso8601String(),
          location: _location,
        );
      } else {
        await ApiClient.instance.createExpense(
          tripId: widget.tripId,
          description: title,
          amount: amount,
          category: _category,
          date: _dateTime.toIso8601String(),
          location: _location,
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
