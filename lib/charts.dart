import 'package:flutter/material.dart';

import 'theme.dart';

/// One bar: a label (with an optional icon or leading widget) and its value.
class BarDatum {
  const BarDatum(this.label, this.value, {this.icon, this.leading});
  final String label;
  final double value;
  final IconData? icon;
  final Widget? leading;
}

/// Ranked horizontal bars, one hue, values in ink beside each bar. Tapping a
/// row shows its share of the total.
class HBarChart extends StatefulWidget {
  const HBarChart({super.key, required this.data, this.maxRows = 8});
  final List<BarDatum> data;
  final int maxRows;

  @override
  State<HBarChart> createState() => _HBarChartState();
}

class _HBarChartState extends State<HBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.data]..sort((a, b) => b.value.compareTo(a.value));
    // Past maxRows, fold the tail into "Other" rather than inventing more rows.
    final rows = sorted.length <= widget.maxRows
        ? sorted
        : [
            ...sorted.take(widget.maxRows - 1),
            BarDatum(
              'Everything else',
              sorted.skip(widget.maxRows - 1).fold(0.0, (s, d) => s + d.value),
              icon: Icons.more_horiz_rounded,
            ),
          ];
    final total = rows.fold(0.0, (s, d) => s + d.value);
    final maxValue = rows.isEmpty ? 0.0 : rows.first.value;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _selected = _selected == i ? null : i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child:
                        rows[i].leading ??
                        Icon(rows[i].icon ?? Icons.circle_outlined, size: 18, color: _selected == i ? accent : muted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                rows[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                _selected == i && total > 0
                                    ? '${(rows[i].value / total * 100).round()}% · ${money(rows[i].value)}'
                                    : money(rows[i].value),
                                key: ValueKey(_selected == i),
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (context, c) => Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(color: line.withValues(alpha: .7), borderRadius: BorderRadius.circular(4)),
                              ),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: maxValue == 0 ? 0 : rows[i].value / maxValue),
                                duration: Duration(milliseconds: 500 + i * 60),
                                curve: Curves.easeOutCubic,
                                builder: (_, f, _) => Container(
                                  width: c.maxWidth * f,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _selected == null || _selected == i ? accent : accent.withValues(alpha: .35),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Spending over time: one bar per day (or month), a recessive baseline, the
/// peak value as the only gridline label, and a tap-for-detail readout.
class TimeBarChart extends StatefulWidget {
  const TimeBarChart({super.key, required this.buckets, this.height = 150});

  /// In order, oldest first. Labels are short ("12", "Sep").
  final List<BarDatum> buckets;
  final double height;

  @override
  State<TimeBarChart> createState() => _TimeBarChartState();
}

class _TimeBarChartState extends State<TimeBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final peak = buckets.fold(0.0, (m, b) => b.value > m ? b.value : m);
    final sel = _selected != null && _selected! < buckets.length ? buckets[_selected!] : null;
    // Label every nth bucket so the axis never crowds.
    final every = (buckets.length / 6).ceil().clamp(1, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              sel == null ? 'Peak ${money(peak)}' : '${sel.label} · ${money(sel.value)}',
              key: ValueKey(sel?.label),
              style: TextStyle(color: sel == null ? muted : ink, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              // The peak gridline, dashed-look via low alpha.
              Positioned(top: 0, left: 0, right: 0, child: Container(height: 1, color: line)),
              Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 1, color: const Color(0xFFD5D8E2))),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < buckets.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _selected = _selected == i ? null : i),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            // A 2px gap between neighbouring bars.
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: peak == 0 ? 0 : buckets[i].value / peak),
                              duration: const Duration(milliseconds: 550),
                              curve: Curves.easeOutCubic,
                              builder: (_, f, _) => Container(
                                constraints: const BoxConstraints(maxWidth: 22),
                                height: buckets[i].value > 0 ? (widget.height * f).clamp(2, widget.height) : 0,
                                decoration: BoxDecoration(
                                  color: _selected == null || _selected == i ? accent : accent.withValues(alpha: .35),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < buckets.length; i++)
              Expanded(
                child: Text(
                  i % every == 0 ? buckets[i].label : '',
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
