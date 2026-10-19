import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../google_auth.dart';
import '../theme.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await GoogleAuth.signIn();
      await ApiClient.instance.signInWithGoogle(idToken);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    } on GoogleAuthException catch (e) {
      if (!e.canceled) setState(() => _error = e.message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Staggered fade + rise for the [index]th block of the screen.
  Widget _reveal(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(start + 0.5, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .12), end: Offset.zero).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _reveal(0, const _Emblem()),
                      const SizedBox(height: 30),
                      _reveal(
                        1,
                        const Text(
                          'Split trips,\nnot friendships.',
                          style: TextStyle(
                            color: ink,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.2,
                            height: 1.08,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _reveal(
                        2,
                        const Text(
                          'One shared ledger for everyone on the trip — who paid, who owes, and the fewest payments to settle up.',
                          style: TextStyle(color: muted, fontSize: 14, height: 1.45),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _reveal(
                        3,
                        const Column(
                          children: [
                            _Feature(
                              icon: Icons.groups_outlined,
                              color: accent,
                              title: 'Shared with your group',
                              subtitle: 'Join with an invite code; everyone sees the same expenses.',
                            ),
                            _Feature(
                              icon: Icons.bolt_outlined,
                              color: Color(0xFFE0A96D),
                              title: 'UPI payments, auto-added',
                              subtitle: 'Pay with any UPI app and add it to the trip in one tap.',
                            ),
                            _Feature(
                              icon: Icons.handshake_outlined,
                              color: Color(0xFF7FA8D1),
                              title: 'Settle up simply',
                              subtitle: 'Balances and suggested payments, worked out for you.',
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey(_error),
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFCE8EA),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline_rounded, size: 18, color: negative),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(color: ink, fontSize: 12.5, height: 1.35),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      _reveal(4, _GoogleButton(busy: _busy, onPressed: _continueWithGoogle)),
                      const SizedBox(height: 14),
                      _reveal(
                        5,
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 13, color: muted),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'No OTP. You stay signed in until you sign out.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lion emblem on a soft light halo.
class _Emblem extends StatelessWidget {
  const _Emblem();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: accentGlow.withValues(alpha: .55), blurRadius: 24, spreadRadius: 1),
            ],
          ),
          child: Image.asset('assets/splash_logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(width: 14),
        const Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.4),
            children: [
              TextSpan(text: 'TRIP', style: TextStyle(color: ink)),
              TextSpan(text: 'SPLIT', style: TextStyle(color: accent)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.color, required this.title, required this.subtitle});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: muted, fontSize: 12.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: softShadow(ink, .12),
        ),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            disabledBackgroundColor: Colors.white,
            foregroundColor: ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: line),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: busy
                ? const SizedBox(
                    key: ValueKey('busy'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
                  )
                : const Row(
                    key: ValueKey('idle'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GoogleLogo(size: 20),
                      SizedBox(width: 12),
                      Text(
                        'Continue with Google',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: .1),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The four-colour Google "G", drawn so no image asset is needed.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const CustomPaint(painter: _GoogleLogoPainter()));
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .2;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    double deg(double d) => d * math.pi / 180;
    // Angles run clockwise from 3 o'clock.
    canvas.drawArc(rect, deg(-40), deg(-100), false, paint..color = _red);
    canvas.drawArc(rect, deg(-140), deg(-80), false, paint..color = _yellow);
    canvas.drawArc(rect, deg(140), deg(-95), false, paint..color = _green);
    canvas.drawArc(rect, deg(45), deg(-45), false, paint..color = _blue);
    // The crossbar.
    canvas.drawRect(
      Rect.fromLTRB(size.width * .5, size.height * .5 - stroke / 2, rect.right + stroke / 2, size.height * .5 + stroke / 2),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter oldDelegate) => false;
}
