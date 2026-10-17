import 'package:flutter/material.dart';

import '../theme.dart';
import '../update_service.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  bool _installing = false;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _installing = false;
      _error = null;
    });
    try {
      // Downloads, installs and relaunches in one go; on success this app
      // instance is replaced, so we only get past this line on failure.
      await UpdateService.downloadAndInstall(widget.info, (p, installing) {
        if (mounted) {
          setState(() {
            _progress = p;
            _installing = installing;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Could not update. $e';
        });
      }
    }
  }

  /// Release notes come straight from the CHANGELOG section, hard-wrapped and
  /// with Markdown markers. Unwrap the wrapped lines, drop the "###"/"-"
  /// markers, and bullet the list so it reads cleanly in a narrow dialog.
  String _cleanNotes(String raw) {
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
    return out.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return Dialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        // Cap the dialog so long release notes never push the buttons off
        // the screen — the notes scroll inside, the buttons stay put.
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.system_update_rounded, color: teal),
                SizedBox(width: 10),
                Text(
                  'Update available',
                  style: TextStyle(
                    color: ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Version ${widget.info.versionName} is ready to install.',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            if (widget.info.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    _cleanNotes(widget.info.notes),
                    style: const TextStyle(color: ink, fontSize: 13, height: 1.4),
                  ),
                ),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 18),
              // One bar for download + install; animated so the jumps between
              // chunks and the install phase's creep read as smooth motion.
              TweenAnimationBuilder<double>(
                tween: Tween(end: _progress!),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (context, value, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: value > 0 ? value : null,
                        minHeight: 8,
                        color: teal,
                        backgroundColor: const Color(0xFFE4E8DF),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            _installing ? 'Installing… the app will reopen' : 'Downloading…',
                            key: ValueKey(_installing),
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(value * 100).floor()}%',
                          style: const TextStyle(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFB3261E), fontSize: 12)),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!downloading)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later', style: TextStyle(color: muted)),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: downloading ? null : _update,
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(downloading ? 'Updating…' : 'Update now'),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}
