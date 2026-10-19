import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api_client.dart';
import '../google_auth.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../update_service.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'trips_ui.dart';
import 'update_dialog.dart';

const _owe = negative;
const _hairline = line;

/// The signed-in user's Google photo, or their initials on a member colour.
/// Wrapped in a [Hero] so it flies between the home header and the profile.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40, this.hero = true});
  final AppUser user;
  final double size;
  final bool hero;

  /// Google serves profile photos at any size; ask for one sharp at [size].
  String? get _photo {
    final url = user.photoUrl;
    if (url == null) return null;
    final px = (size * 3).round();
    return url.contains(RegExp(r'=s\d+-c$')) ? url.replaceFirst(RegExp(r'=s\d+-c$'), '=s$px-c') : url;
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      color: colorForId(user.id),
      child: Text(
        user.initials,
        style: TextStyle(color: Colors.white, fontSize: size * .38, fontWeight: FontWeight.w800),
      ),
    );
    final avatar = SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: _photo == null
            ? fallback
            : Image.network(
                _photo!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                  opacity: sync || frame != null ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: child,
                ),
              ),
      ),
    );
    return hero ? Hero(tag: 'profile-avatar', child: avatar) : avatar;
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// Shown as a tab in the home shell (no back button).
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  static const _upiSettings = MethodChannel('tripsplit/upi_settings');

  bool _upiDetection = true;
  bool _upiAlertsOn = true;
  AppUser? _user = ApiClient.instance.currentUser;
  PackageInfo? _packageInfo;
  bool _linking = false;

  int? get _tripCount => TripStore.instance.trips?.length;

  double? get _netBalance {
    if (TripStore.instance.trips == null) return null;
    final t = TripStore.instance.totals;
    return t.owed - t.owing;
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TripStore.instance.removeListener(_onStore);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Settings app, where SMS access may have just been allowed.
    if (state == AppLifecycleState.resumed) _checkUpiDetection();
  }

  Future<void> _checkUpiDetection() async {
    final granted = await Permission.sms.isGranted;
    bool on;
    try {
      on = await _upiSettings.invokeMethod<bool>('isEnabled') ?? true;
    } on Exception {
      on = true;
    }
    if (mounted) {
      setState(() {
        _upiDetection = granted;
        _upiAlertsOn = on;
      });
    }
  }

  /// The home screen's UPI alerts switch. Switching on without SMS access runs
  /// the set-up flow; the switch then reads on only once access is granted
  /// (re-checked on resume). Switching off keeps the permission, just silences
  /// the alerts in the native receiver.
  Future<void> _setUpiAlerts(bool on) async {
    setState(() => _upiAlertsOn = on);
    try {
      await _upiSettings.invokeMethod<void>('setEnabled', on);
    } on Exception {
      // Setting stays as it was; the switch re-syncs on the next check.
    }
    if (on && !_upiDetection) await _enableUpiDetection();
  }

  Future<void> _enableUpiDetection() async {
    final result = await [Permission.sms, Permission.notification].request();
    final sms = result[Permission.sms] ?? PermissionStatus.denied;
    // On a build installed from outside the Play Store, Play Protect treats SMS
    // as a restricted permission and auto-denies the request — the toggle in
    // Settings stays greyed out until the user turns on "Allow restricted
    // settings" first. A plain openAppSettings() drops them there with no clue
    // how to proceed, so when SMS didn't get granted we spell the steps out.
    if (!sms.isGranted && mounted) {
      await _showSmsHelpDialog();
    }
    await _checkUpiDetection();
  }

  Future<void> _showSmsHelpDialog() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Allow SMS access',
        style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: const Text(
        'Because TripSplit is installed outside the Play Store, Android keeps '
        'SMS access switched off and greys out the toggle. Turn it on by hand:\n\n'
        '1.  Tap “Open settings” below.\n'
        '2.  On the App info screen, tap ⋮ in the top-right corner.\n'
        '3.  Choose “Allow restricted settings”.\n'
        '4.  Open Permissions → SMS → Allow.\n\n'
        'Then come back here — the banner will disappear once it’s on.',
        style: TextStyle(color: ink, fontSize: 13.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now', style: TextStyle(color: muted)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            openAppSettings();
          },
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TripStore.instance.addListener(_onStore);
    _checkUpiDetection();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final user = await ApiClient.instance.refreshMe();
      if (mounted) setState(() => _user = user);
    } on ApiException {
      // Offline or an older server: the saved profile is still good.
    }
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _editName() async {
    final user = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditFieldSheet(
        title: 'Your name',
        subtitle: 'This is what everyone on your trips sees.',
        label: 'NAME',
        hint: 'e.g. Aarav',
        icon: Icons.person_outline_rounded,
        initial: _user?.name ?? '',
        emptyError: 'Enter your name.',
        save: ApiClient.instance.updateName,
      ),
    );
    if (user != null && mounted) setState(() => _user = user);
  }

  Future<void> _editUpiId() async {
    final user = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditFieldSheet(
        title: 'Your UPI ID',
        subtitle: 'Tripmates who owe you can tap “Pay” and their UPI app opens with your ID and the amount filled in.',
        label: 'UPI ID',
        hint: 'e.g. aarav@okhdfc',
        icon: Icons.qr_code_2_outlined,
        initial: _user?.upiId ?? '',
        keyboard: TextInputType.emailAddress,
        capitalization: TextCapitalization.none,
        save: ApiClient.instance.updateUpiId,
      ),
    );
    if (user != null && mounted) {
      setState(() => _user = user);
      TripStore.instance.refresh();
    }
  }

  /// For accounts made with the old phone login: attach a Google account so
  /// the session can be renewed without a code, keeping every trip.
  Future<void> _connectGoogle() async {
    setState(() => _linking = true);
    try {
      final idToken = await GoogleAuth.signIn();
      final user = await ApiClient.instance.signInWithGoogle(idToken);
      if (!mounted) return;
      setState(() => _user = user);
      _toast('Google account connected.');
    } on GoogleAuthException catch (e) {
      if (!e.canceled && mounted) _toast(e.message);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      _toast("You're on the latest version.");
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Sign out?', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        content: Text(
          _user?.hasGoogle == true
              ? 'Your trips stay safe on the server. Sign back in with the same Google account to see them again.'
              : 'This account has no Google account connected, so you would need the old phone login to get back in. Connect Google first to keep your trips.',
          style: const TextStyle(color: muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _owe),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await GoogleAuth.signOut();
    await ApiClient.instance.logOut();
    TripStore.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    // Light status-bar icons over the dark header.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: paper,
        body: user == null
            ? const SizedBox.shrink()
            : RefreshIndicator(
                onRefresh: _refresh,
                color: accent,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _header(user)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList.list(
                        children: [
                          _stats(),
                          if (!user.hasGoogle) ...[const SizedBox(height: 14), _connectCard()],
                          const SizedBox(height: 22),
                          _sectionLabel('YOUR TRIPS'),
                          ..._trips(),
                          const SizedBox(height: 22),
                          _sectionLabel('ACCOUNT'),
                          _card([
                            _row(
                              icon: Icons.badge_outlined,
                              label: 'Name',
                              value: user.name,
                              trailing: const Icon(Icons.edit_outlined, size: 17, color: muted),
                              onTap: _editName,
                            ),
                            _row(
                              icon: Icons.qr_code_2_outlined,
                              label: 'UPI ID',
                              value: user.upiId ?? 'Add one so friends can pay you',
                              trailing: const Icon(Icons.edit_outlined, size: 17, color: muted),
                              onTap: _editUpiId,
                            ),
                            if (user.email != null)
                              _row(icon: Icons.alternate_email_rounded, label: 'Email', value: user.email!),
                            if (user.phone != null)
                              _row(icon: Icons.phone_outlined, label: 'Phone', value: user.phone!),
                            _row(
                              icon: Icons.verified_user_outlined,
                              label: 'Sign-in',
                              value: user.hasGoogle ? 'Google · stays signed in' : 'Phone (legacy)',
                              trailing: user.hasGoogle ? const GoogleLogo(size: 16) : null,
                            ),
                          ]),
                          const SizedBox(height: 22),
                          _sectionLabel('APP'),
                          _card([
                            _row(
                              icon: _upiDetection && _upiAlertsOn
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_off_outlined,
                              label: 'UPI payment alerts',
                              value: !_upiDetection
                                  ? 'Needs SMS access — switch on'
                                  : _upiAlertsOn
                                  ? 'On for every UPI payment'
                                  : 'Off',
                              trailing: Switch(
                                value: _upiDetection && _upiAlertsOn,
                                onChanged: _setUpiAlerts,
                                activeThumbColor: Colors.white,
                                activeTrackColor: accent,
                              ),
                            ),
                            _row(
                              icon: Icons.info_outline_rounded,
                              label: 'Version',
                              value: _packageInfo == null
                                  ? '…'
                                  : 'v${_packageInfo!.version} · build ${_packageInfo!.buildNumber}',
                            ),
                            _row(
                              icon: Icons.system_update_outlined,
                              label: 'Updates',
                              value: 'Check for a new version',
                              trailing: const Icon(Icons.chevron_right_rounded, color: muted),
                              onTap: _checkForUpdate,
                            ),
                          ]),
                          const SizedBox(height: 26),
                          SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _owe,
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFF3CDD2)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _header(AppUser user) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.fromLTRB(8, top + 4, 8, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ink, Color(0xFF2A3480), accent],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (widget.embedded)
                const SizedBox(width: 48)
              else
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              const Expanded(
                child: Text(
                  'Profile',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentGlow,
              boxShadow: [BoxShadow(color: accentGlow.withValues(alpha: .35), blurRadius: 22)],
            ),
            child: UserAvatar(user: user, size: 88),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              user.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.email ?? user.phone ?? '',
            style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 13),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    user.hasGoogle ? Icons.verified_outlined : Icons.phone_iphone_outlined,
                    size: 14,
                    color: accentGlow,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    user.hasGoogle ? 'Signed in with Google' : 'Phone account',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final net = _netBalance;
    final settled = net == null || net.abs() < 0.5;
    final owed = (net ?? 0) > 0;
    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: Icons.luggage_outlined,
            color: accent,
            value: _tripCount?.toString() ?? '–',
            label: _tripCount == 1 ? 'Split' : 'Splits',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            icon: settled
                ? Icons.check_circle_outline_rounded
                : (owed ? Icons.south_west_rounded : Icons.north_east_rounded),
            color: settled ? accent : (owed ? positive : _owe),
            value: net == null ? '–' : (settled ? 'All square' : money(net.abs())),
            label: settled ? 'Across all trips' : (owed ? 'You\'re owed' : 'You owe'),
          ),
        ),
      ],
    );
  }

  Widget _statTile({required IconData icon, required Color color, required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3),
                  ),
                ),
                Text(label, style: const TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect your Google account',
            style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Phone codes are gone. Connect Google once to keep this account and all its trips, and stay signed in.',
            style: TextStyle(color: muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _linking ? null : _connectGoogle,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white,
                foregroundColor: ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: line),
                ),
              ),
              child: _linking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GoogleLogo(size: 18),
                        SizedBox(width: 10),
                        Text('Connect Google', style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Every trip (tap to show it on the Trip tab), then New / Join.
  List<Widget> _trips() {
    final store = TripStore.instance;
    final trips = store.trips;
    return [
      if (trips == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: accent)),
        )
      else
        for (final t in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TripCard(trip: t, current: t.id == store.currentTripId),
          ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showJoinTrip(context),
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Join trip'),
              style: secondaryButton(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => showCreateTrip(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New trip'),
              style: primaryButton(),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    child: Text(
      text,
      style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
    ),
  );

  Widget _card(List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: cardDecoration(),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 58, color: _hairline),
          rows[i],
        ],
      ],
    ),
  );

  Widget _row({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
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
                  Text(label, style: const TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
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
}

/// A one-field profile edit (name, UPI ID).
class _EditFieldSheet extends StatefulWidget {
  const _EditFieldSheet({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.hint,
    required this.icon,
    required this.initial,
    required this.save,
    this.emptyError,
    this.keyboard,
    this.capitalization = TextCapitalization.words,
  });
  final String title;
  final String subtitle;
  final String label;
  final String hint;
  final IconData icon;
  final String initial;
  final Future<AppUser> Function(String) save;

  /// Set when the field can't be left empty.
  final String? emptyError;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;

  @override
  State<_EditFieldSheet> createState() => _EditFieldSheetState();
}

class _EditFieldSheetState extends State<_EditFieldSheet> {
  late final _name = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty && widget.emptyError != null) {
      setState(() => _error = widget.emptyError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.save(name);
      if (mounted) Navigator.pop(context, user);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5D8E2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              style: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
            ),
            const SizedBox(height: 6),
            Text(widget.subtitle, style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 20),
            fieldLabel(widget.label),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: true,
              keyboardType: widget.keyboard,
              autocorrect: widget.keyboard == null,
              textCapitalization: widget.capitalization,
              onSubmitted: (_) => _save(),
              decoration: appInputDecoration(widget.hint, widget.icon),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: _owe, fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
