import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app_fonts.dart';
import '../expense_notifier.dart';
import '../theme.dart';
import '../update_service.dart';
import '../upi_alerts.dart';
import '../widgets.dart';
import 'font_screen.dart';
import 'update_dialog.dart';

/// The app's own settings, opened from the profile: notifications, the
/// font, bold text and text size, and updates.
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  static const _upiSettings = MethodChannel('tripsplit/upi_settings');

  bool _notificationsOn = true;
  final _updates = Updates.instance;
  final _upi = UpiAlerts.instance;
  final _fonts = AppFonts.instance;
  PackageInfo? _packageInfo;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _updates.addListener(_changed);
    _upi.addListener(_changed);
    _fonts.addListener(_changed);
    _upi.refresh();
    ExpenseNotifier.enabled().then((on) {
      if (mounted) setState(() => _notificationsOn = on);
    });
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  void dispose() {
    _updates.removeListener(_changed);
    _upi.removeListener(_changed);
    _fonts.removeListener(_changed);
    super.dispose();
  }

  /// The master switch: off silences expense alerts, settle-up reminders
  /// and UPI payment alerts alike.
  Future<void> _setNotifications(bool on) async {
    setState(() => _notificationsOn = on);
    await ExpenseNotifier.setEnabled(on);
    try {
      await _upiSettings.invokeMethod<void>('setAllEnabled', on);
    } on Exception {
      // The UPI receiver keeps its own switch.
    }
    await _upi.refresh();
  }

  Widget _switch(bool value, ValueChanged<bool>? onChanged) => Switch(
    value: value,
    onChanged: onChanged,
    activeThumbColor: Colors.white,
    activeTrackColor: accent,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      actions: const [ThemeToggle()],
      backgroundColor: paper,
      surfaceTintColor: paper,
      title: const Text('App Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    body: ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        _sectionLabel('NOTIFICATIONS'),
        _card([
          _row(
            icon: _notificationsOn ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            label: 'All Notifications',
            value: _notificationsOn ? 'Expenses, Reminders And UPI Alerts' : 'Off: TripSplit Stays Quiet',
            trailing: _switch(_notificationsOn, _setNotifications),
          ),
          _row(
            icon: _upi.on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            label: 'UPI Payment Alerts',
            value: !_upi.canSpot
                ? 'Needs Access To Spot Payments — Switch On'
                : _upi.enabled
                ? 'On For Every UPI Payment'
                : 'Off',
            trailing: _switch(_notificationsOn && _upi.on, _notificationsOn ? (v) => _upi.set(context, v) : null),
          ),
          // Spotted but not shown: Android is blocking TripSplit's notifications.
          if (_notificationsOn && _upi.on && _upi.blocked != null)
            _row(
              icon: Icons.warning_amber_rounded,
              label: 'Android Is Hiding UPI Alerts',
              value: '${_upi.blocked!.replaceFirst('Not Shown — ', '')} — Tap To Allow',
              trailing: Icon(Icons.chevron_right_rounded, color: muted),
              onTap: _upi.openAlertSettings,
            ),
          // Where payments are spotted: any one is enough.
          _row(
            icon: Icons.verified_outlined,
            label: 'From GPay & PhonePe Screens',
            value: _upi.screensOn
                ? 'Allowed — Spots The “Payment Successful” Screen'
                : 'Not Allowed — Tap To Allow (Works Without SMS)',
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () => _upi.askForScreens(context),
          ),
          _row(
            icon: Icons.sms_outlined,
            label: 'From Bank SMS',
            value: !_upi.smsOn
                ? 'Off — Bank SMS Isn’t Read'
                : _upi.smsGranted
                ? 'On — Reads Your Bank’s UPI SMS'
                : 'Needs SMS Access — Switch On',
            trailing: _switch(_upi.smsUsed, (v) => _upi.setSms(context, v)),
          ),
          _row(
            icon: Icons.account_balance_wallet_outlined,
            label: 'From GPay & PhonePe Notifications',
            value: _upi.listenerOn ? 'Allowed — For Banks That Send No SMS' : 'Not Allowed — Tap To Allow',
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () => _upi.askForAppNotifications(context),
          ),
          _row(
            icon: Icons.history_rounded,
            label: 'Last Payment Spotted',
            value: _upi.lastSummary ?? 'None Yet',
          ),
          _row(
            icon: Icons.notification_add_outlined,
            label: 'Send Test Alert',
            value: 'Shows A Sample ₹1 Alert Right Now',
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () => _upi.sendTest(context),
          ),
        ]),
        const SizedBox(height: 22),
        _sectionLabel('TEXT'),
        _card([
          _row(
            icon: Icons.text_fields_rounded,
            label: 'App Font',
            value: _fonts.family,
            trailing: Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () {
              _fonts.registerAll();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FontScreen()));
            },
          ),
          _row(
            icon: Icons.format_bold_rounded,
            label: 'Bold Text',
            value: _fonts.bold ? 'Every Word In Bold' : 'Off',
            trailing: _switch(_fonts.bold, _fonts.setBold),
          ),
          _textSize(),
        ]),
        const SizedBox(height: 22),
        _sectionLabel('UPDATES'),
        _card([
          _row(
            icon: Icons.update_rounded,
            label: 'Check For Updates At Launch',
            value: _updates.atLaunch ? 'Tells You When A New Version Is Out' : 'Off',
            trailing: _switch(_updates.atLaunch, _updates.setAtLaunch),
          ),
          _row(
            icon: Icons.system_update_outlined,
            label: _updates.available ? 'Update To ${_updates.latest!.versionName}' : 'Check For Updates',
            value: _packageInfo == null
                ? '…'
                : 'This Phone Has v${_packageInfo!.version} · Build ${_packageInfo!.buildNumber}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_updates.available)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                Icon(Icons.chevron_right_rounded, color: muted),
              ],
            ),
            onTap: () => showUpdateSheet(context),
          ),
        ]),
      ],
    ),
  );

  /// Text size: a slider from smaller to larger, with the text right above
  /// it changing as it moves (and the whole app with it).
  Widget _textSize() {
    final scale = _fonts.scale;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_size_rounded, size: 20, color: muted),
              const SizedBox(width: 22),
              Expanded(
                child: Text('Text Size', style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              Text(
                '${(scale * 100).round()}%',
                style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              if (scale != 1) ...[
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => _fonts.setScale(1),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: accent),
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, top: 6),
            child: Text(
              'Dinner At The Riverfront · ₹1,240',
              style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text('A', style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: Slider(
                  value: scale,
                  min: AppFonts.minScale,
                  max: AppFonts.maxScale,
                  divisions: ((AppFonts.maxScale - AppFonts.minScale) / .05).round(),
                  activeColor: accent,
                  inactiveColor: line,
                  label: '${(scale * 100).round()}%',
                  onChanged: _fonts.setScale,
                ),
              ),
              Text('A', style: TextStyle(color: muted, fontSize: 20, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    child: Text(
      text,
      style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
    ),
  );

  Widget _card(List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: cardDecoration(),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 58, color: line),
            rows[i],
          ],
        ],
      ),
    ),
  );

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    ),
  );
}
