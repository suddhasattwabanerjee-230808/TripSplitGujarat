import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A real lion (a cut-out photo, assets/lion.webp) that bursts out of
/// [origin], charges at the screen, roars, then blows away as dust. Drawn
/// full-screen on a transparent background over the UPI pop-up's
/// "Expense added", with the roar sound started through [onRoar].
///
/// Photo: "Hear me roar" by Adam King, Yorkshire Wildlife Park, via Unsplash /
/// Wikimedia Commons, CC0.
class LionCharge extends StatefulWidget {
  const LionCharge({super.key, required this.origin, this.onRoar});

  /// Where it bursts out from, in global coordinates (read every frame, so it
  /// can follow a widget that's still settling). Null = bottom centre.
  final Offset? Function() origin;

  /// When the roar sound should start: just before the lion lands.
  final VoidCallback? onRoar;

  static const duration = Duration(milliseconds: 3000);

  static Future<ui.Image>? _image;

  /// Starts decoding the photo early so it's ready the moment it's needed.
  static Future<ui.Image> preload() => _image ??= () async {
    final data = await rootBundle.load('assets/lion.webp');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }();

  @override
  State<LionCharge> createState() => _LionChargeState();
}

class _LionChargeState extends State<LionCharge> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: LionCharge.duration)..addListener(_cues);
  ui.Image? _image;
  final _dust = _Dust(Random(7));
  bool _roared = false, _landed = false;

  @override
  void initState() {
    super.initState();
    LionCharge.preload().then((image) {
      if (!mounted) return;
      setState(() => _image = image);
      _controller.forward();
    });
  }

  void _cues() {
    final s = _controller.value * 3;
    if (!_roared && s >= _Timeline.roarCue) {
      _roared = true;
      widget.onRoar?.call();
    }
    if (!_landed && s >= _Timeline.land) {
      _landed = true;
      HapticFeedback.heavyImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'A lion roaring',
      image: true,
      child: SizedBox.expand(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final box = context.findRenderObject() as RenderBox?;
            final global = widget.origin();
            final origin = global != null && box != null && box.hasSize ? box.globalToLocal(global) : null;
            return CustomPaint(painter: _LionPainter(image, _controller.value * 3, origin, _dust, still: still));
          },
        ),
      ),
    );
  }
}

/// The beats, in seconds.
abstract final class _Timeline {
  static const land = .5; // arrives full-size
  static const roarCue = .38; // sound starts (its roar kicks in ~0.1 s later)
  static const dissolve = 2.1; // starts blowing away
  static const end = 3.0;
}

/// Per-fragment randomness for the dissolve, fixed so every run looks alike.
class _Dust {
  _Dust(Random r) : seeds = List.generate(_cols * _rows, (_) => [r.nextDouble(), r.nextDouble(), r.nextDouble()]);

  static const _cols = 64, _rows = 106; // ~6,800 grains: fine enough to read as dust
  final List<List<double>> seeds;
}

class _LionPainter extends CustomPainter {
  _LionPainter(this.image, this.s, this.origin, this.dust, {required this.still});

  final ui.Image image;
  final double s;
  final Offset? origin;
  final _Dust dust;
  final bool still;

  // The mouth, as a fraction of the photo (where the shockwaves start).
  static const _mouth = Offset(.63, .46);

  @override
  void paint(Canvas canvas, Size size) {
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    // Full size: 82% of the screen's height, a little wider than a phone,
    // so he spills past the edges.
    final k = size.height * .82 / ih;
    final target = Offset(size.width / 2, size.height * .47);
    final from = origin ?? Offset(size.width / 2, size.height - 150);

    if (still) {
      // Reduced motion: fade in, hold, fade out. No movement.
      final fade = s < .3 ? s / .3 : (s > 2.6 ? (3 - s) / .4 : 1.0);
      _drawWhole(canvas, iw, ih, target, k, 0, Paint()..color = Colors.white.withValues(alpha: fade.clamp(0, 1)));
      return;
    }

    // 1. The charge: position eases out (he covers ground fast), size eases
    //    in (perspective: the closer, the faster he grows), blurred by speed.
    if (s < _Timeline.land) {
      final p = s / _Timeline.land;
      final center = Offset.lerp(from, target, Curves.easeOutCubic.transform(p))!;
      final scale = k * (.10 + .90 * Curves.easeInCubic.transform(p));
      final blur = 7 * (1 - p);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: (s / .12).clamp(0, 1))
        ..imageFilter = blur > .3 ? ui.ImageFilter.blur(sigmaX: blur * .4, sigmaY: blur) : null;
      _drawWhole(canvas, iw, ih, center, scale, 0, paint);
      return;
    }

    // 2. The roar: landing bump, then a shaking push towards the viewer.
    final roar = _roarAmount();
    final bump = s < .72 ? .07 * sin(pi * (s - _Timeline.land) / .22) : 0.0;
    final shake = Offset(sin(s * 53), cos(s * 47)) * 6 * roar;
    final tilt = .012 * sin(s * 31) * roar;
    final scale = k * (1 + bump + .05 * roar);
    final center = target + shake;

    _shade(canvas, size, roar);
    _shockwaves(canvas, size, center, iw, ih, scale);

    if (s < _Timeline.dissolve) {
      _drawWhole(canvas, iw, ih, center, scale, tilt, Paint()..filterQuality = FilterQuality.medium);
    } else {
      _drawDust(canvas, size, iw, ih, center, scale);
    }
  }

  /// 0 – 1: how hard he's roaring right now.
  double _roarAmount() {
    if (s < _Timeline.land) return 0;
    if (s < .62) return (s - _Timeline.land) / .12;
    if (s < 1.85) return .78 + .22 * sin(s * 19).abs();
    if (s < _Timeline.dissolve + .1) return .78 * (1 - (s - 1.85) / .35).clamp(0, 1);
    return 0;
  }

  void _drawWhole(Canvas canvas, double iw, double ih, Offset center, double scale, double tilt, Paint paint) {
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(tilt)
      ..scale(scale)
      ..drawImage(image, Offset(-iw / 2, -ih / 2), paint..filterQuality = FilterQuality.medium)
      ..restore();
  }

  /// A dark vignette that deepens with the roar, so he stands out.
  void _shade(Canvas canvas, Size size, double roar) {
    final fadeOut = s > _Timeline.dissolve ? (1 - (s - _Timeline.dissolve) / .9).clamp(0.0, 1.0) : 1.0;
    final strength = (.18 + .22 * roar) * fadeOut;
    if (strength <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: strength),
          ],
          stops: const [.45, 1],
        ).createShader(Offset.zero & size),
    );
  }

  /// Rings of air pushed out of his mouth.
  void _shockwaves(Canvas canvas, Size size, Offset center, double iw, double ih, double scale) {
    final mouth = center + Offset((_mouth.dx - .5) * iw * scale, (_mouth.dy - .5) * ih * scale);
    for (final start in const [.55, .95, 1.35]) {
      final p = (s - start) / .9;
      if (p <= 0 || p >= 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      canvas.drawCircle(
        mouth,
        size.width * (.08 + 1.1 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 * (1 - p) + 1
          ..color = const Color(0xFFFFE7C2).withValues(alpha: .38 * (1 - p))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  /// 3. The photo cut into a grid; a wave sweeps across it from the left and
  /// each fragment drifts up and away on the wind, spinning and fading.
  void _drawDust(Canvas canvas, Size size, double iw, double ih, Offset center, double scale) {
    const cols = _Dust._cols, rows = _Dust._rows;
    final tw = iw / cols, th = ih / rows;
    final t = (s - _Timeline.dissolve) / (_Timeline.end - _Timeline.dissolve);
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final seed = dust.seeds[r * cols + c];
        final delay = .5 * (c / cols * .65 + seed[0] * .35);
        final p = ((t - delay) / .5).clamp(0.0, 1.0);
        if (p >= 1) continue;
        final drift = Curves.easeIn.transform(p);
        // Wind to the upper right, in screen points, then into photo pixels.
        final dx = (.25 + .45 * seed[1]) * size.width * drift + 12 * sin(p * 9 + seed[2] * 6);
        final dy = -(.08 + .30 * seed[2]) * size.height * drift;
        final local = Offset((c + .5) * tw - iw / 2, (r + .5) * th - ih / 2);
        final at = center + local * scale + Offset(dx, dy);
        transforms.add(
          RSTransform.fromComponents(
            rotation: (seed[1] * 2 - 1) * 1.4 * p,
            scale: scale * (1.04 - .7 * p), // 1.04 hides seams between grains
            anchorX: tw / 2,
            anchorY: th / 2,
            translateX: at.dx,
            translateY: at.dy,
          ),
        );
        rects.add(Rect.fromLTWH(c * tw, r * th, tw, th));
        colors.add(Colors.white.withValues(alpha: 1 - drift));
      }
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(
      image,
      transforms,
      rects,
      colors,
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_LionPainter old) => old.s != s || old.origin != origin || old.still != still;
}
