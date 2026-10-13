import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import 'trip_list_screen.dart';

enum _Step { phone, otp, name }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  String? _mockOtp;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a phone number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final otp = await ApiClient.instance.requestOtp(phone);
      setState(() {
        _mockOtp = otp;
        _step = _Step.otp;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode({String? name}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.verifyOtp(
        _phone.text.trim(),
        _code.text.trim(),
        name: name,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TripListScreen()),
      );
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('name is required')) {
        setState(() => _step = _Step.name);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 40, 26, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TRIPSPLIT',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                switch (_step) {
                  _Step.phone => 'Log in to your trips',
                  _Step.otp => 'Enter the code',
                  _Step.name => 'What should we call you?',
                },
                style: const TextStyle(
                  color: ink,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(child: _stepBody()),
              ),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _primaryAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          switch (_step) {
                            _Step.phone => 'Send code',
                            _Step.otp => 'Verify',
                            _Step.name => 'Continue',
                          },
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _primaryAction() {
    switch (_step) {
      case _Step.phone:
        _sendCode();
      case _Step.otp:
        _verifyCode();
      case _Step.name:
        if (_name.text.trim().isEmpty) {
          setState(() => _error = 'Enter your name.');
          return;
        }
        _verifyCode(name: _name.text.trim());
    }
  }

  Widget _stepBody() {
    switch (_step) {
      case _Step.phone:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fieldLabel('PHONE NUMBER'),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: appInputDecoration(
                '98765 43210',
                Icons.phone_rounded,
              ),
            ),
          ],
        );
      case _Step.otp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_mockOtp != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2E8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: teal, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No SMS provider yet, so here\'s your code: $_mockOtp',
                        style: const TextStyle(
                          color: ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            fieldLabel('6-DIGIT CODE'),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: appInputDecoration('••••••', Icons.lock_outline_rounded),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = _Step.phone),
              child: const Text(
                'Use a different number',
                style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      case _Step.name:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            fieldLabel('YOUR NAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: appInputDecoration('e.g. Aarav', Icons.person_outline_rounded),
            ),
          ],
        );
    }
  }
}
