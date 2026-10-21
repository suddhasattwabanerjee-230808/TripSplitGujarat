import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_shell.dart';

/// Shown once after Google sign-in: the name tripmates will see everywhere.
/// Photo and email stay as Google has them.
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _user = ApiClient.instance.currentUser;
  // Starts as the Google first name, the most likely pick.
  late final _name = TextEditingController(text: (_user?.name ?? '').trim().split(RegExp(r'\s+')).first);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pick a name your tripmates will recognise.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.updateName(name);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final googleName = user?.name ?? '';
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(26, 40, 26, 24 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user != null) MemberAvatar(id: user.id, name: googleName, photoUrl: user.photoUrl, size: 76, ring: 3),
                  const Spacer(),
                  const ThemeToggle(),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                'What should your\ntripmates call you?',
                style: TextStyle(color: ink, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.1),
              ),
              const SizedBox(height: 10),
              Text(
                'This name appears on your trips, expenses and balances, instead of your Google name.',
                style: TextStyle(color: muted, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 26),
              fieldLabel('NICKNAME'),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 24,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _continue(),
                decoration: appInputDecoration('e.g. Bittu', Icons.badge_outlined),
              ),
              if (user?.email != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Photo and email from Google · ${user!.email}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: TextStyle(color: negative, fontSize: 12.5)),
                ),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _busy ? null : _continue,
                  style: primaryButton(radius: 16),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
                        )
                      : const Text('Continue', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('You can change it any time in Profile.', style: TextStyle(color: muted, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
