import 'package:flutter/material.dart';

import '../app_fonts.dart';
import '../theme.dart';
import '../widgets.dart';

/// Picks the app's typeface (applied everywhere at once) and bold text.
/// Fonts not on the phone yet download when picked; those that are show
/// their name in their own face.
class FontScreen extends StatelessWidget {
  const FontScreen({super.key});

  Future<void> _pick(BuildContext context, String family) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppFonts.instance.select(family);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('HttpException: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppFonts.instance,
    builder: (context, _) {
      final fonts = AppFonts.instance;
      return Scaffold(
        backgroundColor: paper,
        appBar: AppBar(
          actions: const [ThemeToggle()],
          backgroundColor: paper,
          surfaceTintColor: paper,
          title: const Text('App Font', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
          children: [
            _preview(fonts.family),
            const SizedBox(height: 12),
            Container(
              decoration: cardDecoration(),
              child: Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  value: fonts.bold,
                  onChanged: fonts.setBold,
                  activeThumbColor: Colors.white,
                  activeTrackColor: accent,
                  secondary: Icon(Icons.format_bold_rounded, color: accent),
                  title: Text(
                    'Bold Text',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Every Word In Bold, In Any Font', style: TextStyle(color: muted, fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Apple’s San Francisco and New York are licensed only for Apple devices, so Inter and Source Serif, '
                'their closest open matches, stand in for them.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.4),
              ),
            ),
            for (final kind in FontKind.values) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: kind.title,
                        style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '  ·  ${kind.subtitle}',
                        style: TextStyle(color: muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
              groupedCard([for (final font in appFonts.where((f) => f.kind == kind)) _row(context, font, fonts)]),
            ],
          ],
        ),
      );
    },
  );

  Widget _preview(String family) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(gradient: brandGradient, borderRadius: BorderRadius.circular(22)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          family,
          style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          '₹48,250',
          style: TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Dinner At The Riverfront · Split 4 Ways',
          style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );

  Widget _row(BuildContext context, AppFont font, AppFonts fonts) {
    final selected = fonts.family == font.family;
    final busy = fonts.downloading == font.family;
    final onPhone = fonts.downloaded.contains(font.family);
    return InkWell(
      onTap: busy || fonts.downloading != null ? null : () => _pick(context, font.family),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    font.family,
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      // Shown in its own face once it's on the phone.
                      fontFamily: onPhone ? font.family : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(font.note, style: TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (busy)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: fonts.progress > 0 ? fonts.progress : null,
                  strokeWidth: 2.4,
                  color: accent,
                ),
              )
            else if (selected)
              Icon(Icons.check_circle_rounded, color: accent, size: 22)
            else if (!onPhone)
              Icon(Icons.download_rounded, color: muted, size: 20),
          ],
        ),
      ),
    );
  }
}
