import 'package:flutter/material.dart';

import '../api_client.dart';
import '../charts.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// One trip's spending, four ways: by date, category, person and place.
/// "Whole trip" counts every expense in full; "My share" counts what's yours.
/// Settle-up payments are left out (they move money, they aren't spending).
class TripInsights extends StatefulWidget {
  const TripInsights({super.key, required this.trip, required this.expenses});
  final Trip trip;
  final List<TripExpense> expenses;

  @override
  State<TripInsights> createState() => _TripInsightsState();
}

class _TripInsightsState extends State<TripInsights> {
  bool _mine = false;
  bool _byShare = false; // person chart: paid (false) or share (true)

  String get _me => ApiClient.instance.currentUser?.id ?? '';

  List<TripExpense> get _spend => widget.expenses.where((e) => !e.isSettlement).toList();

  double _value(TripExpense e) => _mine ? e.shareOf(_me) : e.amount;

  @override
  Widget build(BuildContext context) {
    final spend = _spend.where((e) => _value(e) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Insights', style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            ),
            _Segmented(
              options: const ['Whole trip', 'My share'],
              selected: _mine ? 1 : 0,
              onSelect: (i) => setState(() => _mine = i == 1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (spend.isEmpty)
          _card(
            title: 'Nothing to show yet',
            subtitle: _mine ? 'None of the expenses include you.' : 'Add an expense to see where the money goes.',
            child: const SizedBox.shrink(),
          )
        else ...[
          _byDate(spend),
          const SizedBox(height: 14),
          _byCategory(spend),
          const SizedBox(height: 14),
          _byPerson(),
          const SizedBox(height: 14),
          _byPlace(spend),
        ],
      ],
    );
  }

  // --- By date ---------------------------------------------------------------------

  Widget _byDate(List<TripExpense> spend) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final days = spend.map((e) => day(e.dateTime)).toList()..sort();
    final first = days.first, last = days.last;
    final span = last.difference(first).inDays + 1;
    // Up to a month: one column a day. Longer: one a week.
    final weekly = span > 31;
    final step = weekly ? 7 : 1;
    final count = (span / step).ceil();
    final buckets = List.generate(count, (i) {
      final start = first.add(Duration(days: i * step));
      final end = start.add(Duration(days: step));
      final v = spend
          .where((e) => !day(e.dateTime).isBefore(start) && day(e.dateTime).isBefore(end))
          .fold(0.0, (s, e) => s + _value(e));
      return (start, v);
    });
    final total = buckets.fold(0.0, (s, b) => s + b.$2);
    final busiest = buckets.reduce((a, b) => b.$2 > a.$2 ? b : a);
    String label(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';
    return _card(
      title: 'By date',
      subtitle: weekly ? 'Each week of the trip' : 'Each day of the trip',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _fact(weekly ? 'Busiest week' : 'Busiest day', '${label(busiest.$1)} · ${money(busiest.$2)}')),
              const SizedBox(width: 12),
              Expanded(child: _fact('Daily average', money(total / span))),
            ],
          ),
          const SizedBox(height: 14),
          TimeBarChart(
            height: 160,
            buckets: [for (final b in buckets) BarDatum(weekly ? label(b.$1) : '${b.$1.day}', b.$2)],
          ),
        ],
      ),
    );
  }

  // --- By category -------------------------------------------------------------------

  /// The trip's top 4 categories (on the whole trip, so a category keeps its
  /// colour when switching to "My share") get colours; the rest are Other.
  Widget _byCategory(List<TripExpense> spend) {
    final whole = <String, double>{};
    for (final e in _spend) {
      final c = e.category ?? 'Other';
      whole[c] = (whole[c] ?? 0) + e.amount;
    }
    final ranked = (whole.entries.where((e) => e.key != 'Other').toList()..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .map((e) => e.key)
        .toList();
    final now = <String, double>{};
    for (final e in spend) {
      final c = e.category ?? 'Other';
      now[c] = (now[c] ?? 0) + _value(e);
    }
    final total = now.values.fold(0.0, (s, v) => s + v);
    final slots = donutSlotColors();
    final slices = <DonutSlice>[
      for (final (i, c) in ranked.indexed)
        if ((now[c] ?? 0) > 0) DonutSlice(c, now[c]!, slots[i], icon: iconForCategory(c)),
    ];
    final other = total - slices.fold(0.0, (s, d) => s + d.value);
    if (other > 0.5) slices.add(DonutSlice('Other', other, otherSliceColor, icon: Icons.more_horiz_rounded));
    return _card(
      title: 'By category',
      subtitle: 'Tap a slice for its share',
      child: Row(
        children: [
          DonutChart(slices: slices, total: total, size: 148),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (final s in slices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 8),
                        Icon(s.icon, size: 15, color: muted),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(compactMoney(s.value), style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
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

  // --- By person ------------------------------------------------------------------------

  /// Who paid for the trip, or whose share it was: always the whole trip.
  Widget _byPerson() {
    final data = <BarDatum>[
      for (final m in widget.trip.members)
        BarDatum(
          m.id == _me ? '${m.name} (you)' : m.name,
          _spend.fold(0.0, (s, e) => s + (_byShare ? e.shareOf(m.id) : (e.paidBy == m.id ? e.amount : 0))),
          leading: MemberAvatar.of(m, size: 24, tripId: widget.trip.id),
        ),
    ];
    return _card(
      title: 'By person',
      subtitle: _byShare ? 'Each person’s share of the trip' : 'Who paid for the trip',
      trailing: _Segmented(
        options: const ['Paid', 'Share'],
        selected: _byShare ? 1 : 0,
        onSelect: (i) => setState(() => _byShare = i == 1),
      ),
      child: HBarChart(data: data, maxRows: 8),
    );
  }

  // --- By place ---------------------------------------------------------------------------

  Widget _byPlace(List<TripExpense> spend) {
    final sums = <String, double>{};
    for (final e in spend) {
      final city = cityFromLocation(e.location) ?? 'No location';
      sums[city] = (sums[city] ?? 0) + _value(e);
    }
    return _card(
      title: 'By location',
      subtitle: 'Spending in each city',
      child: HBarChart(
        maxRows: 5,
        data: [
          for (final e in sums.entries)
            BarDatum(e.key, e.value, icon: e.key == 'No location' ? Icons.location_off_outlined : Icons.place_outlined),
        ],
      ),
    );
  }

  // --- Pieces ---------------------------------------------------------------------------------

  Widget _fact(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted, fontSize: 11.5)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _card({required String title, String? subtitle, Widget? trailing, required Widget child}) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    decoration: cardDecoration(radius: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: ink, fontSize: 15.5, fontWeight: FontWeight.w800)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: muted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

/// A small two-way switch (dark pill on the chosen side).
class _Segmented extends StatelessWidget {
  const _Segmented({required this.options, required this.selected, required this.onSelect});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: line)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, o) in options.indexed)
          GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: selected == i ? ink : Colors.transparent, borderRadius: BorderRadius.circular(16)),
              child: Text(
                o,
                style: TextStyle(color: selected == i ? paper : muted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    ),
  );
}
