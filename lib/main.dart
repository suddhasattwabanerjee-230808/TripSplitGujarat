import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const TripSplitApp());

const _ink = Color(0xFF182A3A);
const _muted = Color(0xFF788692);
const _paper = Color(0xFFF6F5F0);
const _teal = Color(0xFF087E78);
const _lime = Color(0xFFD9F078);

class TripSplitApp extends StatelessWidget {
  const TripSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'TripSplit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _paper,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: _paper,
          foregroundColor: _ink,
        ),
      ),
      home: const TripHome(),
    );
  }
}

class Traveler {
  const Traveler(this.name, this.initial, this.color);
  final String name;
  final String initial;
  final Color color;
}

class TripExpense {
  TripExpense({
    required this.title,
    required this.category,
    required this.amount,
    required this.payer,
    required this.icon,
    DateTime? date,
  }) : date = date ?? DateTime.now();
  final String title;
  final String category;
  final double amount;
  final int payer;
  final IconData icon;
  final DateTime date;

  Map<String, Object> toJson() => {
    'title': title,
    'category': category,
    'amount': amount,
    'payer': payer,
    'date': date.toIso8601String(),
  };

  factory TripExpense.fromJson(Map<String, dynamic> json) => TripExpense(
    title: json['title'] as String,
    category: json['category'] as String,
    amount: (json['amount'] as num).toDouble(),
    payer: json['payer'] as int,
    icon: _iconForCategory(json['category'] as String),
    date: DateTime.parse(json['date'] as String),
  );
}

IconData _iconForCategory(String category) => switch (category) {
  'Food' => Icons.restaurant_rounded,
  'Stay' => Icons.hotel_rounded,
  'Transport' => Icons.local_taxi_rounded,
  'Activities' => Icons.local_activity_rounded,
  _ => Icons.more_horiz_rounded,
};

final _sampleExpenses = [
  TripExpense(
    title: 'Hotel Riverfront',
    category: 'Stay',
    amount: 5400,
    payer: 0,
    icon: Icons.hotel_rounded,
    date: DateTime(2026, 10, 8),
  ),
  TripExpense(
    title: 'Gujarati thali',
    category: 'Food',
    amount: 1860,
    payer: 1,
    icon: Icons.restaurant_rounded,
    date: DateTime(2026, 10, 8),
  ),
  TripExpense(
    title: 'Auto to Adalaj',
    category: 'Transport',
    amount: 420,
    payer: 2,
    icon: Icons.local_taxi_rounded,
    date: DateTime(2026, 10, 7),
  ),
  TripExpense(
    title: 'Stepwell tickets',
    category: 'Activities',
    amount: 300,
    payer: 0,
    icon: Icons.confirmation_number_rounded,
    date: DateTime(2026, 10, 7),
  ),
];

class TripHome extends StatefulWidget {
  const TripHome({super.key});

  @override
  State<TripHome> createState() => _TripHomeState();
}

class _TripHomeState extends State<TripHome> {
  final travelers = const [
    Traveler('Aarav', 'A', Color(0xFFE1B764)),
    Traveler('Meera', 'M', Color(0xFF88B8AD)),
    Traveler('Kabir', 'K', Color(0xFFB49BC8)),
  ];
  static const _expenseStorageKey = 'trip_split.expenses.v1';
  final _preferences = SharedPreferencesAsync();
  final expenses = <TripExpense>[];
  bool _loadingExpenses = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _restoreExpenses();
  }

  Future<void> _restoreExpenses() async {
    try {
      final saved = await _preferences.getString(_expenseStorageKey);
      if (saved == null) {
        expenses.addAll(_sampleExpenses);
        await _saveExpenses();
      } else {
        final decoded = jsonDecode(saved) as List<dynamic>;
        expenses.addAll(
          decoded.map(
            (item) => TripExpense.fromJson(item as Map<String, dynamic>),
          ),
        );
      }
    } on Object {
      expenses
        ..clear()
        ..addAll(_sampleExpenses);
      await _saveExpenses();
    }
    if (mounted) setState(() => _loadingExpenses = false);
  }

  Future<void> _saveExpenses() => _preferences.setString(
    _expenseStorageKey,
    jsonEncode(expenses.map((expense) => expense.toJson()).toList()),
  );

  double get total => expenses.fold(0, (sum, item) => sum + item.amount);
  List<double> get balances {
    final each = total / travelers.length;
    return List.generate(travelers.length, (index) {
      final paid = expenses
          .where((expense) => expense.payer == index)
          .fold<double>(0, (sum, expense) => sum + expense.amount);
      return paid - each;
    });
  }

  String money(double value) =>
      '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

  Future<void> _addExpense() async {
    final created = await showModalBottomSheet<TripExpense>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExpenseSheet(travelers: travelers),
    );
    if (created != null) {
      setState(() => expenses.insert(0, created));
      await _saveExpenses();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExpenses) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    final isOverview = _tab == 0;
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
              sliver: SliverToBoxAdapter(child: _topBar()),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverToBoxAdapter(child: _tripHeader()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              sliver: SliverToBoxAdapter(child: _summaryCard()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 0),
              sliver: SliverToBoxAdapter(
                child: _sectionHeading(
                  isOverview ? 'Your crew' : 'Trip balances',
                  trailing: '3 people',
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 13, 22, 0),
              sliver: SliverToBoxAdapter(child: _peopleRow()),
            ),
            if (isOverview) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 27, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: _sectionHeading(
                    'Recent expenses',
                    trailing: '${expenses.length} entries',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
                sliver: SliverList.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) =>
                      _expenseTile(expenses[index]),
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
                  child: _sectionHeading(
                    'All expenses',
                    trailing: '${expenses.length} entries',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 120),
                sliver: SliverList.builder(
                  itemCount: expenses.length,
                  itemBuilder: (context, index) =>
                      _expenseTile(expenses[index]),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addExpense,
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add expense',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        backgroundColor: const Color(0xFFFEFDF9),
        indicatorColor: const Color(0xFFDDF1EB),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_horiz_rounded),
            label: 'Balances',
          ),
        ],
      ),
    );
  }

  Widget _topBar() => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: _ink, size: 21),
      ),
      const Spacer(),
      const Text(
        'TRIPSPLIT',
        style: TextStyle(
          color: _muted,
          fontSize: 11,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w800,
        ),
      ),
      const Spacer(),
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(Icons.more_horiz_rounded, color: _ink),
      ),
    ],
  );

  Widget _tripHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEE5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, size: 7, color: _teal),
                SizedBox(width: 6),
                Text(
                  'IN PROGRESS',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: _teal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'OCT 7 — 10',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Gujarat getaway',
        style: TextStyle(
          color: _ink,
          fontSize: 31,
          height: 1.08,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 7),
      const Row(
        children: [
          Icon(Icons.location_on_rounded, size: 15, color: _teal),
          SizedBox(width: 3),
          Text(
            'Ahmedabad · India',
            style: TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _summaryCard() => Container(
    padding: const EdgeInsets.all(21),
    decoration: BoxDecoration(
      color: _ink,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
          color: _ink.withValues(alpha: .12),
          blurRadius: 20,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'TOTAL SPENT',
              style: TextStyle(
                color: Color(0xFFAAB7C2),
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.trending_up_rounded,
                color: _lime,
                size: 17,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          money(total),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 37,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${money(total / travelers.length)} per person · ${expenses.length} shared expenses',
          style: const TextStyle(color: Color(0xFFAAB7C2), fontSize: 12),
        ),
        const SizedBox(height: 19),
        Container(height: 1, color: Colors.white.withValues(alpha: .12)),
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: _lime),
            SizedBox(width: 7),
            Text(
              'Everything is up to date',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Spacer(),
            Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 19),
          ],
        ),
      ],
    ),
  );

  Widget _sectionHeading(String title, {required String trailing}) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          color: _ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -.3,
        ),
      ),
      const Spacer(),
      Text(
        trailing,
        style: const TextStyle(
          fontSize: 11,
          color: _muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _peopleRow() => Row(
    children: List.generate(travelers.length, (index) {
      final person = travelers[index];
      final balance = balances[index];
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(
            right: index == travelers.length - 1 ? 0 : 9,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 13, 9, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: person.color.withValues(alpha: .35),
                      child: Text(
                        person.initial,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      balance >= 0
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                      size: 14,
                      color: balance >= 0 ? _teal : const Color(0xFFD1805C),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  person.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${balance >= 0 ? '+' : '−'}${money(balance.abs())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: balance >= 0 ? _teal : const Color(0xFFD1805C),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }),
  );

  Widget _settlementCard() {
    final debtors = <int, double>{};
    final creditors = <int, double>{};
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] < -0.5) debtors[i] = -balances[i];
      if (balances[i] > 0.5) creditors[i] = balances[i];
    }
    final transfers = <(int, int, double)>[];
    while (debtors.isNotEmpty && creditors.isNotEmpty) {
      final debtor = debtors.keys.first;
      final creditor = creditors.keys.first;
      final amount = (debtors[debtor]!)
          .clamp(0, creditors[creditor]!)
          .toDouble();
      transfers.add((debtor, creditor, amount));
      final debtLeft = debtors[debtor]! - amount;
      final creditLeft = creditors[creditor]! - amount;
      if (debtLeft < 0.5) {
        debtors.remove(debtor);
      } else {
        debtors[debtor] = debtLeft;
      }
      if (creditLeft < 0.5) {
        creditors.remove(creditor);
      } else {
        creditors[creditor] = creditLeft;
      }
    }
    if (transfers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'You’re all settled up!',
          style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2E8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SUGGESTED SETTLEMENT',
            style: TextStyle(
              color: _teal,
              fontSize: 9,
              letterSpacing: 1.25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final transfer in transfers) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: travelers[transfer.$1].color.withValues(
                    alpha: .5,
                  ),
                  child: Text(
                    travelers[transfer.$1].initial,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  travelers[transfer.$1].name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 15, color: _teal),
                const SizedBox(width: 6),
                CircleAvatar(
                  radius: 15,
                  backgroundColor: travelers[transfer.$2].color.withValues(
                    alpha: .5,
                  ),
                  child: Text(
                    travelers[transfer.$2].initial,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    travelers[transfer.$2].name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  money(transfer.$3),
                  style: const TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'These transfers will settle the trip.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _expenseTile(TripExpense expense) {
    final person = travelers[expense.payer];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3EE),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(expense.icon, color: _teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${expense.category} · paid by ${person.name}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            money(expense.amount),
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ExpenseSheet extends StatefulWidget {
  const ExpenseSheet({super.key, required this.travelers});
  final List<Traveler> travelers;

  @override
  State<ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<ExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  int _payer = 0;
  String _category = 'Food';
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
      decoration: const BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9DED8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Add an expense',
                style: TextStyle(
                  color: _ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'A little detail keeps everyone in sync.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 23),
              _label('WHAT WAS IT?'),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputDecoration(
                  'e.g. Dinner at Manek Chowk',
                  Icons.edit_rounded,
                ),
              ),
              const SizedBox(height: 18),
              _label('AMOUNT'),
              const SizedBox(height: 8),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _inputDecoration(
                  '₹  0',
                  Icons.currency_rupee_rounded,
                ),
              ),
              const SizedBox(height: 18),
              _label('CATEGORY'),
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
                        onSelected: (_) =>
                            setState(() => _category = entry.key),
                        showCheckmark: false,
                        selectedColor: const Color(0xFFDDF1EB),
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _category == entry.key ? _teal : _muted,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              _label('PAID BY'),
              const SizedBox(height: 9),
              Row(
                children: List.generate(widget.travelers.length, (index) {
                  final person = widget.travelers[index];
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == widget.travelers.length - 1 ? 0 : 8,
                      ),
                      child: InkWell(
                        onTap: () => setState(() => _payer = index),
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _payer == index
                                ? const Color(0xFFDDF1EB)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: _payer == index
                                  ? _teal
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: person.color.withValues(
                                  alpha: .4,
                                ),
                                child: Text(
                                  person.initial,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _ink,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                person.name,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: const Text(
                    'Save expense',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 9,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w800,
    ),
  );
  InputDecoration _inputDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: _muted),
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: Color(0xFFAAB3B5), fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _teal, width: 1.3),
        ),
      );
  void _save() {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (title.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a name and a valid amount to continue.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      TripExpense(
        title: title,
        category: _category,
        amount: amount,
        payer: _payer,
        icon: categories[_category]!,
      ),
    );
  }
}
