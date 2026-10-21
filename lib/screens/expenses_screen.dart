import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../charts.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'location_picker_screen.dart';
import 'trip_home_screen.dart';
import 'trip_insights.dart';
import 'trip_people.dart';
import 'trips_ui.dart';

/// How the list is ordered.
enum ExpenseSort {
  newest('Newest first'),
  oldest('Oldest first'),
  highest('Highest amount'),
  lowest('Lowest amount');

  const ExpenseSort(this.label);
  final String label;
}

/// Everything the Expenses tab can narrow the list by. Each part is optional;
/// a date range and a time window combine (e.g. 20–21 Oct, 6–10 PM).
class ExpenseFilter {
  ExpenseFilter({
    this.dates,
    this.timeFrom,
    this.timeTo,
    Set<int>? dayParts,
    Set<String>? categories,
    Set<String>? places,
    Set<String>? payers,
    this.minAmount,
    this.maxAmount,
    this.settlements = true,
  }) : dayParts = dayParts ?? {},
       categories = categories ?? {},
       places = places ?? {},
       payers = payers ?? {};

  DateTimeRange? dates;
  TimeOfDay? timeFrom, timeTo;

  /// Indexes into [dayParts] (Morning, Afternoon, Evening, Night).
  final Set<int> dayParts;
  final Set<String> categories;

  /// Cities (the last part of a location), or [noPlace].
  final Set<String> places;
  final Set<String> payers;
  double? minAmount, maxAmount;

  /// Settle-up payments are listed too unless this is off.
  bool settlements;

  static const noPlace = 'No location';

  ExpenseFilter copy() => ExpenseFilter(
    dates: dates,
    timeFrom: timeFrom,
    timeTo: timeTo,
    dayParts: {...dayParts},
    categories: {...categories},
    places: {...places},
    payers: {...payers},
    minAmount: minAmount,
    maxAmount: maxAmount,
    settlements: settlements,
  );

  /// How many kinds of filter are on (for the badge).
  int get active => [
    dates != null,
    timeFrom != null || timeTo != null,
    dayParts.isNotEmpty,
    categories.isNotEmpty,
    places.isNotEmpty,
    payers.isNotEmpty,
    minAmount != null || maxAmount != null,
    !settlements,
  ].where((on) => on).length;

  bool matches(TripExpense e) {
    final at = e.dateTime;
    if (!settlements && e.isSettlement) return false;
    final range = dates;
    if (range != null) {
      final day = DateTime(at.year, at.month, at.day);
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      if (day.isBefore(start) || day.isAfter(end)) return false;
    }
    if (timeFrom != null || timeTo != null) {
      final m = at.hour * 60 + at.minute;
      final from = timeFrom == null ? null : timeFrom!.hour * 60 + timeFrom!.minute;
      final to = timeTo == null ? null : timeTo!.hour * 60 + timeTo!.minute;
      final inWindow = from != null && to != null
          ? (from <= to ? m >= from && m <= to : m >= from || m <= to) // a window past midnight wraps
          : from != null
          ? m >= from
          : m <= to!;
      if (!inWindow) return false;
    }
    if (dayParts.isNotEmpty && !dayParts.contains(dayPartOf(at))) return false;
    if (categories.isNotEmpty && !categories.contains(e.category ?? 'Other')) return false;
    if (places.isNotEmpty && !places.contains(cityFromLocation(e.location) ?? noPlace)) return false;
    if (payers.isNotEmpty && !payers.contains(e.paidBy)) return false;
    if (minAmount != null && e.amount < minAmount!) return false;
    if (maxAmount != null && e.amount > maxAmount!) return false;
    return true;
  }
}

/// Free-text search over what an expense says: description, place, category,
/// who paid and the amount.
bool expenseMatchesQuery(TripExpense e, String query, Trip? trip) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return [
    e.description,
    e.location ?? '',
    e.category ?? 'Other',
    e.payerName(trip),
    e.amount.toStringAsFixed(0),
  ].any((s) => s.toLowerCase().contains(q));
}

String _time(TimeOfDay t) {
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

String _shortDate(DateTime d) => '${d.day} ${shortMonth(d.month)}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The Expenses tab: the current trip's expenses, live.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.tripId});
  final String tripId;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _store = TripStore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<TripExpense>? _expenses;
  String? _error;

  Trip? get _trip => _store.trips?.where((t) => t.id == widget.tripId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _sub = ApiClient.instance.watchExpenseSnapshots(widget.tripId).listen(
      (snap) {
        if (mounted) setState(() => _expenses = snap.docs.map(TripExpense.fromDoc).toList());
      },
      onError: (Object e) {
        if (mounted) setState(() => _error = e is ApiException ? e.message : 'Couldn’t load the expenses.');
      },
    );
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip, expenses = _expenses;
    if (trip == null || expenses == null) {
      return Scaffold(
        backgroundColor: paper,
        body: Center(
          child: _error == null
              ? CircularProgressIndicator(color: accent)
              : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
        ),
      );
    }
    return ExpensesView(trip: trip, expenses: expenses, onRefresh: _store.refresh);
  }
}

/// The list itself, for any trip and its expenses: three views (the whole
/// trip, one person, you), search, filters and sorting.
class ExpensesView extends StatefulWidget {
  const ExpensesView({super.key, required this.trip, required this.expenses, this.onRefresh});
  final Trip trip;
  final List<TripExpense> expenses;
  final Future<void> Function()? onRefresh;

  @override
  State<ExpensesView> createState() => _ExpensesViewState();
}

enum _View { trip, people, me }

/// What the "Me" view lists.
enum _Mine { all, paid, share }

class _ExpensesViewState extends State<ExpensesView> {
  _View _view = _View.trip;
  _Mine _mine = _Mine.all;
  String? _person;
  ExpenseFilter _filter = ExpenseFilter();
  ExpenseSort _sort = ExpenseSort.newest;
  final _search = TextEditingController();

  Trip get _trip => widget.trip;
  String get _meId => ApiClient.instance.currentUser?.id ?? '';
  String get _personId => _person ?? (_trip.members.where((m) => m.id != _meId).firstOrNull ?? _trip.members.first).id;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _name(String id) => id == _meId ? 'You' : (_trip.member(id)?.name ?? 'Someone');

  /// The expenses this view is about, before search and filters.
  List<TripExpense> get _scope => switch (_view) {
    _View.trip => widget.expenses,
    _View.people => widget.expenses.where((e) => e.paidBy == _personId || e.shareOf(_personId) > 0).toList(),
    _View.me => widget.expenses.where((e) {
      final paid = e.paidBy == _meId, share = e.shareOf(_meId) > 0;
      return switch (_mine) {
        _Mine.all => paid || share,
        _Mine.paid => paid,
        _Mine.share => share && !paid,
      };
    }).toList(),
  };

  List<TripExpense> get _shown {
    final list = _scope.where((e) => _filter.matches(e) && expenseMatchesQuery(e, _search.text, _trip)).toList();
    switch (_sort) {
      case ExpenseSort.newest:
        list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      case ExpenseSort.oldest:
        list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      case ExpenseSort.highest:
        list.sort((a, b) => b.amount.compareTo(a.amount));
      case ExpenseSort.lowest:
        list.sort((a, b) => a.amount.compareTo(b.amount));
    }
    return list;
  }

  /// Whose share the rows and the summary talk about.
  String? get _focus => switch (_view) {
    _View.trip => null,
    _View.people => _personId,
    _View.me => _meId,
  };

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: accent,
          onRefresh: widget.onRefresh ?? () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverToBoxAdapter(child: _viewSwitch()),
              ),
              if (_view == _View.people)
                SliverPadding(padding: const EdgeInsets.only(top: 14), sliver: SliverToBoxAdapter(child: _personPicker())),
              if (_view == _View.me)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(child: _mineChips()),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(child: _summary(shown)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(child: _searchRow()),
              ),
              if (_filter.active > 0)
                SliverPadding(padding: const EdgeInsets.only(top: 10), sliver: SliverToBoxAdapter(child: _activeFilters())),
              if (shown.isEmpty)
                SliverPadding(padding: const EdgeInsets.fromLTRB(24, 40, 24, 0), sliver: SliverToBoxAdapter(child: _empty()))
              else
                ..._sections(shown),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  // --- Header and view switch ------------------------------------------------------------

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 6, 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Expenses',
                style: TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(_trip.tripKind.icon, size: 14, color: _trip.tripKind.color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _trip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Switch trip',
          onPressed: () => showTripSwitcher(context),
          icon: Icon(Icons.swap_horiz_rounded, color: ink),
        ),
        const ThemeToggle(),
      ],
    ),
  );

  Widget _viewSwitch() {
    const views = [
      (_View.trip, 'Whole trip', Icons.luggage_outlined),
      (_View.people, 'Per person', Icons.groups_outlined),
      (_View.me, 'Me', Icons.person_outline_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)),
      child: Row(
        children: [
          for (final v in views)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _view = v.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: _view == v.$1 ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(v.$3, size: 16, color: _view == v.$1 ? onAccent : muted),
                      const SizedBox(width: 6),
                      Text(
                        v.$2,
                        style: TextStyle(
                          color: _view == v.$1 ? onAccent : ink,
                          fontSize: 12.5,
                          fontWeight: _view == v.$1 ? FontWeight.w800 : FontWeight.w600,
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
  }

  Widget _personPicker() => SizedBox(
    height: 76,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final m in _trip.members)
          GestureDetector(
            onTap: () => setState(() => _person = m.id),
            child: Container(
              width: 70,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: m.id == _personId ? accent : Colors.transparent, width: 2),
                    ),
                    child: MemberAvatar.of(m, size: 42),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m.id == _meId ? 'You' : m.name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: m.id == _personId ? ink : muted,
                      fontSize: 11.5,
                      fontWeight: m.id == _personId ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _mineChips() => Row(
    children: [
      for (final (m, label) in const [
        (_Mine.all, 'All mine'),
        (_Mine.paid, 'I paid'),
        (_Mine.share, 'Others paid for me'),
      ]) ...[
        _chip(label, selected: _mine == m, onTap: () => setState(() => _mine = m)),
        const SizedBox(width: 8),
      ],
    ],
  );

  // --- Summary ------------------------------------------------------------------------

  Widget _summary(List<TripExpense> shown) {
    final spend = shown.where((e) => !e.isSettlement).toList();
    final total = spend.fold(0.0, (s, e) => s + e.amount);
    final focus = _focus;
    final List<(String, String)> stats;
    if (focus == null) {
      final mine = spend.fold(0.0, (s, e) => s + e.shareOf(_meId));
      stats = [('Expenses', '${shown.length}'), ('Spent', compactMoney(total)), ('Your share', compactMoney(mine))];
    } else {
      // Paid and share over everything listed, settle-ups included, so the
      // net is what this list moves.
      final paid = shown.where((e) => e.paidBy == focus).fold(0.0, (s, e) => s + e.amount);
      final share = shown.fold(0.0, (s, e) => s + e.shareOf(focus));
      stats = [('Paid', compactMoney(paid)), ('Share', compactMoney(share)), ('Net', signedMoney(paid - share))];
    }
    final person = _view == _View.people ? _trip.member(_personId) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: cardDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (person != null) ...[
                MemberAvatar.of(person, size: 30, tripId: _trip.id),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  switch (_view) {
                    _View.trip => 'The whole trip',
                    _View.people => person == null ? 'Per person' : '${_name(person.id)}${person.id == _meId ? '' : '’s expenses'}',
                    _View.me => 'Your expenses',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (_filter.active > 0 || _search.text.isNotEmpty)
                Text('filtered', style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, s) in stats.indexed) ...[
                if (i > 0) Container(width: 1, height: 30, color: line, margin: const EdgeInsets.symmetric(horizontal: 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: TextStyle(color: muted, fontSize: 11.5)),
                      const SizedBox(height: 2),
                      Text(
                        s.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: s.$1 == 'Net' ? (s.$2.startsWith('-') ? negative : positive) : ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (spend.isNotEmpty) ...[const SizedBox(height: 14), _categoryBar(spend, focus)],
        ],
      ),
    );
  }

  /// Where the listed money went: one bar split by category (each in its own
  /// colour, 2px gaps), then the biggest three named with their share.
  Widget _categoryBar(List<TripExpense> spend, String? focus) {
    final sums = <String, double>{};
    for (final e in spend) {
      final v = focus == null ? e.amount : e.shareOf(focus);
      if (v > 0) sums[e.category ?? 'Other'] = (sums[e.category ?? 'Other'] ?? 0) + v;
    }
    final total = sums.values.fold(0.0, (s, v) => s + v);
    if (total <= 0) return const SizedBox.shrink();
    final ranked = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final (i, c) in ranked.indexed) ...[
                  if (i > 0) Container(width: 2, color: surface),
                  Expanded(
                    flex: (c.value / total * 1000).round().clamp(1, 1000),
                    child: Container(color: colorForCategory(c.key)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final c in ranked.take(3))
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: colorForCategory(c.key), borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${c.key} ${(c.value / total * 100).round()}%',
                    style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            if (ranked.length > 3)
              Text('+${ranked.length - 3} more', style: TextStyle(color: muted, fontSize: 11.5)),
          ],
        ),
      ],
    );
  }

  // --- Search, sort and filters ----------------------------------------------------------

  Widget _searchRow() => Row(
    children: [
      Expanded(
        child: SizedBox(
          height: 46,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: ink, fontSize: 14),
            decoration: appInputDecoration('Search description, place, category…', Icons.search_rounded).copyWith(
              contentPadding: EdgeInsets.zero,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () => setState(_search.clear),
                      icon: Icon(Icons.close_rounded, size: 18, color: muted),
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      PopupMenuButton<ExpenseSort>(
        tooltip: 'Sort',
        initialValue: _sort,
        onSelected: (s) => setState(() => _sort = s),
        itemBuilder: (_) => [
          for (final s in ExpenseSort.values)
            PopupMenuItem(
              value: s,
              child: Row(
                children: [
                  Icon(s == _sort ? Icons.check_rounded : null, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text(s.label),
                ],
              ),
            ),
        ],
        child: _squareButton(Icons.swap_vert_rounded, active: _sort != ExpenseSort.newest),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _openFilters,
        child: Badge(
          isLabelVisible: _filter.active > 0,
          label: Text('${_filter.active}'),
          backgroundColor: accent,
          textColor: onAccent,
          child: _squareButton(Icons.tune_rounded, active: _filter.active > 0),
        ),
      ),
    ],
  );

  Widget _squareButton(IconData icon, {bool active = false}) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: active ? accentSoft : surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: active ? accent : line),
    ),
    child: Icon(icon, color: active ? accent : ink, size: 21),
  );

  /// One removable chip per filter that's on, then "Clear all".
  Widget _activeFilters() {
    final f = _filter;
    final chips = <(String, VoidCallback)>[
      if (f.dates != null)
        (
          f.dates!.start == f.dates!.end
              ? _shortDate(f.dates!.start)
              : '${_shortDate(f.dates!.start)} – ${_shortDate(f.dates!.end)}',
          () => f.dates = null,
        ),
      if (f.timeFrom != null || f.timeTo != null)
        (
          '${f.timeFrom == null ? 'Until' : _time(f.timeFrom!)}${f.timeFrom != null && f.timeTo != null ? ' – ' : ' '}${f.timeTo == null ? 'onwards' : _time(f.timeTo!)}',
          () => f
            ..timeFrom = null
            ..timeTo = null,
        ),
      for (final p in f.dayParts) (dayParts[p].$1, () => f.dayParts.remove(p)),
      for (final c in f.categories) (c, () => f.categories.remove(c)),
      for (final p in f.places) (p, () => f.places.remove(p)),
      for (final id in f.payers) ('Paid by ${_name(id)}', () => f.payers.remove(id)),
      if (f.minAmount != null || f.maxAmount != null)
        (
          f.minAmount != null && f.maxAmount != null
              ? '${money(f.minAmount!)} – ${money(f.maxAmount!)}'
              : f.minAmount != null
              ? 'From ${money(f.minAmount!)}'
              : 'Up to ${money(f.maxAmount!)}',
          () => f
            ..minAmount = null
            ..maxAmount = null,
        ),
      if (!f.settlements) ('No settle-ups', () => f.settlements = true),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(c.$1),
                labelStyle: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w600),
                backgroundColor: surface,
                side: BorderSide(color: accent.withValues(alpha: .5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                visualDensity: VisualDensity.compact,
                deleteIconColor: muted,
                onDeleted: () => setState(c.$2),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _filter = ExpenseFilter()),
            style: TextButton.styleFrom(foregroundColor: accent, visualDensity: VisualDensity.compact),
            child: const Text('Clear all', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<ExpenseFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSheet(
        trip: _trip,
        expenses: _scope,
        initial: _filter.copy(),
        count: (f) => _scope.where((e) => f.matches(e) && expenseMatchesQuery(e, _search.text, _trip)).length,
      ),
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  Widget _chip(String label, {required bool selected, required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? accentSoft : surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? accent : line),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? accent : ink,
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    ),
  );

  // --- The list -------------------------------------------------------------------------

  Widget _empty() => Column(
    children: [
      const IconCircle(icon: Icons.receipt_long_outlined, size: 64),
      const SizedBox(height: 14),
      Text(
        widget.expenses.isEmpty ? 'No expenses yet' : 'Nothing matches',
        style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        widget.expenses.isEmpty
            ? 'Add the first one with ＋ — or scan a bill — and it’s split with everyone on the trip.'
            : 'Try another view, or loosen the search and filters.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );

  /// By date (newest or oldest first): a heading per day with its total. By
  /// amount: one ranked list.
  List<Widget> _sections(List<TripExpense> shown) {
    final byDate = _sort == ExpenseSort.newest || _sort == ExpenseSort.oldest;
    final groups = <String, List<TripExpense>>{};
    for (final e in shown) {
      final d = e.dateTime;
      final key = byDate ? '${_weekdays[d.weekday - 1]}, ${d.day} ${shortMonth(d.month)} ${d.year}' : _sort.label;
      groups.putIfAbsent(key, () => []).add(e);
    }
    final focus = _focus;
    return [
      for (final (index, entry) in groups.entries.indexed) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, index == 0 ? 22 : 18, 20, 10),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${entry.value.length} · ${money(entry.value.where((e) => !e.isSettlement).fold<double>(0, (s, e) => s + (focus == null ? e.amount : e.shareOf(focus))))}',
                  style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
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
    final me = _meId;
    final iPaid = expense.paidBy == me;
    final share = expense.shareOf(me);
    final delta = iPaid ? expense.amount - share : share;
    final involved = (iPaid || share > 0) && delta >= 0.5;
    final catColor = colorForCategory(expense.category);
    final city = cityFromLocation(expense.location);
    final focus = _view == _View.people ? _personId : null;
    final people = [
      for (final s in expense.shares) _trip.member(s.userId) ?? TripMember(id: s.userId, name: _name(s.userId)),
    ];
    final String title;
    final String detail;
    if (expense.isSettlement) {
      final to = expense.shares.isEmpty ? null : expense.shares.first.userId;
      title = '${_name(expense.paidBy)} paid ${to == null ? 'back' : _name(to)}';
      detail = expense.description;
    } else {
      title = expense.description;
      detail = '${iPaid ? 'You' : expense.payerName(_trip)} paid${city == null ? '' : ' · $city'}';
    }
    // In the per-person view, that person's part of it; elsewhere, yours.
    final String? note;
    final Color noteColor;
    if (expense.isSettlement) {
      note = null;
      noteColor = muted;
    } else if (focus != null && focus != me) {
      final theirs = expense.shareOf(focus);
      note = expense.paidBy == focus
          ? '${_name(focus)} paid${theirs > 0 ? ' · share ${money(theirs)}' : ''}'
          : '${_name(focus)}’s share ${money(theirs)}';
      noteColor = accent;
    } else {
      note = involved ? (iPaid ? 'you lent ${money(delta)}' : 'you owe ${money(delta)}') : null;
      noteColor = iPaid ? positive : negative;
    }
    return AppCard(
      onTap: () => _showExpenseDetails(expense),
      onLongPress: () => _showExpenseActions(expense),
      padding: const EdgeInsets.all(12),
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
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDateAndTime(expense.dateTime)} · ${expense.category ?? 'Other'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 11.5, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 11.5),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: noteColor, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(expense.amount),
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 10),
              AvatarStack(
                members: expense.isSettlement
                    ? [_trip.member(expense.paidBy) ?? TripMember(id: expense.paidBy, name: expense.payerName(_trip)), ...people]
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

  // --- Details, edit and delete (only for expenses you added) ---------------------------------

  Future<void> _sheet(String title, List<Widget> children) =>
      showAppSheet<void>(context, title: title, children: (_) => children);

  Widget _sheetCard(List<Widget> rows) => groupedCard(rows, indent: 58);

  Widget _avatarFor(String userId, {double size = 30}) {
    final member = _trip.member(userId);
    return member != null
        ? MemberAvatar.of(member, size: size, tripId: _trip.id)
        : MemberAvatar(id: userId, name: _name(userId), size: size);
  }

  Future<void> _afterChange() async => widget.onRefresh?.call();

  Future<void> _editExpense(TripExpense expense) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ExpenseSheet(tripId: _trip.id, existing: expense),
    );
    if (updated == true) await _afterChange();
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
            child: Text('Delete', style: TextStyle(color: negative)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteExpense(expense);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  bool _requireOwnership(TripExpense expense) {
    if (expense.paidBy == _meId) return true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can only edit expenses you added.')));
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
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(expense.dateTime));
    if (time == null || !mounted) return;
    final newDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ApiClient.instance.updateExpense(
        existing: expense,
        trip: _trip,
        description: expense.description,
        amount: expense.amount,
        category: expense.category,
        date: newDateTime.toIso8601String(),
        location: expense.location,
      );
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
        existing: expense,
        trip: _trip,
        description: expense.description,
        amount: expense.amount,
        category: expense.category,
        date: expense.date,
        location: result,
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showExpenseActions(TripExpense expense) async {
    if (expense.paidBy != _meId) {
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
        decoration: BoxDecoration(color: paper, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 10),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: ink),
                title: Text('Edit expense', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: negative),
                title: Text('Delete expense', style: TextStyle(fontWeight: FontWeight.w700, color: negative)),
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

  void _showExpenseDetails(TripExpense expense) {
    final isOwn = expense.paidBy == _meId;
    final catColor = colorForCategory(expense.category);
    final shares = [...expense.shares]..sort((a, b) => (a.userId == _meId ? 0 : 1) - (b.userId == _meId ? 0 : 1));
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
                  style: TextStyle(color: ink, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.6),
                ),
                Text(
                  '${isOwn ? 'You' : expense.payerName(_trip)} paid · ${expense.category ?? 'Other'}',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _sheetCard([
        _detailRow(
          Icons.schedule_outlined,
          formatDateAndTime(expense.dateTime),
          isOwn
              ? () {
                  Navigator.pop(context);
                  _quickEditDateTime(expense);
                }
              : null,
        ),
        _detailRow(
          Icons.location_on_outlined,
          expense.location ?? 'No location',
          isOwn
              ? () {
                  Navigator.pop(context);
                  _quickEditLocation(expense);
                }
              : null,
        ),
      ]),
      const SizedBox(height: 18),
      fieldLabel(expense.isSettlement ? 'PAID TO' : 'SPLIT'),
      const SizedBox(height: 8),
      _sheetCard([
        for (final s in shares)
          InkWell(
            onTap: () => openMember(context, _trip.id, s.userId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  _avatarFor(s.userId),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.userId == expense.paidBy
                          ? '${_name(s.userId)} paid ${money(expense.amount)}, owe${s.userId == _meId ? '' : 's'} ${money(s.shareAmount)}'
                          : '${_name(s.userId)} owe${s.userId == _meId ? '' : 's'} ${money(s.shareAmount)}',
                      style: TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: s.userId == _meId ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
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
                  foregroundColor: negative,
                  side: BorderSide(color: negative.withValues(alpha: .3)),
                  backgroundColor: surface,
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
                  foregroundColor: onAccent,
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
              style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (onTap != null) Icon(Icons.edit_outlined, size: 15, color: muted),
        ],
      ),
    ),
  );
}

/// Filters: dates, a time window or parts of the day, categories, places,
/// who paid, an amount range and settle-ups. The button says how many
/// expenses the choice leaves.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.trip, required this.expenses, required this.initial, required this.count});
  final Trip trip;
  final List<TripExpense> expenses;
  final ExpenseFilter initial;
  final int Function(ExpenseFilter) count;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ExpenseFilter _f = widget.initial;
  late final _min = TextEditingController(text: _f.minAmount?.toStringAsFixed(0) ?? '');
  late final _max = TextEditingController(text: _f.maxAmount?.toStringAsFixed(0) ?? '');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final seen = {for (final e in widget.expenses.where((e) => !e.isSettlement)) e.category ?? 'Other'};
    return [...categoryOrder.where(seen.contains), ...seen.where((c) => !categoryOrder.contains(c))];
  }

  List<String> get _places {
    final counts = <String, int>{};
    for (final e in widget.expenses) {
      final p = cityFromLocation(e.location) ?? ExpenseFilter.noPlace;
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).toList();
  }

  Future<void> _pickDates() async {
    final days = widget.expenses.map((e) => e.dateTime).toList()..sort();
    final now = DateTime.now();
    final first = days.isEmpty ? now.subtract(const Duration(days: 365)) : days.first;
    final last = days.isEmpty ? now : days.last;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(first.year - 1),
      lastDate: DateTime(last.year + 1),
      initialDateRange: _f.dates ?? DateTimeRange(start: DateTime(first.year, first.month, first.day), end: DateTime(last.year, last.month, last.day)),
    );
    if (range != null) setState(() => _f.dates = range);
  }

  Future<void> _pickTime(bool from) async {
    final t = await showTimePicker(
      context: context,
      initialTime: (from ? _f.timeFrom : _f.timeTo) ?? (from ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 21, minute: 0)),
    );
    if (t == null) return;
    setState(() => from ? _f.timeFrom = t : _f.timeTo = t);
  }

  void _readAmounts() {
    _f.minAmount = double.tryParse(_min.text.trim());
    _f.maxAmount = double.tryParse(_max.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    _readAmounts();
    final n = widget.count(_f);
    return DraggableScrollableSheet(
      initialChildSize: .88,
      maxChildSize: .95,
      minChildSize: .5,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(color: paper, borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Filters', style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _f = ExpenseFilter();
                      _min.clear();
                      _max.clear();
                    }),
                    style: TextButton.styleFrom(foregroundColor: accent),
                    child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _section('DATE'),
                  _pickerButton(
                    Icons.date_range_rounded,
                    _f.dates == null
                        ? 'Any date'
                        : _f.dates!.start == _f.dates!.end
                        ? _shortDate(_f.dates!.start)
                        : '${_shortDate(_f.dates!.start)} – ${_shortDate(_f.dates!.end)}',
                    _pickDates,
                    onClear: _f.dates == null ? null : () => setState(() => _f.dates = null),
                  ),
                  _section('TIME'),
                  Row(
                    children: [
                      Expanded(
                        child: _pickerButton(
                          Icons.schedule_rounded,
                          _f.timeFrom == null ? 'From any time' : 'From ${_time(_f.timeFrom!)}',
                          () => _pickTime(true),
                          onClear: _f.timeFrom == null ? null : () => setState(() => _f.timeFrom = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _pickerButton(
                          Icons.schedule_rounded,
                          _f.timeTo == null ? 'To any time' : 'To ${_time(_f.timeTo!)}',
                          () => _pickTime(false),
                          onClear: _f.timeTo == null ? null : () => setState(() => _f.timeTo = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (i, p) in dayParts.indexed)
                        _toggle(p.$1, _f.dayParts.contains(i), () => _flip(_f.dayParts, i), icon: p.$3),
                    ],
                  ),
                  _section('CATEGORY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _categories)
                        _toggle(c, _f.categories.contains(c), () => _flip(_f.categories, c), icon: iconForCategory(c)),
                    ],
                  ),
                  _section('LOCATION'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in _places)
                        _toggle(
                          p,
                          _f.places.contains(p),
                          () => _flip(_f.places, p),
                          icon: p == ExpenseFilter.noPlace ? Icons.location_off_outlined : Icons.place_outlined,
                        ),
                    ],
                  ),
                  _section('PAID BY'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in widget.trip.members)
                        _toggle(
                          m.id == ApiClient.instance.currentUser?.id ? 'You' : m.name,
                          _f.payers.contains(m.id),
                          () => _flip(_f.payers, m.id),
                          leading: MemberAvatar.of(m, size: 20),
                        ),
                    ],
                  ),
                  _section('AMOUNT (₹)'),
                  Row(
                    children: [
                      Expanded(child: _amountField(_min, 'Min')),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('to', style: TextStyle(color: muted)),
                      ),
                      Expanded(child: _amountField(_max, 'Max')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: line)),
                    clipBehavior: Clip.antiAlias,
                    child: SwitchListTile(
                      value: _f.settlements,
                      onChanged: (v) => setState(() => _f.settlements = v),
                      activeThumbColor: accent,
                      title: Text('Show settle-up payments', style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Money paid back between tripmates', style: TextStyle(color: muted, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      _readAmounts();
                      Navigator.pop(context, _f);
                    },
                    style: primaryButton(),
                    child: Text('Show $n expense${n == 1 ? '' : 's'}'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _flip<T>(Set<T> set, T value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  Widget _section(String text) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 10), child: fieldLabel(text));

  Widget _pickerButton(IconData icon, String text, VoidCallback onTap, {VoidCallback? onClear}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onClear == null ? line : accent),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: onClear == null ? muted : accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: muted)),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    ),
  );

  Widget _toggle(String label, bool on, VoidCallback onTap, {IconData? icon, Widget? leading}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(leading != null ? 6 : 12, 7, 13, 7),
      decoration: BoxDecoration(
        color: on ? accentSoft : surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? accent : line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 15, color: on ? accent : muted), const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(color: on ? accent : ink, fontSize: 12.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget _amountField(TextEditingController controller, String hint) => SizedBox(
    height: 46,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: ink, fontSize: 14),
      decoration: appInputDecoration(hint, Icons.currency_rupee_rounded).copyWith(contentPadding: EdgeInsets.zero),
    ),
  );
}
