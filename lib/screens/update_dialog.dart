import 'package:flutter/material.dart';

import '../theme.dart';
import '../update_service.dart';
import '../widgets.dart';

/// The update sheet: what's new in the latest version and the button to get
/// it, with the download's progress in place. Checks again as it opens, so it
/// also answers "is there anything new?".
Future<void> showUpdateSheet(BuildContext context) {
  final updates = Updates.instance;
  if (!updates.checking && updates.progress == null) updates.check();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _UpdateSheet(),
  );
}

/// "TripSplit 1.12.0 Is Out", once per launch, as a bar with an Update button.
void showUpdateBanner(ScaffoldMessengerState messenger, BuildContext Function() sheetContext) {
  final latest = Updates.instance.latest;
  if (latest == null) return;
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: accentGlow, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text('TripSplit ${latest.versionName} Is Out')),
        ],
      ),
      action: SnackBarAction(label: 'Update', textColor: accentGlow, onPressed: () => showUpdateSheet(sheetContext())),
    ),
  );
}

/// Release notes come straight from the CHANGELOG section, hard-wrapped and
/// with Markdown markers. Unwrap the wrapped lines, drop the "###"/"-"
/// markers and bold stars, and bullet the list so it reads cleanly.
String cleanReleaseNotes(String raw) {
  final out = <String>[];
  for (final line in raw.trim().split('\n')) {
    if (line.trim().isEmpty) {
      out.add('');
    } else if (line.startsWith('  ') && out.isNotEmpty && out.last.isNotEmpty) {
      // Continuation of the previous wrapped bullet/line — join it on.
      out[out.length - 1] = '${out.last} ${line.trim()}';
    } else {
      var l = line.trimLeft().replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      if (l.startsWith('- ')) l = '•  ${l.substring(2)}';
      out.add(l);
    }
  }
  return out.join('\n').replaceAll('**', '');
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet();

  String _mb(int bytes) => '${(bytes / 1e6).toStringAsFixed(bytes < 1e7 ? 1 : 0)} MB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Updates.instance,
    builder: (context, _) {
      final u = Updates.instance;
      final latest = u.latest;
      final progress = u.progress;
      return Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: SheetHandle()),
                const SizedBox(height: 18),
                Text(
                  latest != null ? 'TripSplit ${latest.versionName} Is Out' : 'App Updates',
                  style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.4),
                ),
                const SizedBox(height: 4),
                Text(
                  u.current.isEmpty ? '' : 'This Phone Has ${u.current}',
                  style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                if (u.checking && latest == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator(color: accent, strokeWidth: 3)),
                  )
                else if (latest == null) ...[
                  _message(
                    u.checkFailed ? Icons.cloud_off_rounded : Icons.verified_rounded,
                    u.checkFailed ? 'Couldn’t check for updates. Is the phone online?' : 'You have the newest version.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: u.check,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check Again'),
                    style: secondaryButton(),
                  ),
                ] else ...[
                  if (latest.notes.trim().isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: cardDecoration(radius: 16),
                        child: SingleChildScrollView(
                          child: Text(
                            cleanReleaseNotes(latest.notes),
                            style: TextStyle(color: ink, fontSize: 13, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (progress != null) ...[
                    // One bar for download + install; animated so the jumps
                    // between chunks and the install's creep read as motion.
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: value > 0 ? value : null,
                              minHeight: 6,
                              color: accent,
                              backgroundColor: line,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            u.installing
                                ? 'Installing… The App Will Reopen'
                                : 'Downloading… ${(value * 100).floor()}%${u.apkBytes == null ? '' : ' Of ${_mb(u.apkBytes!)}'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: u.install,
                      icon: const Icon(Icons.system_update_rounded, size: 19),
                      label: Text('Update To ${latest.versionName}'),
                      style: primaryButton(),
                    ),
                  if (u.error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Couldn’t Update: ${u.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: negative, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Android may ask you to confirm the install. Your trips and settings stay as they are.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _message(IconData icon, String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: cardDecoration(radius: 16),
    child: Row(
      children: [
        Icon(icon, color: accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: ink, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
