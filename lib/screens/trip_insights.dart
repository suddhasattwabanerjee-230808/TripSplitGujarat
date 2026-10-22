import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../charts.dart';
import '../ledger.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The parts of a day the "Time of day" card splits spending into.
const dayParts = [
  ('Morning', '5 AM – 12 PM', Icons.wb_twilight_rounded),
  ('Afternoon', '12 – 5 PM', Icons.wb_sunny_outlined),
  ('Evening', '5 – 9 PM', Icons.wb_cloudy_outlined),
  ('Night', '9 PM – 5 AM', Icons.bedtime_outlined),
];

int dayPartOf(DateTime d) => d.hour >= 5 && d.hour < 12
    ? 0
    : d.hour >= 12 && d.hour < 17
    ? 1
    : d.hour >= 17 && d.hour < 21
    ? 2
    : 3;

/// One trip's spending as a row of cards you swipe through (or jump to with
/// the chips above): an overview, by date, category, person, who's ahead,
/// place, time of day and the biggest expenses. "Whole trip" counts every
/// expense in full; "My share" counts what's yours. Settle-up payments are
/// left out of spending (they move money, they aren't spending).
class TripInsights extends StatefulWidget {
  const TripInsights({super.key, required this.trip, required this.expenses});
  final Trip trip;
  final List<TripExpense> expenses;

  /// Every card is this tall, so swiping never makes the page jump.
  static const cardHeight = 356.0;

  @override
  State<TripInsights> createState() => _TripInsightsState();
}

class _TripInsightsState extends State<TripInsights> {
  bool _mine = false;
  bool _byShare = false; // person chart: paid (false) or share (true)
  int _page = 0;
  final _pages = PageController(viewportFraction: .9);
  late final _chipKeys = List.generate(_cards.length, (_) => GlobalKey());

  static const _cards = [
    ('Overview', Icons.space_dashboard_outlined),
    ('By Date', Icons.calendar_month_outlined),
    ('Category', Icons.donut_large_rounded),
    ('People', Icons.groups_outlined),
    ('Who’s Ahead', Icons.balance_rounded),
    ('Places', Icons.place_outlined),
    ('Time Of Day', Icons.schedule_rounded),
    ('Top Expenses', Icons.emoji_events_outlined),
  ];

  String get _me => ApiClient.instance.currentUser?.id ?? '';

  List<TripExpense> get _spend => widget.expenses.where((e) => !e.isSettlement).toList();

  double _value(TripExpense e) => _mine ? e.shareOf(_me) : e.amount;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int i) =>
      _pages.animateToPage(i, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);

  void _onPage(int i) {
    setState(() => _page = i);
    final chip = _chipKeys[i].currentContext;
    if (chip != null) {
      Scrollable.ensureVisible(chip, alignment: .5, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spend = _spend.where((e) => _value(e) > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Insights',
                      style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3),
                    ),
                    Text('Swipe The Cards For More', style: TextStyle(color: muted, fontSize: 11.5)),
                  ],
                ),
              ),
              _Segmented(
                options: const ['Whole Trip', 'My Share'],
                selected: _mine ? 1 : 0,
                onSelect: (i) => setState(() => _mine = i == 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (spend.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _card(
              title: 'Nothing To Show Yet',
              subtitle: _mine ? 'None of the expenses include you.' : 'Add an expense to see where the money goes.',
              child: const SizedBox.shrink(),
              inPage: false,
            ),
          )
        else ...[
          _chips(),
          const SizedBox(height: 12),
          SizedBox(
            // Taller with a larger system font, so the cards still fit.
            height: TripInsights.cardHeight * MediaQuery.textScalerOf(context).scale(14).clamp(14, 22) / 14,
            child: PageView(
              controller: _pages,
              onPageChanged: _onPage,
              children: [
                _overview(spend),
                _byDate(spend),
                _byCategory(spend),
                _byPerson(),
                _whosAhead(),
                _byPlace(spend),
                _byTime(spend),
                _top(spend),
              ].map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: c)).toList(),
            ),
          ),
          const SizedBox(height: 10),
          _dots(),
        ],
      ],
    );
  }

  Widget _chips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final (i, c) in _cards.indexed)
          Padding(
            key: _chipKeys[i],
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => _goTo(i),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _page == i ? accent : surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _page == i ? accent : line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(c.$2, size: 15, color: _page == i ? onAccent : muted),
                    const SizedBox(width: 6),
                    Text(
                      c.$1,
                      style: TextStyle(
                        color: _page == i ? onAccent : ink,
                        fontSize: 12,
                        fontWeight: _page == i ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _dots() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _cards.length; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: _page == i ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: _page == i ? accent : muted.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    ],
  );

  // --- Overview -------------------------------------------------------------------------

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int _spanDays(List<TripExpense> spend) {
    final days = spend.map((e) => _day(e.dateTime)).toList()..sort();
    return days.last.difference(days.first).inDays + 1;
  }

  Widget _overview(List<TripExpense> spend) {
    final total = spend.fold(0.0, (s, e) => s + _value(e));
    final span = _spanDays(spend);
    final biggest = spend.reduce((a, b) => _value(b) > _value(a) ? b : a);
    final byCategory = <String, double>{};
    for (final e in spend) {
      byCategory[e.category ?? 'Other'] = (byCategory[e.category ?? 'Other'] ?? 0) + _value(e);
    }
    final topCategory = byCategory.entries.reduce((a, b) => b.value > a.value ? b : a);
    final wholeTotal = _spend.fold(0.0, (s, e) => s + e.amount);
    // Spending each day, for the pace line.
    final first = _day(spend.map((e) => e.dateTime).reduce((a, b) => a.isBefore(b) ? a : b));
    final daily = List.filled(span, 0.0);
    for (final e in spend) {
      daily[_day(e.dateTime).difference(first).inDays.clamp(0, span - 1)] += _value(e);
    }
    var running = 0.0;
    final cumulative = [for (final v in daily) running += v];
    return _card(
      title: _mine ? 'Your Trip At A Glance' : 'The Trip At A Glance',
      subtitle: '$span Day${span == 1 ? '' : 's'} · ${spend.length} Expense${spend.length == 1 ? '' : 's'}',
      trailing: cumulative.length > 1 ? Sparkline(values: cumulative, width: 70, height: 28) : null,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _tile(_mine ? 'Your Share' : 'Total Spent', money(total), _mine
                  ? '${wholeTotal == 0 ? 0 : (total / wholeTotal * 100).round()}% Of The Trip'
                  : 'By ${widget.trip.memberCount} People')),
              const SizedBox(width: 8),
              Expanded(child: _tile('Per Day', money(total / span), 'Over $span Day${span == 1 ? '' : 's'}')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _mine
                    ? _tile('Per Expense', money(total / spend.length), '${spend.length} With You')
                    : _tile('Per Person', money(total / math.max(1, widget.trip.memberCount)), 'If Split Evenly'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _tile('Average Bill', money(total / spend.length), '${spend.length} Expenses')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _tile(_mine ? 'Biggest Share' : 'Biggest Expense', money(_value(biggest)), biggest.description)),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  'Top Category',
                  topCategory.key,
                  '${money(topCategory.value)} · ${total == 0 ? 0 : (topCategory.value / total * 100).round()}%',
                  icon: iconForCategory(topCategory.key),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- By date ---------------------------------------------------------------------

  Widget _byDate(List<TripExpense> spend) {
    final days = spend.map((e) => _day(e.dateTime)).toList()..sort();
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
          .where((e) => !_day(e.dateTime).isBefore(start) && _day(e.dateTime).isBefore(end))
          .fold(0.0, (s, e) => s + _value(e));
      return (start, v);
    });
    final total = buckets.fold(0.0, (s, b) => s + b.$2);
    final busiest = buckets.reduce((a, b) => b.$2 > a.$2 ? b : a);
    final activeDays = days.toSet().length;
    String label(DateTime d) => '${d.day} ${_monthsShort[d.month - 1]}';
    return _card(
      title: 'By Date',
      subtitle: weekly
          ? 'Each Week · $activeDays Of $span Days Had Spending'
          : 'Each Day · $activeDays Of $span Day${span == 1 ? '' : 's'} Had Spending',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _fact(weekly ? 'Busiest Week' : 'Busiest Day', '${label(busiest.$1)} · ${compactMoney(busiest.$2)}')),
              const SizedBox(width: 8),
              Expanded(child: _fact('Daily Average', money(total / span))),
            ],
          ),
          const SizedBox(height: 12),
          TimeBarChart(
            height: 150,
            average: total / count,
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
    final counts = <String, int>{};
    for (final e in spend) {
      final c = e.category ?? 'Other';
      now[c] = (now[c] ?? 0) + _value(e);
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final total = now.values.fold(0.0, (s, v) => s + v);
    final slots = donutSlotColors();
    final slices = <DonutSlice>[
      for (final (i, c) in ranked.indexed)
        if ((now[c] ?? 0) > 0) DonutSlice(c, now[c]!, slots[i], icon: iconForCategory(c)),
    ];
    final shown = slices.map((s) => s.label).toSet();
    final other = total - slices.fold(0.0, (s, d) => s + d.value);
    final otherCount = counts.entries.where((e) => !shown.contains(e.key)).fold(0, (s, e) => s + e.value);
    if (other > 0.5) slices.add(DonutSlice('Other', other, otherSliceColor, icon: Icons.more_horiz_rounded));
    return _card(
      title: 'By Category',
      subtitle: '${now.length} Categor${now.length == 1 ? 'y' : 'ies'} · Tap A Slice',
      child: Column(
        children: [
          Center(child: DonutChart(slices: slices, total: total, size: 132)),
          const SizedBox(height: 12),
          for (final s in slices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 8),
                  Icon(s.icon, size: 15, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.label} · ${s.label == 'Other' ? otherCount : counts[s.label] ?? 0}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${total == 0 ? 0 : (s.value / total * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      compactMoney(s.value),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w700),
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
          m.id == _me ? '${m.name} (You)' : m.name,
          _spend.fold(0.0, (s, e) => s + (_byShare ? e.shareOf(m.id) : (e.paidBy == m.id ? e.amount : 0))),
          leading: MemberAvatar.of(m, size: 24, tripId: widget.trip.id),
        ),
    ];
    return _card(
      title: 'By Person',
      subtitle: _byShare ? 'Each Person’s Share Of The Trip' : 'Who Paid For The Trip',
      trailing: _Segmented(
        options: const ['Paid', 'Share'],
        selected: _byShare ? 1 : 0,
        onSelect: (i) => setState(() => _byShare = i == 1),
      ),
      child: HBarChart(data: data, maxRows: 6),
    );
  }

  /// Paid minus share for everyone, settle-ups included: who gets money back.
  Widget _whosAhead() {
    final totals = totalsFromExpenses(widget.expenses);
    final balances = balancesFor(widget.trip.members, totals.paid, totals.owed);
    final settled = balances.where((b) => b.netBalance.abs() < 0.5).length;
    return _card(
      title: 'Who’s Ahead',
      subtitle: settled == balances.length
          ? 'Everyone Is Settled Up'
          : '+ Gets Money Back · − Owes · After Settle-Ups',
      child: DivergingBarChart(
        maxRows: 8,
        data: [
          for (final b in balances)
            BarDatum(
              b.userId == _me ? 'You' : (widget.trip.member(b.userId)?.name ?? b.name),
              b.netBalance,
              leading: widget.trip.member(b.userId) == null
                  ? null
                  : MemberAvatar.of(widget.trip.member(b.userId)!, size: 24, tripId: widget.trip.id),
            ),
        ],
      ),
    );
  }

  // --- By place ---------------------------------------------------------------------------

  Widget _byPlace(List<TripExpense> spend) {
    final sums = <String, double>{};
    for (final e in spend) {
      final city = cityFromLocation(e.location) ?? 'No Location';
      sums[city] = (sums[city] ?? 0) + _value(e);
    }
    final places = sums.keys.where((k) => k != 'No Location').length;
    final top = sums.entries.where((e) => e.key != 'No Location').fold<MapEntry<String, double>?>(
      null,
      (best, e) => best == null || e.value > best.value ? e : best,
    );
    return _card(
      title: 'By Location',
      subtitle: 'Spending In Each City',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _fact('Cities', '$places')),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _fact('Most Spent In', top == null ? '—' : '${top.key} · ${compactMoney(top.value)}')),
            ],
          ),
          const SizedBox(height: 8),
          HBarChart(
            maxRows: 4,
            data: [
              for (final e in sums.entries)
                BarDatum(e.key, e.value, icon: e.key == 'No Location' ? Icons.location_off_outlined : Icons.place_outlined),
            ],
          ),
        ],
      ),
    );
  }

  // --- Time of day --------------------------------------------------------------------------

  Widget _byTime(List<TripExpense> spend) {
    final sums = List.filled(dayParts.length, 0.0);
    final counts = List.filled(dayParts.length, 0);
    for (final e in spend) {
      final p = dayPartOf(e.dateTime);
      sums[p] += _value(e);
      counts[p]++;
    }
    final peak = List.generate(sums.length, (i) => i).reduce((a, b) => sums[b] > sums[a] ? b : a);
    final busiest = List.generate(counts.length, (i) => i).reduce((a, b) => counts[b] > counts[a] ? b : a);
    return _card(
      title: 'Time Of Day',
      subtitle: 'When The Money Goes',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _fact('Most Spent', dayParts[peak].$1)),
              const SizedBox(width: 8),
              Expanded(child: _fact('Most Expenses', '${dayParts[busiest].$1} · ${counts[busiest]}')),
            ],
          ),
          const SizedBox(height: 8),
          HBarChart(
            ranked: false,
            data: [
              for (final (i, p) in dayParts.indexed) BarDatum('${p.$1} · ${p.$2}', sums[i], icon: p.$3),
            ],
          ),
        ],
      ),
    );
  }

  // --- Top expenses ---------------------------------------------------------------------------

  Widget _top(List<TripExpense> spend) {
    final top = ([...spend]..sort((a, b) => _value(b).compareTo(_value(a)))).take(5).toList();
    final total = spend.fold(0.0, (s, e) => s + _value(e));
    final topSum = top.fold(0.0, (s, e) => s + _value(e));
    return _card(
      title: _mine ? 'Your Biggest Shares' : 'Biggest Expenses',
      subtitle: 'The Top ${top.length} Are ${total == 0 ? 0 : (topSum / total * 100).round()}% Of The Spending',
      child: Column(
        children: [
          for (final (i, e) in top.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconCircle(icon: e.icon, color: colorForCategory(e.category), size: 34, outlined: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${e.paidBy == _me ? 'You' : e.payerName(widget.trip)} · ${e.dateTime.day} ${_monthsShort[e.dateTime.month - 1]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money(_value(e)),
                    style: TextStyle(
                      color: ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Pieces ---------------------------------------------------------------------------------

  Widget _tile(String label, String value, String note, {IconData? icon}) => Container(
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
    decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: accent), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3),
              ),
            ),
          ],
        ),
        Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 10.5)),
      ],
    ),
  );

  Widget _fact(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  /// [inPage]: the card fills a carousel page; content taller than the page
  /// (a large system font) scrolls inside it.
  Widget _card({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
    bool inPage = true,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
    decoration: cardDecoration(radius: 22),
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
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
        const SizedBox(height: 12),
        if (inPage)
          Flexible(child: SingleChildScrollView(physics: const ClampingScrollPhysics(), child: child))
        else
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
