import 'dart:math';

import 'package:flutter/material.dart';

/// A cartoon lion head that pops in and roars once (mane puffs up, head
/// shakes, eyes squint, jaw drops, sound waves ripple out), timed to the
/// 2.3 s roar sound played alongside it on the UPI pop-up's "Expense added".
class LionRoar extends StatefulWidget {
  const LionRoar({super.key, this.size = 150});

  final double size;

  /// How long the roar plays; the sound is the same length.
  static const duration = Duration(milliseconds: 2600);

  @override
  State<LionRoar> createState() => _LionRoarState();
}

class _LionRoarState extends State<LionRoar> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: LionRoar.duration)..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With animations turned off, show the lion mid-roar, standing still.
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'A lion roaring',
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, __) => CustomPaint(
            painter: _LionPainter(still ? _LionPose.still : _LionPose.at(_controller.value * 2.6)),
          ),
        ),
      ),
    );
  }
}

/// Everything that moves, worked out from the time [s] in seconds.
class _LionPose {
  const _LionPose({required this.entrance, required this.roar, required this.shake, required this.time});

  static const still = _LionPose(entrance: 1, roar: .7, shake: 0, time: 0);

  factory _LionPose.at(double s) {
    final entrance = Curves.easeOutBack.transform((s / .45).clamp(0.0, 1.0));
    final double roar;
    if (s < .15) {
      roar = 0;
    } else if (s < .38) {
      roar = Curves.easeOut.transform((s - .15) / .23);
    } else if (s < 1.9) {
      roar = .82 + .18 * sin(s * 23).abs();
    } else if (s < 2.3) {
      roar = .82 * (1 - Curves.easeIn.transform((s - 1.9) / .4));
    } else {
      roar = 0;
    }
    return _LionPose(entrance: entrance, roar: roar, shake: roar * .06 * sin(s * 38), time: s);
  }

  /// 0–1 pop-in scale.
  final double entrance;

  /// 0 (mouth shut) – 1 (full roar).
  final double roar;

  /// Head tilt in radians.
  final double shake;
  final double time;
}

class _LionPainter extends CustomPainter {
  _LionPainter(this.pose);

  final _LionPose pose;

  static const _maneDark = Color(0xFFC2611A);
  static const _maneLight = Color(0xFFE08A1E);
  static const _fur = Color(0xFFF5C04F);
  static const _earInner = Color(0xFFE8916B);
  static const _muzzle = Color(0xFFFCE6B8);
  static const _darkBrown = Color(0xFF4A2A18);
  static const _mouth = Color(0xFF6B1A1A);
  static const _tongue = Color(0xFFE0707A);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width;
    final center = Offset(u / 2, u * .53);
    final roar = pose.roar;

    _soundWaves(canvas, center, u);

    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(pose.shake)
      // .86 leaves a margin around the mane for the sound waves.
      ..scale(.86 * pose.entrance * (1 + .03 * roar));

    // Mane: a dark disc ringed by two layers of scallops that puff up.
    final puff = 1 + .07 * roar;
    final twist = .04 * sin(pose.time * 6) * roar;
    final fill = Paint();
    canvas.drawCircle(Offset.zero, .34 * u * puff, fill..color = _maneDark);
    const tufts = 14;
    for (var i = 0; i < tufts; i++) {
      final a = i * 2 * pi / tufts + twist;
      canvas.drawCircle(Offset.fromDirection(a, .33 * u * puff), .115 * u, fill..color = _maneDark);
    }
    for (var i = 0; i < tufts; i++) {
      final a = (i + .5) * 2 * pi / tufts - twist;
      canvas.drawCircle(Offset.fromDirection(a, .27 * u * puff), .10 * u, fill..color = _maneLight);
    }

    // Ears.
    for (final side in [-1.0, 1.0]) {
      final ear = Offset(side * .17 * u, -.20 * u);
      canvas
        ..drawCircle(ear, .07 * u, fill..color = _fur)
        ..drawCircle(ear, .038 * u, fill..color = _earInner);
    }

    // Face.
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: .50 * u, height: .52 * u), fill..color = _fur);

    // Brows: their inner ends drop as he roars.
    final brow = Paint()
      ..color = _darkBrown
      ..strokeWidth = .022 * u
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(side * .135 * u, -.095 * u),
        Offset(side * .05 * u, (-.085 + .04 * roar) * u),
        brow,
      );
    }

    // Eyes squint shut into slits mid-roar.
    for (final side in [-1.0, 1.0]) {
      final eye = Offset(side * .09 * u, -.035 * u);
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: .05 * u, height: max(.05 * (1 - .8 * roar), .009) * u),
        fill..color = _darkBrown,
      );
      if (roar < .3) canvas.drawCircle(eye + Offset(.008 * u, -.009 * u), .008 * u, fill..color = Colors.white);
    }

    // Muzzle and whisker dots.
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(Offset(side * .058 * u, .075 * u), .072 * u, fill..color = _muzzle);
      for (final dot in const [Offset(.04, .09), Offset(.075, .078), Offset(.07, .11)]) {
        canvas.drawCircle(Offset(side * dot.dx * u, dot.dy * u), .007 * u, fill..color = const Color(0xFFB0805A));
      }
    }

    // Mouth: a smile when shut; opens into a jaw with fangs and a tongue.
    if (roar < .04) {
      final smile = Path()
        ..moveTo(-.05 * u, .125 * u)
        ..quadraticBezierTo(-.025 * u, .145 * u, 0, .118 * u)
        ..quadraticBezierTo(.025 * u, .145 * u, .05 * u, .125 * u);
      canvas.drawPath(
        smile,
        Paint()
          ..color = _darkBrown
          ..style = PaintingStyle.stroke
          ..strokeWidth = .016 * u
          ..strokeCap = StrokeCap.round,
      );
    } else {
      final top = .112 * u;
      final height = (.02 + .16 * roar) * u;
      final mouth = Rect.fromLTWH(-(.06 + .02 * roar) * u, top, (.12 + .04 * roar) * u, height);
      final mouthPath = Path()..addOval(mouth);
      canvas
        ..drawPath(mouthPath, fill..color = _mouth)
        ..save()
        ..clipPath(mouthPath)
        ..drawOval(
          Rect.fromCenter(center: Offset(0, top + height * .82), width: .09 * u, height: height * .5),
          fill..color = _tongue,
        )
        ..restore();
      for (final side in [-1.0, 1.0]) {
        final x = side * .032 * u;
        canvas.drawPath(
          Path()
            ..moveTo(x - .015 * u, top + .006 * u)
            ..lineTo(x + .015 * u, top + .006 * u)
            ..lineTo(x, top + (.012 + .045 * roar) * u)
            ..close(),
          fill..color = Colors.white,
        );
      }
    }

    // Nose, on top of everything.
    final nose = Path()
      ..moveTo(-.045 * u, .03 * u)
      ..lineTo(.045 * u, .03 * u)
      ..lineTo(0, .085 * u)
      ..close();
    canvas
      ..drawPath(
        nose,
        Paint()
          ..color = _darkBrown
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = .02 * u
          ..style = PaintingStyle.fill,
      )
      ..drawPath(
        nose,
        Paint()
          ..color = _darkBrown
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = .02 * u
          ..style = PaintingStyle.stroke,
      )
      ..restore();
  }

  /// Three arcs on each side, rippling outwards while he roars.
  void _soundWaves(Canvas canvas, Offset center, double u) {
    if (pose.roar < .05) return;
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .03 * u
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 3; k++) {
      final p = (pose.time * 1.6 + k / 3) % 1;
      final rect = Rect.fromCircle(center: center, radius: (.41 + .08 * p) * u);
      wave.color = _maneLight.withValues(alpha: (1 - p) * pose.roar);
      canvas
        ..drawArc(rect, -.45, .9, false, wave)
        ..drawArc(rect, pi - .45, .9, false, wave);
    }
  }

  @override
  bool shouldRepaint(_LionPainter old) => true;
}
