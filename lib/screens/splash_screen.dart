import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ajrakh.dart';
import '../theme.dart';

/// Cinematic brand intro, in the spirit of Netflix's "ta-dum", on an ajrakh
/// print: the logo is unveiled by a feathered diagonal wipe, the wordmark
/// settles beneath it, a light sweep crosses the logo, then the camera dives
/// into the logo's centre, which bursts into streaks of light.
/// Tapping anywhere skips straight to [onDone].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  // Shared across replays so returning to the app starts the intro instantly.
  static Future<ui.Image?>? _logoFuture;
  static ui.Image? _strandSprite;
  static ui.Image? _logoShadow;

  late final AnimationController _controller;
  final _strands = _Strand.generate(64);
  ui.Image? _logo;
  bool _done = false;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _strandSprite ??= _buildStrandSprite();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))
      ..addListener(_onTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
    (_logoFuture ??= _loadLogo()).then((image) {
      if (!mounted || _done) return;
      if (image != null) _logoShadow ??= _buildShadow(image);
      setState(() => _logo = image);
      _controller.forward();
    });
  }

  static Future<ui.Image?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/splash_logo.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null; // the rest of the intro still plays
    }
  }

  /// The logo's silhouette, blurred: a soft shadow that seats the sticker
  /// on the print. Rendered once, at [_shadowPad] around the logo.
  static ui.Image _buildShadow(ui.Image logo) {
    final pad = logo.width * _shadowPad;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: pad / 3, sigmaY: pad / 3));
    canvas.drawImage(
      logo,
      Offset(pad, pad),
      Paint()..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn),
    );
    canvas.restore();
    return recorder.endRecording().toImageSync((logo.width + 2 * pad).round(), (logo.height + 2 * pad).round());
  }

  /// One soft, blurred white streak, rendered once and tinted per strand at draw
  /// time — far cheaper than blurring 64 shapes on every frame.
  static ui.Image _buildStrandSprite() {
    const width = 48.0;
    const height = 256.0;
    final recorder = ui.PictureRecorder();
    const bar = Rect.fromLTWH(width * _Strand.spriteBarLeft, height * _Strand.spriteBarTop,
        width * _Strand.spriteBarWidth, height * _Strand.spriteBarHeight);
    Canvas(recorder).drawRect(
      bar,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(bar)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    return recorder.endRecording().toImageSync(width.toInt(), height.toInt());
  }

  void _onTick() {
    if (!_landed && _controller.value >= _T.land) {
      _landed = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: ajrakhBlack,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _controller.stop();
          _finish();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: ajrakhBlack, child: AjrakhBackground()),
            RepaintBoundary(
              child: CustomPaint(
                painter: _IntroPainter(_controller, _strands, _logo, _logoShadow, _strandSprite!),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Timeline, as fractions of the controller's run.
abstract final class _T {
  static const land = 0.28; // logo fully revealed
  static const zoomStart = 0.58;
  static const zoomEnd = 0.84;
}

/// The shadow image's margin around the logo, as a fraction of its width.
const _shadowPad = 0.08;

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

// Colours sampled from the logo artwork.
const _logoOrange = Color(0xFFF5831F);
const _logoBrown = Color(0xFFA84924);

class _Strand {
  const _Strand(this.x, this.width, this.length, this.delay, this.color);

  // Where the streak sits inside the sprite image, as fractions of its size.
  static const spriteBarLeft = 0.3;
  static const spriteBarWidth = 0.4;
  static const spriteBarTop = 0.04;
  static const spriteBarHeight = 0.92;

  /// Final horizontal position, -1 (left edge) .. 1 (right edge).
  final double x;

  /// Width as a fraction of screen width.
  final double width;

  /// Height as a fraction of screen height.
  final double length;

  /// Start offset within the strand phase.
  final double delay;
  final Color color;

  static List<_Strand> generate(int count) {
    final random = math.Random(11);
    const colors = [
      _logoOrange,
      _logoBrown,
      Colors.white,
      Color(0xFFFFB25C),
      Color(0xFFE1B764),
      _logoOrange,
      accentGlow,
    ];
    return List.generate(count, (_) {
      final x = random.nextDouble() * 2 - 1;
      return _Strand(
        x * x.abs() * 0.4 + x * 0.6, // denser near the centre, like a light burst
        0.004 + random.nextDouble() * 0.026,
        0.55 + random.nextDouble() * 0.45,
        random.nextDouble() * 0.4,
        colors[random.nextInt(colors.length)],
      );
    });
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.animation, this.strands, this.logo, this.shadow, this.strandSprite) : super(repaint: animation);

  final Animation<double> animation;
  final List<_Strand> strands;
  final ui.Image? logo;
  final ui.Image? shadow;
  final ui.Image strandSprite;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final s = math.min(size.width, size.height) * 0.30;
    final center = size.center(Offset.zero);

    final aspect = logo == null ? 610 / 653 : logo!.width / logo!.height;
    final logoH = s * 1.55;
    final logoW = logoH * aspect;
    final fontSize = s * 0.25;
    final gap = s * 0.26;
    final groupH = logoH + gap + fontSize * 1.25;
    final logoRect = Rect.fromLTWH(center.dx - logoW / 2, center.dy - groupH / 2, logoW, logoH);
    final focus = logoRect.center;

    _paintGlow(canvas, focus, s, t);
    _paintLogo(canvas, logoRect, focus, t);
    _paintWordmark(canvas, center, logoRect.bottom + gap, fontSize, t);
    _paintStrands(canvas, size, focus.dx, t);
    _paintBurst(canvas, size, focus, t);
  }

  void _paintGlow(Canvas canvas, Offset at, double s, double t) {
    final alpha = 0.28 * _seg(t, 0.05, 0.30) * (1 - _seg(t, 0.60, 0.74));
    if (alpha <= 0) return;
    final radius = s * 1.9;
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [_logoOrange.withValues(alpha: alpha), Colors.transparent],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  void _paintLogo(Canvas canvas, Rect rect, Offset focus, double t) {
    final image = logo;
    if (image == null) return;

    final intro = Curves.easeOutCubic.transform(_seg(t, 0.0, 0.10));
    final zoom = Curves.easeInCubic.transform(_seg(t, _T.zoomStart, _T.zoomEnd));
    final opacity = intro * (1 - Curves.easeIn.transform(_seg(t, 0.64, 0.73)));
    if (opacity <= 0) return;

    // Settle in from slightly small, then dive into the logo's centre.
    final scale = (0.94 + 0.06 * intro) * (1 + zoom * 9);
    canvas.save();
    canvas.translate(focus.dx, focus.dy);
    canvas.scale(scale);
    canvas.translate(-focus.dx, -focus.dy);

    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final reveal = Curves.easeInOutCubic.transform(_seg(t, 0.03, _T.land));

    // Its shadow, seating it on the print.
    void drawShadow(double alpha) {
      final shadow = this.shadow;
      if (shadow == null) return;
      final pad = rect.width * _shadowPad;
      canvas.drawImageRect(
        shadow,
        Rect.fromLTWH(0, 0, shadow.width.toDouble(), shadow.height.toDouble()),
        rect.inflate(pad).shift(Offset(0, rect.height * .03)),
        Paint()..color = Colors.white.withValues(alpha: .8 * alpha),
      );
    }

    void drawLogo(double alpha) => canvas.drawImageRect(
      image,
      src,
      rect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: alpha),
    );

    final sheen = _seg(t, 0.40, 0.60);
    final sheenActive = sheen > 0 && sheen < 1;

    // Offscreen layers only while the wipe or sweep needs one; the zoom draws direct.
    if (reveal >= 1 && !sheenActive) {
      drawShadow(opacity);
      drawLogo(opacity);
      canvas.restore();
      return;
    }

    // While the wipe runs the shadow is revealed with the logo; after it, the
    // shadow stays out of the layer so the sweep lights the logo only.
    if (reveal >= 1) drawShadow(opacity);
    final bounds = rect.inflate(rect.width * _shadowPad * 1.5);
    canvas.saveLayer(bounds, Paint()..color = Colors.white.withValues(alpha: opacity));
    if (reveal < 1) drawShadow(1);
    drawLogo(1);

    // Feathered diagonal wipe: the lion appears first, then the pattern panel.
    if (reveal < 1) {
      const feather = 0.22;
      final edge = -feather + (1 + 2 * feather) * reveal;
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(
            begin: const Alignment(-1, -0.5),
            end: const Alignment(1, 0.5),
            colors: [Colors.white, Colors.white.withValues(alpha: 0)],
            stops: [(edge - feather).clamp(0.0, 1.0), edge.clamp(0.0, 1.0)],
          ).createShader(bounds),
      );
    }

    // One light sweep across the logo, painted only onto the logo's own pixels.
    if (sheenActive) {
      final c = -0.2 + 1.4 * Curves.easeInOut.transform(sheen);
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.45),
              Colors.white.withValues(alpha: 0),
            ],
            stops: [
              (c - 0.12).clamp(0.0, 1.0),
              c.clamp(0.0, 1.0),
              (c + 0.12).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
      );
    }

    canvas.restore(); // saveLayer
    canvas.restore(); // transform
  }

  void _paintWordmark(Canvas canvas, Offset center, double top, double fontSize, double t) {
    final appear = Curves.easeOutCubic.transform(_seg(t, 0.30, 0.48));
    final opacity = appear * (1 - _seg(t, _T.zoomStart, 0.64));
    if (opacity <= 0) return;

    final spacing = fontSize * (0.7 - 0.42 * appear);
    final glow = fontSize * 0.55;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        style: TextStyle(fontFamily: 'Inter', fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: spacing),
        children: [
          // Ivory and saffron, as on the print and the logo, with a dark halo
          // so the letters sit clear of the pattern behind them.
          TextSpan(
            text: 'TRIP',
            style: TextStyle(
              color: ajrakhIvory.withValues(alpha: opacity),
              shadows: [
                Shadow(color: ajrakhBlack.withValues(alpha: 0.9 * opacity), blurRadius: glow),
                Shadow(color: ajrakhIvory.withValues(alpha: 0.18 * opacity), blurRadius: glow * 1.6),
              ],
            ),
          ),
          TextSpan(
            text: 'SPLIT',
            style: TextStyle(
              color: ajrakhSaffron.withValues(alpha: opacity),
              shadows: [
                Shadow(color: ajrakhBlack.withValues(alpha: 0.9 * opacity), blurRadius: glow),
                Shadow(color: logoOrange.withValues(alpha: 0.45 * opacity), blurRadius: glow * 1.6),
              ],
            ),
          ),
        ],
      ),
    )..layout();

    // letterSpacing also pads after the last glyph; drop it so the word is optically centred.
    final dx = center.dx - (painter.width - spacing) / 2;
    final dy = top + (1 - appear) * fontSize * 0.4;
    painter.paint(canvas, Offset(dx, dy));
    painter.dispose();
  }

  void _paintStrands(Canvas canvas, Size size, double originX, double t) {
    final phase = _seg(t, 0.62, 0.94);
    if (phase <= 0 || phase >= 1) return;
    final fade = 1 - _seg(t, 0.84, 0.95);
    final cy = size.height / 2;
    final src = Rect.fromLTWH(0, 0, strandSprite.width.toDouble(), strandSprite.height.toDouble());

    for (final strand in strands) {
      final local = ((phase - strand.delay) / 0.55).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final alpha = math.sin(math.pi * local) * fade;
      if (alpha <= 0.01) continue;

      final spread = Curves.easeOutCubic.transform(local);
      final width = size.width * strand.width * (0.4 + 1.6 * spread);
      final height = size.height * strand.length * (0.35 + 0.65 * spread);
      // The sprite's streak only fills part of the image, so scale the image up to match.
      final dst = Rect.fromCenter(
        center: Offset(originX + strand.x * size.width * 0.8 * spread, cy),
        width: width / _Strand.spriteBarWidth,
        height: height / _Strand.spriteBarHeight,
      );
      canvas.drawImageRect(
        strandSprite,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = ColorFilter.mode(strand.color.withValues(alpha: 0.9 * alpha), BlendMode.modulate),
      );
    }
  }

  void _paintBurst(Canvas canvas, Size size, Offset at, double t) {
    final burst = math.sin(math.pi * _seg(t, 0.66, 0.86));
    if (burst <= 0) return;
    final radius = size.longestSide * 0.6;
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.3 * burst), Colors.transparent],
        ).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_IntroPainter oldDelegate) => oldDelegate.logo != logo || oldDelegate.shadow != shadow;
}
