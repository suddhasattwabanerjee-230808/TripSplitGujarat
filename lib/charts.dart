import 'dart:math' as math;

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
  const HBarChart({super.key, required this.data, this.maxRows = 8, this.ranked = true});
  final List<BarDatum> data;
  final int maxRows;

  /// Largest first; false keeps the given order (e.g. times of day).
  final bool ranked;

  @override
  State<HBarChart> createState() => _HBarChartState();
}

class _HBarChartState extends State<HBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.data];
    if (widget.ranked) sorted.sort((a, b) => b.value.compareTo(a.value));
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
    final maxValue = rows.fold(0.0, (m, d) => math.max(m, d.value));
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
  const TimeBarChart({super.key, required this.buckets, this.height = 150, this.average});

  /// In order, oldest first. Labels are short ("12", "Sep").
  final List<BarDatum> buckets;
  final double height;

  /// Drawn as a dashed reference line across the bars when set.
  final double? average;

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
              Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 1, color: muted.withValues(alpha: .35))),
              if (widget.average != null && peak > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: widget.height * (widget.average! / peak).clamp(0.0, 1.0),
                  child: _AverageLine(label: 'avg ${compactMoney(widget.average!)}'),
                ),
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

/// A dashed hairline with its value at the right end (the bar chart's average).
class _AverageLine extends StatelessWidget {
  const _AverageLine({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 14,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashPainter(ink.withValues(alpha: .45))),
        ),
        Positioned(
          right: 0,
          bottom: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: surface,
            child: Text(label, style: TextStyle(color: muted, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 4, size.width), 0), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Who is ahead and who is behind: one row per person, bars growing right
/// (gets back, [positive]) or left (owes, [negative]) from a zero line, the
/// amount in ink at the end. Polarity is also in the sign, never colour alone.
class DivergingBarChart extends StatelessWidget {
  const DivergingBarChart({super.key, required this.data, this.maxRows = 6});
  final List<BarDatum> data;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    final rows = ([...data]..sort((a, b) => b.value.compareTo(a.value))).take(maxRows).toList();
    final peak = rows.fold(0.0, (m, d) => math.max(m, d.value.abs()));
    return Column(
      children: [
        for (final (i, d) in rows.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(width: 26, child: d.leading ?? Icon(d.icon ?? Icons.circle_outlined, size: 18, color: muted)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 74,
                  child: Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final half = c.maxWidth / 2;
                      final f = peak == 0 ? 0.0 : d.value.abs() / peak;
                      final settled = d.value.abs() < 0.5;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: settled ? 0 : f),
                        duration: Duration(milliseconds: 500 + i * 60),
                        curve: Curves.easeOutCubic,
                        builder: (_, t, _) => SizedBox(
                          height: 18,
                          child: Stack(
                            children: [
                              Positioned(
                                left: half - .5,
                                top: 0,
                                bottom: 0,
                                child: Container(width: 1, color: muted.withValues(alpha: .5)),
                              ),
                              Positioned(
                                left: d.value >= 0 ? half + 1 : half - 1 - (half - 1) * t,
                                top: 4,
                                child: Container(
                                  width: (half - 1) * t,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: d.value >= 0 ? positive : negative,
                                    borderRadius: d.value >= 0
                                        ? const BorderRadius.horizontal(right: Radius.circular(4))
                                        : const BorderRadius.horizontal(left: Radius.circular(4)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 66,
                  child: Text(
                    d.value.abs() < 0.5 ? 'settled' : signedMoney(d.value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Indian-style compact amounts for axes and tiles: ₹950, ₹12.9K, ₹1.2L, ₹3.4Cr.
String compactMoney(double v) {
  final a = v.abs(), sign = v < 0 ? '-' : '';
  String trim(double x) => x >= 100 ? x.toStringAsFixed(0) : x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  if (a >= 1e7) return '$sign₹${trim(a / 1e7)}Cr';
  if (a >= 1e5) return '$sign₹${trim(a / 1e5)}L';
  if (a >= 1e3) return '$sign₹${trim(a / 1e3)}K';
  return '$sign₹${a.toStringAsFixed(0)}';
}

/// One point of a [TrendChart].
class TrendPoint {
  const TrendPoint(this.label, this.tooltip, this.value);

  /// Axis label (shown for a few points only) and the tooltip's heading.
  final String label;
  final String tooltip;
  final double value;
}

/// One series over time: a 2px accent line over a 10% wash, hairline grid with
/// compact ticks, and an end dot. Touch or drag for a crosshair and tooltip.
class TrendChart extends StatefulWidget {
  const TrendChart({super.key, required this.points, this.height = 180});
  final List<TrendPoint> points;
  final double height;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  int? _selected;
  static const _left = 44.0, _bottom = 22.0, _top = 10.0;

  void _pick(Offset at, double width) {
    final n = widget.points.length;
    if (n == 0) return;
    final x = ((at.dx - _left) / (width - _left)).clamp(0.0, 1.0);
    setState(() => _selected = n == 1 ? 0 : (x * (n - 1)).round());
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _pick(d.localPosition, c.maxWidth),
      onHorizontalDragStart: (d) => _pick(d.localPosition, c.maxWidth),
      onHorizontalDragUpdate: (d) => _pick(d.localPosition, c.maxWidth),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              widget.points,
              _selected,
              t,
              colors: (accent: accent, line: line, muted: muted, ink: ink, surface: surface),
            ),
          ),
        ),
      ),
    ),
  );
}

typedef _ChartColors = ({Color accent, Color line, Color muted, Color ink, Color surface});

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.selected, this.progress, {required this.colors});
  final List<TrendPoint> points;
  final int? selected;
  final double progress;
  final _ChartColors colors;

  static const _left = _TrendChartState._left, _bottom = _TrendChartState._bottom, _top = _TrendChartState._top;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final plot = Rect.fromLTRB(_left, _top, size.width - 6, size.height - _bottom);
    final peak = points.fold(0.0, (m, p) => p.value > m ? p.value : m);
    final top = _niceCeil(peak <= 0 ? 100 : peak);
    TextPainter label(String s, {Color? color, FontWeight weight = FontWeight.w500, double size = 10.5}) => TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color ?? colors.muted, fontSize: size, fontWeight: weight, fontFamily: 'Manrope')),
      textDirection: TextDirection.ltr,
    )..layout();

    // Hairline grid and compact ticks at 0, ½ and the top.
    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    for (final f in [0.0, .5, 1.0]) {
      final y = plot.bottom - plot.height * f;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tick = label(compactMoney(top * f));
      tick.paint(canvas, Offset(plot.left - tick.width - 8, y - tick.height / 2));
    }

    Offset at(int i) {
      final x = points.length == 1 ? plot.center.dx : plot.left + plot.width * i / (points.length - 1);
      return Offset(x, plot.bottom - plot.height * (points[i].value / top) * progress);
    }

    // X labels: first, middle, last.
    for (final i in {0, (points.length - 1) ~/ 2, points.length - 1}) {
      final l = label(points[i].label);
      final x = (at(i).dx - l.width / 2).clamp(plot.left - 6, size.width - l.width);
      l.paint(canvas, Offset(x, plot.bottom + 6));
    }

    // Smooth line (monotone-ish cubic) over a soft wash.
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final a = at(i - 1), b = at(i), mid = (b.dx - a.dx) / 2;
      path.cubicTo(a.dx + mid, a.dy, b.dx - mid, b.dy, b.dx, b.dy);
    }
    final area = Path.from(path)
      ..lineTo(at(points.length - 1).dx, plot.bottom)
      ..lineTo(at(0).dx, plot.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.accent.withValues(alpha: .18), colors.accent.withValues(alpha: 0)],
        ).createShader(plot),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    void dot(Offset p) {
      canvas.drawCircle(p, 6, Paint()..color = colors.surface); // 2px surface ring
      canvas.drawCircle(p, 4, Paint()..color = colors.accent);
    }

    final sel = selected;
    if (sel == null) {
      dot(at(points.length - 1));
      return;
    }
    // Crosshair, dot and tooltip for the touched point.
    final p = at(sel);
    canvas.drawLine(Offset(p.dx, plot.top), Offset(p.dx, plot.bottom), grid);
    dot(p);
    final head = label(points[sel].tooltip, size: 10.5);
    final value = label(money(points[sel].value), color: colors.ink, weight: FontWeight.w800, size: 13);
    final w = (head.width > value.width ? head.width : value.width) + 20, h = head.height + value.height + 14;
    final left = (p.dx - w / 2).clamp(plot.left, size.width - w);
    final top0 = (p.dy - h - 12).clamp(0.0, size.height - h);
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(left, top0, w, h), const Radius.circular(10));
    canvas.drawRRect(box.shift(const Offset(0, 2)), Paint()..color = const Color(0x22000000));
    canvas.drawRRect(box, Paint()..color = colors.surface);
    canvas.drawRRect(
      box,
      Paint()
        ..color = colors.line
        ..style = PaintingStyle.stroke,
    );
    head.paint(canvas, Offset(left + 10, top0 + 6));
    value.paint(canvas, Offset(left + 10, top0 + 8 + head.height));
  }

  /// 1, 2, 2.5 or 5 times a power of ten, at or above [v].
  static double _niceCeil(double v) {
    var p = 1.0;
    while (p * 10 <= v) {
      p *= 10;
    }
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (p * m >= v) return p * m;
    }
    return p * 10;
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.selected != selected || old.progress != progress || old.colors != colors;
}

/// A slice of a [DonutChart].
class DonutSlice {
  const DonutSlice(this.label, this.value, this.color, {this.icon});
  final String label;
  final double value;
  final Color color;
  final IconData? icon;
}

/// Part-to-whole at a glance (<= 5 slices: 4 categories + Other), a 2px gap
/// in the surface colour between slices. Tap a slice: the others dim and the
/// centre shows it; tap again to go back to the total.
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.slices, required this.total, this.size = 168, this.caption = 'spent'});
  final List<DonutSlice> slices;
  final double total;
  final double size;
  final String caption;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _selected;

  void _tap(Offset at) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final v = at - c;
    final r = v.distance;
    if (r < widget.size * .28 || r > widget.size / 2) {
      setState(() => _selected = null);
      return;
    }
    var angle = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    final sum = widget.slices.fold(0.0, (s, d) => s + d.value);
    var acc = 0.0;
    for (var i = 0; i < widget.slices.length; i++) {
      acc += widget.slices[i].value / sum * 2 * math.pi;
      if (angle <= acc) {
        setState(() => _selected = _selected == i ? null : i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected != null && _selected! < widget.slices.length ? widget.slices[_selected!] : null;
    return GestureDetector(
      onTapUp: (d) => _tap(d.localPosition),
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _DonutPainter(widget.slices, _selected, t, surface),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sel?.label ?? 'Total',
                  style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  compactMoney(sel?.value ?? widget.total),
                  style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.5),
                ),
                Text(
                  sel == null
                      ? widget.caption
                      : '${widget.total == 0 ? 0 : (sel.value / widget.total * 100).round()}%',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.selected, this.progress, this.gapColor);
  final List<DonutSlice> slices;
  final int? selected;
  final double progress;
  final Color gapColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sum = slices.fold(0.0, (s, d) => s + d.value);
    if (sum <= 0) return;
    const stroke = 20.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 2);
    final radius = rect.width / 2;
    final gap = slices.length > 1 ? 2 / radius : 0.0; // 2px surface gap
    var start = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].value / sum * 2 * math.pi * progress;
      final dim = selected != null && selected != i;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(0, sweep - gap),
        false,
        Paint()
          ..color = dim ? slices[i].color.withValues(alpha: .3) : slices[i].color
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected == i ? stroke + 4 : stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// A tiny trend for a stat tile: de-emphasised line, the latest point in the accent.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.width = 84, this.height = 28});
  final List<double> values;
  final double width, height;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: _SparkPainter(values, muted, accent, surface));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.lineColor, this.dotColor, this.ring);
  final List<double> values;
  final Color lineColor, dotColor, ring;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = values.fold(0.0, (m, v) => v > m ? v : m);
    Offset at(int i) => Offset(
      size.width * i / (values.length - 1),
      size.height - 4 - (size.height - 8) * (peak == 0 ? 0 : values[i] / peak),
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final end = at(values.length - 1);
    canvas.drawCircle(end, 4.5, Paint()..color = ring);
    canvas.drawCircle(end, 3, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

/// Donut slice colours: the dataviz reference categorical palette, slots 1-4
/// in this order, validated for colour-blind separation on the white and the
/// dark card surface (including the ring's wrap-around pair). Past four,
/// fold into "Other" ([otherSliceColor]).
List<Color> donutSlotColors() => AppTheme.instance.dark
    ? const [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500)]
    : const [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100)];

Color get otherSliceColor => muted.withValues(alpha: .45);
