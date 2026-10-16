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
  String? _error;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await UpdateService.downloadAndInstall(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'Could not install the update. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _progress != null;
    return Dialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
              Text(
                widget.info.notes,
                style: const TextStyle(color: ink, fontSize: 13, height: 1.4),
              ),
            ],
            if (downloading) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress! > 0 ? _progress : null,
                  color: teal,
                  backgroundColor: const Color(0xFFE4E8DF),
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
                  child: Text(downloading ? 'Downloading…' : 'Update now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
