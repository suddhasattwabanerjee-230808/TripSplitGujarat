import 'package:flutter/material.dart';

import '../api_client.dart';
import '../charts.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';

/// Spending charts. As a tab it covers every trip (with a trip filter); opened
/// from a trip ("View stats") it is fixed to that trip.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.trip, this.expenses});
  final Trip? trip;

  /// The trip's expenses when opened from a trip (already loaded there).
  final List<TripExpense>? expenses;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _store = TripStore.instance;
  String? _tripFilter;
  bool _loading = false;

  bool get _single => widget.trip != null;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    if (!_single) _load();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (_store.trips == null) await _store.refresh();
    await _store.loadAllExpenses();
    if (mounted) setState(() => _loading = false);
  }

  List<Trip> get _trips => _single ? [widget.trip!] : (_store.trips ?? const []);

  /// (trip, expense) pairs in scope, without settle-up payments.
  List<(Trip, TripExpense)> get _rows => [
    for (final t in _trips)
      if (_single || _tripFilter == null || _tripFilter == t.id)
        for (final e in (_single ? widget.expenses! : _store.expenses[t.id] ?? const <TripExpense>[]))
          if (!e.isSettlement) (t, e),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final me = ApiClient.instance.currentUser?.id ?? '';
    final total = rows.fold(0.0, (s, r) => s + r.$2.amount);
    final myShare = rows.fold(0.0, (s, r) => s + r.$2.shareOf(me));
    final iPaid = rows.where((r) => r.$2.paidBy == me).fold(0.0, (s, r) => s + r.$2.amount);

    final body = RefreshIndicator(
      color: accent,
      onRefresh: _single ? () async {} : _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (!_single) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text('Statistics', style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.5)),
            ),
            if (_trips.length > 1) _filterRow(),
          ],
          if (_loading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator(color: accent)),
            )
          else if (rows.isEmpty)
            _empty()
          else ...[
            _heroTiles(total, myShare, iPaid, rows.length),
            const SizedBox(height: 14),
            _chartCard('Spending over time', _timeChart(rows)),
            const SizedBox(height: 12),
            _chartCard('By category', HBarChart(data: _byCategory(rows))),
            const SizedBox(height: 12),
            _chartCard('Who paid', HBarChart(data: _byPayer(rows))),
            if (_byCity(rows).isNotEmpty) ...[
              const SizedBox(height: 12),
              _chartCard('By city', HBarChart(data: _byCity(rows))),
            ],
            if (!_single && _tripFilter == null && _trips.length > 1) ...[
              const SizedBox(height: 12),
              _chartCard(
                'By trip',
                HBarChart(
                  data: [
                    for (final t in _trips)
                      BarDatum(
                        t.name,
                        rows.where((r) => r.$1.id == t.id).fold(0.0, (s, r) => s + r.$2.amount),
                        icon: t.tripKind.icon,
                      ),
                  ].where((d) => d.value > 0).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );

    if (!_single) return SafeArea(bottom: false, child: body);
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        surfaceTintColor: paper,
        title: Text('${widget.trip!.name} · stats', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: body,
    );
  }

  Widget _filterRow() => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All trips', null),
          for (final t in _trips) _filterChip(t.name, t.id),
        ],
      ),
    ),
  );

  Widget _filterChip(String label, String? id) {
    final selected = _tripFilter == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _tripFilter = id),
        showCheckmark: false,
        backgroundColor: Colors.white,
        selectedColor: accentSoft,
        side: BorderSide(color: selected ? accent.withValues(alpha: .4) : line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(color: selected ? accent : ink, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _heroTiles(double total, double myShare, double iPaid, int count) => Row(
    children: [
      Expanded(child: _tile('Total spent', money(total), '$count expense${count == 1 ? '' : 's'}', Icons.account_balance_wallet_outlined)),
      const SizedBox(width: 10),
      Expanded(child: _tile('Your share', money(myShare), 'you paid ${money(iPaid)}', Icons.person_outline_rounded)),
    ],
  );

  Widget _tile(String label, String value, String note, IconData icon) => Container(
    padding: const EdgeInsets.all(14),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconCircle(icon: icon, size: 32),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: ink,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 11.5)),
      ],
    ),
  );

  Widget _chartCard(String title, Widget chart) => Container(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        chart,
      ],
    ),
  );

  Widget _empty() => const Padding(
    padding: EdgeInsets.only(top: 70),
    child: Column(
      children: [
        IconCircle(icon: Icons.insights_outlined, size: 64),
        SizedBox(height: 14),
        Text('Nothing to chart yet', style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Add a few expenses and your spending shows up here.', style: TextStyle(color: muted, fontSize: 13)),
      ],
    ),
  );

  Widget _timeChart(List<(Trip, TripExpense)> rows) {
    final dates = rows.map((r) => r.$2.dateTime).toList()..sort();
    final first = DateTime(dates.first.year, dates.first.month, dates.first.day);
    final last = DateTime(dates.last.year, dates.last.month, dates.last.day);
    final days = last.difference(first).inDays + 1;
    final List<BarDatum> buckets;
    if (days <= 31) {
      final sums = List<double>.filled(days, 0);
      for (final r in rows) {
        final d = r.$2.dateTime;
        sums[DateTime(d.year, d.month, d.day).difference(first).inDays] += r.$2.amount;
      }
      buckets = [
        for (var i = 0; i < days; i++)
          () {
            final d = first.add(Duration(days: i));
            return BarDatum('${d.day} ${shortMonth(d.month)}', sums[i]);
          }(),
      ];
    } else {
      final months = (last.year - first.year) * 12 + last.month - first.month + 1;
      final sums = List<double>.filled(months, 0);
      for (final r in rows) {
        final d = r.$2.dateTime;
        sums[(d.year - first.year) * 12 + d.month - first.month] += r.$2.amount;
      }
      buckets = [
        for (var i = 0; i < months; i++)
          () {
            final m = DateTime(first.year, first.month + i);
            return BarDatum('${shortMonth(m.month)} ${m.year % 100}', sums[i]);
          }(),
      ];
    }
    return TimeBarChart(buckets: buckets);
  }

  List<BarDatum> _byCategory(List<(Trip, TripExpense)> rows) {
    final sums = <String, double>{};
    for (final r in rows) {
      final c = r.$2.category ?? 'Other';
      sums[c] = (sums[c] ?? 0) + r.$2.amount;
    }
    return [for (final e in sums.entries) BarDatum(e.key, e.value, icon: iconForCategory(e.key))];
  }

  List<BarDatum> _byPayer(List<(Trip, TripExpense)> rows) {
    final sums = <String, double>{};
    final names = <String, String>{};
    final members = <String, TripMember>{};
    for (final r in rows) {
      sums[r.$2.paidBy] = (sums[r.$2.paidBy] ?? 0) + r.$2.amount;
      names[r.$2.paidBy] = r.$2.paidByName;
      final m = r.$1.member(r.$2.paidBy);
      if (m != null) members[m.id] = m;
    }
    final me = ApiClient.instance.currentUser?.id;
    return [
      for (final e in sums.entries)
        BarDatum(
          e.key == me ? 'You' : names[e.key]!,
          e.value,
          leading: members[e.key] != null
              ? MemberAvatar.of(members[e.key]!, size: 22)
              : MemberAvatar(id: e.key, name: names[e.key]!, size: 22),
        ),
    ];
  }

  List<BarDatum> _byCity(List<(Trip, TripExpense)> rows) {
    final sums = <String, double>{};
    for (final r in rows) {
      final c = cityFromLocation(r.$2.location);
      if (c != null) sums[c] = (sums[c] ?? 0) + r.$2.amount;
    }
    return [for (final e in sums.entries) BarDatum(e.key, e.value, icon: Icons.location_city_outlined)];
  }
}
