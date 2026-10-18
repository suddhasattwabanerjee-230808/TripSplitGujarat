import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api_client.dart';
import '../google_auth.dart';
import '../models.dart';
import '../theme.dart';
import '../update_service.dart';
import 'login_screen.dart';
import 'update_dialog.dart';

const _owe = Color(0xFFD1805C);
const _hairline = Color(0xFFEDEBE3);

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
      color: colorForMember(user.id),
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
  const ProfileScreen({super.key, this.tripCount, this.netBalance});

  /// Passed from the trip list so the stats show instantly.
  final int? tripCount;
  final double? netBalance;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user = ApiClient.instance.currentUser;
  PackageInfo? _packageInfo;
  bool _linking = false;

  @override
  void initState() {
    super.initState();
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
      builder: (_) => _EditNameSheet(initial: _user?.name ?? ''),
    );
    if (user != null && mounted) setState(() => _user = user);
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
                color: teal,
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
                          _sectionLabel('ACCOUNT'),
                          _card([
                            _row(
                              icon: Icons.badge_outlined,
                              label: 'Name',
                              value: user.name,
                              trailing: const Icon(Icons.edit_rounded, size: 17, color: muted),
                              onTap: _editName,
                            ),
                            if (user.email != null)
                              _row(icon: Icons.alternate_email_rounded, label: 'Email', value: user.email!),
                            if (user.phone != null)
                              _row(icon: Icons.phone_rounded, label: 'Phone', value: user.phone!),
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
                              icon: Icons.info_outline_rounded,
                              label: 'Version',
                              value: _packageInfo == null
                                  ? '…'
                                  : 'v${_packageInfo!.version} · build ${_packageInfo!.buildNumber}',
                            ),
                            _row(
                              icon: Icons.system_update_rounded,
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
                                side: const BorderSide(color: Color(0xFFF1D5C8)),
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
          colors: [ink, Color(0xFF0F4F57), teal],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  'PROFILE',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w800),
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
              color: lime,
              boxShadow: [BoxShadow(color: lime.withValues(alpha: .35), blurRadius: 22)],
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
                    user.hasGoogle ? Icons.verified_rounded : Icons.phone_iphone_rounded,
                    size: 14,
                    color: lime,
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
    final net = widget.netBalance;
    final settled = net == null || net.abs() < 0.5;
    final owed = (net ?? 0) > 0;
    return Row(
      children: [
        Expanded(
          child: _statTile(
            icon: Icons.luggage_rounded,
            color: teal,
            value: widget.tripCount?.toString() ?? '–',
            label: widget.tripCount == 1 ? 'Trip' : 'Trips',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statTile(
            icon: settled
                ? Icons.check_circle_outline_rounded
                : (owed ? Icons.south_west_rounded : Icons.north_east_rounded),
            color: settled || owed ? teal : _owe,
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(ink, .05),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
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
        color: const Color(0xFFEAF2E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: teal.withValues(alpha: .18)),
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
                  side: const BorderSide(color: Color(0xFFE4E1D6)),
                ),
              ),
              child: _linking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: teal),
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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    child: Text(
      text,
      style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
    ),
  );

  Widget _card(List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: softShadow(ink, .05),
    ),
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

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initial});
  final String initial;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
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
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ApiClient.instance.updateName(name);
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
                  color: const Color(0xFFD9DED8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Your name',
              style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is what everyone on your trips sees.',
              style: TextStyle(color: muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            fieldLabel('NAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: appInputDecoration('e.g. Aarav', Icons.person_outline_rounded),
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
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
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
