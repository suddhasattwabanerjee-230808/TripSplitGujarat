import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';

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
  int _tab = 0;

  @override
  void initState() {
    super.initState();
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
      builder: (context) => ExpenseSheet(tripId: widget.tripId, members: _trip!.members),
    );
    if (created == true) {
      await _loadAll();
    }
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
    final isOverview = _tab == 0;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                sliver: SliverToBoxAdapter(child: _topBar()),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                sliver: SliverToBoxAdapter(child: _tripHeader(trip)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                sliver: SliverToBoxAdapter(child: _summaryCard(trip)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: _sectionHeading(
                    isOverview ? 'Your crew' : 'Trip balances',
                    trailing: '${trip.members.length} people',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
                sliver: SliverToBoxAdapter(child: _peopleRow(trip)),
              ),
              if (isOverview) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 27, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: _sectionHeading('Recent expenses', trailing: '${_expenses.length} entries'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
                  sliver: _expenses.isEmpty
                      ? SliverToBoxAdapter(child: _emptyExpenses())
                      : SliverList.builder(
                          itemCount: _expenses.length,
                          itemBuilder: (context, index) => _expenseTile(_expenses[index]),
                        ),
                ),
              ] else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                  sliver: SliverToBoxAdapter(child: _settlementCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 27, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: _sectionHeading('All expenses', trailing: '${_expenses.length} entries'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
                  sliver: _expenses.isEmpty
                      ? SliverToBoxAdapter(child: _emptyExpenses())
                      : SliverList.builder(
                          itemCount: _expenses.length,
                          itemBuilder: (context, index) => _expenseTile(_expenses[index]),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        backgroundColor: ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        backgroundColor: const Color(0xFFFEFDF9),
        indicatorColor: const Color(0xFFDDF1EB),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.swap_horiz_rounded), label: 'Balances'),
        ],
      ),
    );
  }

  Widget _emptyExpenses() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 30),
    child: Text(
      'No expenses yet. Add the first one below.',
      style: TextStyle(color: muted, fontSize: 13),
    ),
  );

  Widget _topBar() => Row(
    children: [
      InkWell(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
          child: const Icon(Icons.arrow_back_rounded, color: ink, size: 21),
        ),
      ),
      const Spacer(),
      const Text(
        'TRIPSPLIT',
        style: TextStyle(color: muted, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w800),
      ),
      const Spacer(),
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: const Icon(Icons.more_horiz_rounded, color: ink),
      ),
    ],
  );

  Widget _tripHeader(Trip trip) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFFE8EEE5), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.key_rounded, size: 12, color: teal),
            const SizedBox(width: 5),
            Text(
              'INVITE CODE ${trip.inviteCode}',
              style: const TextStyle(fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: teal),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        trip.name,
        style: const TextStyle(color: ink, fontSize: 31, height: 1.08, fontWeight: FontWeight.w800, letterSpacing: -1),
      ),
      if (trip.destination != null) ...[
        const SizedBox(height: 7),
        Row(
          children: [
            const Icon(Icons.location_on_rounded, size: 15, color: teal),
            const SizedBox(width: 3),
            Text(trip.destination!, style: const TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    ],
  );

  Widget _summaryCard(Trip trip) => Container(
    padding: const EdgeInsets.all(21),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .12), blurRadius: 20, offset: const Offset(0, 9))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TOTAL SPENT',
          style: TextStyle(color: Color(0xFFAAB7C2), fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Text(
          money(total),
          style: const TextStyle(color: Colors.white, fontSize: 37, fontWeight: FontWeight.w800, letterSpacing: -1.4),
        ),
        const SizedBox(height: 3),
        Text(
          trip.members.isEmpty
              ? '${_expenses.length} shared expenses'
              : '${money(total / trip.members.length)} per person · ${_expenses.length} shared expenses',
          style: const TextStyle(color: Color(0xFFAAB7C2), fontSize: 12),
        ),
      ],
    ),
  );

  Widget _sectionHeading(String title, {required String trailing}) => Row(
    children: [
      Text(title, style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w800, letterSpacing: -.3)),
      const Spacer(),
      Text(trailing, style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w600)),
    ],
  );

  Widget _peopleRow(Trip trip) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children: List.generate(trip.members.length, (index) {
      final member = trip.members[index];
      final balance = _balances.firstWhere(
        (b) => b.userId == member.id,
        orElse: () => Balance(userId: member.id, name: member.name, totalPaid: 0, totalOwed: 0, netBalance: 0),
      );
      return SizedBox(
        width: (MediaQuery.of(context).size.width - 44 - 18) / 3,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 13, 9, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: colorForMember(index).withValues(alpha: .35),
                    child: Text(
                      member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                      style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    balance.netBalance >= 0 ? Icons.north_east_rounded : Icons.south_west_rounded,
                    size: 14,
                    color: balance.netBalance >= 0 ? teal : const Color(0xFFD1805C),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(
                '${balance.netBalance >= 0 ? '+' : '−'}${money(balance.netBalance.abs())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: balance.netBalance >= 0 ? teal : const Color(0xFFD1805C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );

  Widget _settlementCard() {
    if (_settlements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Text('You’re all settled up!', style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFEAF2E8), borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUGGESTED SETTLEMENT',
            style: TextStyle(color: teal, fontSize: 9, letterSpacing: 1.25, fontWeight: FontWeight.w800),
          ),
          for (final transfer in _settlements) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    transfer.fromUser,
                    style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 15, color: teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    transfer.toUser,
                    style: const TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  money(transfer.amount),
                  style: const TextStyle(color: teal, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text('These transfers will settle the trip.', style: TextStyle(color: muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _expenseTile(TripExpense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19)),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(color: const Color(0xFFF1F3EE), borderRadius: BorderRadius.circular(15)),
            child: Icon(expense.icon, color: teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  style: const TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${expense.category ?? 'Other'} · paid by ${expense.paidByName}',
                  style: const TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            money(expense.amount),
            style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, required this.tripId, required this.members});
  final int tripId;
  final List<TripMember> members;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  late int _payer = widget.members.first.id;
  String _category = 'Food';
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
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
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
              const Text(
                'Add an expense',
                style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
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
              fieldLabel('PAID BY'),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(widget.members.length, (index) {
                  final member = widget.members[index];
                  final selected = _payer == member.id;
                  return InkWell(
                    onTap: () => setState(() => _payer = member.id),
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFDDF1EB) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: selected ? teal : Colors.transparent),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: colorForMember(index).withValues(alpha: .4),
                            child: Text(
                              member.name.isEmpty ? '?' : member.name[0].toUpperCase(),
                              style: const TextStyle(fontSize: 10, color: ink, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            member.name,
                            style: const TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
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
                      : const Text('Save expense', style: TextStyle(fontWeight: FontWeight.w700)),
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
      await ApiClient.instance.createExpense(
        tripId: widget.tripId,
        description: title,
        amount: amount,
        paidBy: _payer,
        category: _category,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
