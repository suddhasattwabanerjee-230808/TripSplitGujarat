import 'dart:math' as math;

import 'package:flutter/material.dart';

// The colours of Kutch ajrakh block prints: indigo, madder red, iron black
// and the unbleached ivory of the resist dots.
const ajrakhIndigo = Color(0xFF172443);
const ajrakhMadder = Color(0xFF6E1219);
const ajrakhMadderBright = Color(0xFF8E1C24);
const ajrakhBlack = Color(0xFF0F0809);
const ajrakhIvory = Color(0xFFF1E4CC);
const ajrakhSaffron = Color(0xFFFFB45C);

/// A full-bleed ajrakh print, faint and dark: a lattice of eight-point star
/// medallions with dotted resist outlines and sawtooth borders, laid sheer
/// over black and dimmed towards the middle so whatever sits on it (the
/// logo) stands out. Static, so it's
/// painted once and cached.
class AjrakhBackground extends StatelessWidget {
  const AjrakhBackground({super.key, this.tile = 92});

  /// One repeat of the pattern, in logical pixels.
  final double tile;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _AjrakhPainter(tile), size: Size.infinite),
  );
}

class _AjrakhPainter extends CustomPainter {
  _AjrakhPainter(this.tile);
  final double tile;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // The print is laid faintly over black, like a dark, sheer ajrakh.
    canvas.drawRect(rect, Paint()..color = ajrakhBlack);
    canvas.saveLayer(rect, Paint()..color = Colors.white.withValues(alpha: .42));
    canvas.drawRect(rect, Paint()..color = ajrakhMadder);

    // Centre the lattice so a medallion sits right behind the middle.
    final c = size.center(Offset.zero);
    final x0 = c.dx - (c.dx / tile).ceil() * tile - tile / 2;
    final y0 = c.dy - (c.dy / tile).ceil() * tile - tile / 2;
    for (var y = y0; y < size.height + tile; y += tile) {
      for (var x = x0; x < size.width + tile; x += tile) {
        _medallion(canvas, Offset(x + tile / 2, y + tile / 2));
      }
    }
    for (var y = y0; y < size.height + tile; y += tile) {
      for (var x = x0; x < size.width + tile; x += tile) {
        _knot(canvas, Offset(x, y));
      }
    }

    _border(canvas, size, top: true);
    _border(canvas, size, top: false);
    canvas.restore();

    // Darker still, most in the middle, so the print is a quiet ground the
    // logo glows out of.
    canvas.drawRect(rect, Paint()..color = ajrakhBlack.withValues(alpha: .3));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -.1),
          radius: 1.1,
          colors: [
            ajrakhBlack.withValues(alpha: .92),
            ajrakhBlack.withValues(alpha: .7),
            ajrakhBlack.withValues(alpha: .15),
          ],
          stops: const [0, .45, 1],
        ).createShader(rect),
    );
  }

  /// The eight-point star: indigo, outlined in ivory resist dots, a madder
  /// disc inside with a black eight-petal rosette.
  void _medallion(Canvas canvas, Offset c) {
    final r = tile * .44;
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final a = -math.pi / 2 + i * math.pi / 8;
      final rr = i.isEven ? r : r * .74;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = ajrakhIndigo);
    _dots(canvas, star, ajrakhIvory, spacing: tile * .055, radius: tile * .011);

    canvas.drawCircle(c, r * .58, Paint()..color = ajrakhMadderBright);
    canvas.drawCircle(
      c,
      r * .58,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tile * .012
        ..color = ajrakhIvory.withValues(alpha: .85),
    );

    final petal = Paint()..color = ajrakhBlack;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tile * .008
      ..color = ajrakhIvory.withValues(alpha: .7);
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * math.pi / 4);
      final p = Rect.fromCenter(center: Offset(0, -r * .3), width: r * .2, height: r * .42);
      canvas.drawOval(p, petal);
      canvas.drawOval(p, edge);
      canvas.restore();
    }
    canvas.drawCircle(c, r * .1, Paint()..color = ajrakhIvory);
    canvas.drawCircle(c, r * .045, Paint()..color = ajrakhMadder);
  }

  /// Where four tiles meet: a black diamond with ivory dots at its points.
  void _knot(Canvas canvas, Offset c) {
    final r = tile * .13;
    final diamond = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r, c.dy)
      ..lineTo(c.dx, c.dy + r)
      ..lineTo(c.dx - r, c.dy)
      ..close();
    canvas.drawPath(diamond, Paint()..color = ajrakhBlack);
    final dot = Paint()..color = ajrakhIvory;
    for (final d in [Offset(0, -r), Offset(r, 0), Offset(0, r), Offset(-r, 0)]) {
      canvas.drawCircle(c + d * 1.35, tile * .016, dot);
    }
    canvas.drawCircle(c, tile * .022, Paint()..color = ajrakhMadderBright);
  }

  /// A border band: black with an ivory sawtooth, as on the logo's edge.
  void _border(Canvas canvas, Size size, {required bool top}) {
    final h = tile * .34;
    final y = top ? 0.0 : size.height - h;
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), Paint()..color = ajrakhBlack);
    final teeth = Path();
    final w = h * .62;
    final base = top ? y + h : y;
    final tip = top ? y + h * .3 : y + h * .7;
    for (var x = 0.0; x < size.width + w; x += w) {
      teeth
        ..moveTo(x, base)
        ..lineTo(x + w / 2, tip)
        ..lineTo(x + w, base)
        ..close();
    }
    canvas.drawPath(teeth, Paint()..color = ajrakhMadderBright);
    _dots(
      canvas,
      Path()
        ..moveTo(0, top ? y + h * .14 : y + h * .86)
        ..lineTo(size.width, top ? y + h * .14 : y + h * .86),
      ajrakhIvory,
      spacing: tile * .07,
      radius: tile * .012,
    );
    final rule = top ? y + h : y;
    canvas.drawLine(
      Offset(0, rule),
      Offset(size.width, rule),
      Paint()
        ..color = ajrakhIvory.withValues(alpha: .8)
        ..strokeWidth = tile * .014,
    );
  }

  /// Ivory resist dots along [path].
  void _dots(Canvas canvas, Path path, Color color, {required double spacing, required double radius}) {
    final paint = Paint()..color = color;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += spacing) {
        final t = metric.getTangentForOffset(d);
        if (t != null) canvas.drawCircle(t.position, radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AjrakhPainter old) => old.tile != tile;
}
