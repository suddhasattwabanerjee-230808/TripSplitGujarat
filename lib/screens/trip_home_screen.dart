import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../location_service.dart';
import '../models.dart';
import '../theme.dart';
import 'location_picker_screen.dart';

class TripHomeScreen extends StatefulWidget {
  const TripHomeScreen({super.key, required this.tripId, required this.tripName});
  final int tripId;
  final String tripName;

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

  @override
  void initState() {
    super.initState();
    ApiClient.instance.rememberTrip(widget.tripId);
    _loadAll();
  }

  Future<void> _loadAll() async {
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

  double get total => _expenses.fold(0, (sum, item) => sum + item.amount);

  Future<void> _addExpense() async {
    if (_trip == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExpenseSheet(tripId: widget.tripId),
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
            child: const Text('Delete', style: TextStyle(color: Color(0xFFD1805C))),
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
              Center(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD9DED8), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: ink),
                title: const Text('Edit expense', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD1805C)),
                title: const Text(
                  'Delete expense',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFD1805C)),
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

  static const _owe = Color(0xFFD1805C);
  static const _line = Color(0xFFEDEBE3);
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  AppUser? get _me => ApiClient.instance.currentUser;

  Balance? get _myBalance {
    for (final b in _balances) {
      if (b.userId == _me?.id) return b;
    }
    return null;
  }

  double _myShare(TripExpense expense) {
    for (final s in expense.shares) {
      if (s.userId == _me?.id) return s.shareAmount;
    }
    return 0;
  }

  String _memberName(int id) {
    if (id == _me?.id) return 'You';
    for (final m in _trip?.members ?? const <TripMember>[]) {
      if (m.id == id) return m.name;
    }
    return 'Someone';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: paper,
        body: Center(child: CircularProgressIndicator(color: teal)),
      );
    }
    if (_error != null || _trip == null) {
      return Scaffold(
        backgroundColor: paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Could not load this trip.', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton(onPressed: _loadAll, child: const Text('Retry')),
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
          color: teal,
          onRefresh: _loadAll,
          child: NotificationListener<UserScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
                  sliver: SliverToBoxAdapter(child: _appBar(trip)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  sliver: SliverToBoxAdapter(child: _balanceCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(top: 12),
                  sliver: SliverToBoxAdapter(child: _actionChips(trip)),
                ),
                if (_expenses.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
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
        backgroundColor: teal,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.receipt_long_rounded),
        label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _appBar(Trip trip) => Row(
    children: [
      IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded, color: ink),
      ),
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: teal.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.landscape_rounded, color: teal, size: 22),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trip.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3),
            ),
            Text(
              '${trip.members.length} people${trip.destination == null ? '' : ' · ${trip.destination}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Copy invite code',
        onPressed: () => _copyInvite(trip),
        icon: const Icon(Icons.person_add_alt_1_rounded, color: ink),
      ),
    ],
  );

  Widget _balanceCard() {
    final mine = _myBalance;
    final net = mine?.netBalance ?? 0;
    final settled = net.abs() < 0.5;
    final color = settled ? teal : (net > 0 ? teal : _owe);
    final myName = _me?.name;
    final lines = _settlements.where((s) => s.fromUser == myName || s.toUser == myName).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: softShadow()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: settled
                    ? const Text(
                        'You’re all settled up',
                        style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            net > 0 ? 'You are owed' : 'You owe',
                            style: const TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            money(net.abs()),
                            style: TextStyle(
                              color: color,
                              fontSize: 28,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.8,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
                child: Icon(
                  settled
                      ? Icons.check_rounded
                      : net > 0
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: color,
                  size: 20,
                ),
              ),
            ],
          ),
          for (final s in lines) Padding(padding: const EdgeInsets.only(top: 6), child: _debtLine(s, myName)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: _line),
          ),
          Row(
            children: [
              Expanded(child: _miniStat('Your expenses', money(mine?.totalOwed ?? 0))),
              Expanded(child: _miniStat('You paid', money(mine?.totalPaid ?? 0))),
              Expanded(child: _miniStat('Trip total', money(total))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _debtLine(Settlement s, String? myName) {
    final iOwe = s.fromUser == myName;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return Text.rich(
      TextSpan(
        style: const TextStyle(color: ink, fontSize: 13),
        children: iOwe
            ? [
                const TextSpan(text: 'You owe '),
                TextSpan(text: s.toUser, style: bold),
                const TextSpan(text: ' '),
                TextSpan(text: money(s.amount), style: const TextStyle(color: _owe, fontWeight: FontWeight.w700)),
              ]
            : [
                TextSpan(text: s.fromUser, style: bold),
                const TextSpan(text: ' owes you '),
                TextSpan(text: money(s.amount), style: const TextStyle(color: teal, fontWeight: FontWeight.w700)),
              ],
      ),
    );
  }

  Widget _miniStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w500)),
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

  Widget _actionChips(Trip trip) => SizedBox(
    height: 38,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _chip('Settle up', Icons.handshake_rounded, _showSettleUp, filled: true),
        _chip('Balances', Icons.people_alt_rounded, () => _showBalances(trip)),
        _chip('Totals', Icons.pie_chart_rounded, _showTotals),
        _chip('Invite', Icons.key_rounded, () => _copyInvite(trip)),
      ],
    ),
  );

  Widget _chip(String label, IconData icon, VoidCallback onTap, {bool filled = false}) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: filled ? ink : Colors.white,
      shape: StadiumBorder(side: filled ? BorderSide.none : const BorderSide(color: Color(0xFFE4E1D6))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: 16, color: filled ? Colors.white : ink),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _emptyExpenses() => Column(
    children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: teal.withValues(alpha: .1), shape: BoxShape.circle),
        child: const Icon(Icons.receipt_long_rounded, color: teal, size: 30),
      ),
      const SizedBox(height: 14),
      const Text('No expenses yet', style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text(
        'Add the first one — it’s split with everyone on the trip.',
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
      for (final entry in groups.entries) ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  money(entry.value.fold<double>(0, (sum, e) => sum + e.amount)),
                  style: const TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  for (var i = 0; i < entry.value.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 66, color: _line),
                    _expenseRow(entry.value[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _expenseRow(TripExpense expense) {
    final iPaid = expense.paidBy == _me?.id;
    final share = _myShare(expense);
    final delta = iPaid ? expense.amount - share : share;
    final involved = (iPaid || share > 0) && delta >= 0.5;
    final color = !involved ? muted : (iPaid ? teal : _owe);
    final catColor = colorForCategory(expense.category);
    final d = expense.dateTime;
    final city = cityFromLocation(expense.location);
    final paidLine = '${iPaid ? 'You' : expense.paidByName} paid ${money(expense.amount)}';
    return InkWell(
      onTap: () => _showExpenseDetails(expense),
      onLongPress: () => _showExpenseActions(expense),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 11, 14, 11),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  Text(
                    _shortMonths[d.month - 1],
                    style: const TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${d.day}',
                    style: const TextStyle(color: ink, fontSize: 16, height: 1.1, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(expense.icon, color: catColor, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    city == null ? paidLine : '$paidLine · $city',
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
                  !involved ? 'not involved' : (iPaid ? 'you lent' : 'you borrowed'),
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                if (involved)
                  Text(
                    money(delta),
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

  Future<void> _sheet(String title, List<Widget> children) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD9DED8), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );

  Widget _sheetCard(List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 60, color: _line),
          rows[i],
        ],
      ],
    ),
  );

  Widget _avatar(String name, Color color, {double radius = 17}) => CircleAvatar(
    radius: radius,
    backgroundColor: color.withValues(alpha: .35),
    child: Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(color: ink, fontSize: radius * .8, fontWeight: FontWeight.w800),
    ),
  );

  Color _colorFor(String name) {
    final members = _trip?.members ?? const <TripMember>[];
    final index = members.indexWhere((m) => m.name == name);
    return colorForMember(index < 0 ? 0 : index);
  }

  void _showSettleUp() {
    final myName = _me?.name;
    _sheet('Settle up', [
      if (_settlements.isEmpty)
        _sheetCard([
          const ListTile(
            leading: Icon(Icons.check_circle_rounded, color: teal),
            title: Text('Everyone’s settled up', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          ),
        ])
      else ...[
        _sheetCard([
          for (final s in _settlements)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _avatar(s.fromUser, _colorFor(s.fromUser), radius: 15),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
                  ),
                  _avatar(s.toUser, _colorFor(s.toUser), radius: 15),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${s.fromUser == myName ? 'You' : s.fromUser} → ${s.toUser == myName ? 'you' : s.toUser}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: 14,
                        fontWeight: s.fromUser == myName || s.toUser == myName ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    money(s.amount),
                    style: TextStyle(
                      color: s.fromUser == myName ? _owe : teal,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 10),
        const Text(
          'The fewest payments that settle the whole trip. Pay outside the app (UPI, cash).',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    ]);
  }

  void _showBalances(Trip trip) {
    _sheet('Balances', [
      _sheetCard([
        for (var i = 0; i < trip.members.length; i++) _balanceRow(trip.members[i], i),
      ]),
    ]);
  }

  Widget _balanceRow(TripMember member, int index) {
    final b = _balances.firstWhere(
      (b) => b.userId == member.id,
      orElse: () => Balance(userId: member.id, name: member.name, totalPaid: 0, totalOwed: 0, netBalance: 0),
    );
    final settled = b.netBalance.abs() < 0.5;
    final color = settled ? muted : (b.netBalance > 0 ? teal : _owe);
    final isMe = member.id == _me?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _avatar(member.name, colorForMember(index)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${member.name} (you)' : member.name,
                  style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  'paid ${money(b.totalPaid)} · share ${money(b.totalOwed)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                settled ? 'settled up' : (b.netBalance > 0 ? 'gets back' : 'owes'),
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              if (!settled)
                Text(
                  money(b.netBalance.abs()),
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, double> _sumBy(String? Function(TripExpense) key) {
    final sums = <String, double>{};
    for (final e in _expenses) {
      final k = key(e);
      if (k == null) continue;
      sums[k] = (sums[k] ?? 0) + e.amount;
    }
    final entries = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  void _showTotals() {
    final mine = _myBalance;
    final byCategory = _sumBy((e) => e.category ?? 'Other');
    final byCity = _sumBy((e) => cityFromLocation(e.location));
    _sheet('Trip totals', [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Expanded(child: _miniStat('Trip total', money(total))),
            Expanded(child: _miniStat('Your expenses', money(mine?.totalOwed ?? 0))),
            Expanded(child: _miniStat('You paid', money(mine?.totalPaid ?? 0))),
          ],
        ),
      ),
      if (byCategory.isNotEmpty) ...[
        const SizedBox(height: 18),
        fieldLabel('BY CATEGORY'),
        const SizedBox(height: 8),
        _sheetCard([
          for (final e in byCategory.entries)
            _breakdownRow(iconForCategory(e.key), colorForCategory(e.key), e.key, e.value),
        ]),
      ],
      if (byCity.isNotEmpty) ...[
        const SizedBox(height: 18),
        fieldLabel('BY CITY'),
        const SizedBox(height: 8),
        _sheetCard([
          for (final e in byCity.entries)
            _breakdownRow(Icons.location_city_rounded, colorForCity(e.key), e.key, e.value),
        ]),
      ],
    ]);
  }

  Widget _breakdownRow(IconData icon, Color color, String label, double amount) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(money(amount), style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : amount / total,
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: .12),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _showExpenseDetails(TripExpense expense) {
    final isOwn = expense.paidBy == _me?.id;
    final catColor = colorForCategory(expense.category);
    final shares = [...expense.shares]..sort((a, b) => (a.userId == _me?.id ? 0 : 1) - (b.userId == _me?.id ? 0 : 1));
    _sheet(expense.description, [
      Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: catColor.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
            child: Icon(expense.icon, color: catColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  money(expense.amount),
                  style: const TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6),
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
        _detailRow(Icons.schedule_rounded, formatDateTime(expense.dateTime), isOwn
            ? () {
                Navigator.pop(context);
                _quickEditDateTime(expense);
              }
            : null),
        _detailRow(Icons.location_on_rounded, expense.location ?? 'No location', isOwn
            ? () {
                Navigator.pop(context);
                _quickEditLocation(expense);
              }
            : null),
      ]),
      const SizedBox(height: 18),
      fieldLabel('SPLIT EQUALLY'),
      const SizedBox(height: 8),
      _sheetCard([
        for (final s in shares)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                _avatar(_memberName(s.userId), _colorFor(_memberName(s.userId)), radius: 15),
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
                  side: const BorderSide(color: Color(0xFFEBCFC2)),
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
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit'),
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
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
          Icon(icon, size: 18, color: teal),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null) const Icon(Icons.edit_rounded, size: 15, color: muted),
        ],
      ),
    ),
  );
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, required this.tripId, this.existing});
  final int tripId;
  final TripExpense? existing;

  bool get isEditing => existing != null;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  late final _title = TextEditingController(text: widget.existing?.description ?? '');
  late final _amount = TextEditingController(
    text: widget.existing != null ? widget.existing!.amount.toStringAsFixed(0) : '',
  );
  late String _category = widget.existing?.category ?? 'Food';
  late DateTime _dateTime = widget.existing?.dateTime ?? DateTime.now();
  String? _location;
  bool _locatingNow = false;
  bool _busy = false;
  String? _error;
  final categories = const {
    'Food': Icons.restaurant_rounded,
    'Stay': Icons.hotel_rounded,
    'Transport': Icons.directions_car_rounded,
    'Activities': Icons.local_activity_rounded,
    'Other': Icons.more_horiz_rounded,
  };

  @override
  void initState() {
    super.initState();
    _location = widget.existing?.location;
    _refreshLocation();
  }

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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(color: paper, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD9DED8), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                widget.isEditing ? 'Edit expense' : 'Add an expense',
                style: const TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
              ),
              const SizedBox(height: 5),
              const Text(
                'Split equally across everyone on the trip.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 23),
              fieldLabel('WHAT WAS IT?'),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: appInputDecoration('e.g. Dinner at Manek Chowk', Icons.edit_rounded),
              ),
              const SizedBox(height: 18),
              fieldLabel('AMOUNT'),
              const SizedBox(height: 8),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: appInputDecoration('₹  0', Icons.currency_rupee_rounded),
              ),
              const SizedBox(height: 18),
              fieldLabel('CATEGORY'),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories.entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.key),
                        avatar: Icon(entry.value, size: 16),
                        selected: _category == entry.key,
                        onSelected: (_) => setState(() => _category = entry.key),
                        showCheckmark: false,
                        selectedColor: const Color(0xFFDDF1EB),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _category == entry.key ? teal : muted,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              fieldLabel('WHEN'),
              const SizedBox(height: 9),
              InkWell(
                onTap: _pickDateTime,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 17, color: muted),
                      const SizedBox(width: 9),
                      Text(
                        formatDateTime(_dateTime),
                        style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              fieldLabel('LOCATION'),
              const SizedBox(height: 9),
              InkWell(
                onTap: _openLocationPicker,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 17, color: teal),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          _locatingNow
                              ? 'Finding your location…'
                              : (_location ?? 'Tap to choose on map'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_locatingNow)
                        const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: teal),
                        )
                      else
                        const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
                    ],
                  ),
                ),
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
                  onPressed: _busy ? null : _save,
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
                      : Text(
                          widget.isEditing ? 'Save changes' : 'Save expense',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
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
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
