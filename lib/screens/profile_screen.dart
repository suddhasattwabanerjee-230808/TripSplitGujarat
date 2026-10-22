import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api_client.dart';
import '../app_resume.dart';
import '../city_photo.dart';
import '../expense_notifier.dart';
import '../google_auth.dart';
import '../ledger.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../update_service.dart';
import '../widgets.dart';
import 'app_settings_screen.dart';
import 'login_screen.dart';
import 'trips_ui.dart';

final _owe = negative;

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
        child: _photo == null ? fallback : profilePhoto(_photo!, fallback),
      ),
    );
    return hero ? Hero(tag: 'profile-avatar', child: avatar) : avatar;
  }
}

/// The way into the profile from the top of the app: the user's photo in a
/// ring of the brand's orange-to-wine gradient.
class ProfileButton extends StatefulWidget {
  const ProfileButton({super.key, this.size = 34});
  final double size;

  @override
  State<ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<ProfileButton> {
  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (mounted) setState(() {}); // a new photo or nickname
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: 'Profile',
      child: GestureDetector(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(colors: [logoOrange, wineBright, wine, logoOrange]),
            boxShadow: [BoxShadow(color: wine.withValues(alpha: .25), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: paper),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(user: user, size: widget.size),
                // A new version is out: its way in is on the profile.
                ListenableBuilder(
                  listenable: Updates.instance,
                  builder: (context, _) => !Updates.instance.available
                      ? const SizedBox.shrink()
                      : Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: paper, width: 1.5),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false});

  /// Shown as a tab in the home shell (no back button).
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _updates = Updates.instance;
  bool _deleting = false;
  bool _savingPhoto = false;
  AppUser? _user = ApiClient.instance.currentUser;
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
    TripStore.instance.removeListener(_onStore);
    _updates.removeListener(_onStore);
    CityPhoto.instance.removeListener(_onStore);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    TripStore.instance.addListener(_onStore);
    _updates.addListener(_onStore);
    CityPhoto.instance.addListener(_onStore);
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

  /// Pick a new photo (gallery or camera), or go back to the Google one.
  Future<void> _editPhoto() async {
    final user = _user;
    if (user == null) return;
    final choice = await showAppSheet<String>(
      context,
      title: 'Profile Photo',
      subtitle: 'What your tripmates see next to your name.',
      children: (ctx) => [
        groupedCard([
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: accent),
            title: const Text('Choose From Gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_outlined, color: accent),
            title: const Text('Take A Photo'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          if (user.customPhoto && user.hasGoogle)
            ListTile(
              leading: const GoogleLogo(size: 20),
              title: const Text('Use My Google Photo'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
        ]),
      ],
    );
    if (choice == null || !mounted) return;
    String? dataUri;
    if (choice != 'google') {
      // Small and square-ish: it's stored in Firestore and copied onto trips.
      AppResume.sendingOut();
      final picked = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 72,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 150 * 1024) {
        _toast('That photo is too large. Try another one.');
        return;
      }
      final type = picked.path.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      dataUri = 'data:image/$type;base64,${base64Encode(bytes)}';
    }
    setState(() => _savingPhoto = true);
    try {
      final updated = await ApiClient.instance.updatePhoto(dataUri);
      if (mounted) setState(() => _user = updated);
      TripStore.instance.refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Future<void> _editName() async {
    final user = await showModalBottomSheet<AppUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditFieldSheet(
        title: 'Nickname',
        subtitle: 'What everyone on your trips sees, instead of your Google name.',
        label: 'NICKNAME',
        hint: 'e.g. Bittu',
        icon: Icons.badge_outlined,
        initial: _user?.name ?? '',
        emptyError: 'Enter a nickname.',
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

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Sign Out?', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        content: Text(
          _user?.hasGoogle == true
              ? 'Your trips stay safe on the server. Sign back in with the same Google account to see them again.'
              : 'This account has no Google account connected, so you would need the old phone login to get back in. Connect Google first to keep your trips.',
          style: TextStyle(color: muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: muted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: _owe),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ExpenseNotifier.stop();
    await GoogleAuth.signOut();
    await ApiClient.instance.logOut();
    TripStore.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Deletes the account after a typed confirmation and a fresh Google
  /// sign-in (Firebase only deletes accounts that signed in recently).
  Future<void> _deleteAccount() async {
    // Debts first: deleting would leave tripmates with nobody to settle with.
    final me = _user?.id;
    final open = [
      for (final t in TripStore.instance.trips ?? const <Trip>[])
        if (me != null && unsettledAmount(t.paid[me] ?? 0, t.owed[me] ?? 0) != 0)
          (trip: t, amount: unsettledAmount(t.paid[me] ?? 0, t.owed[me] ?? 0)),
    ];
    if (open.isNotEmpty) {
      await showDialog<void>(context: context, builder: (_) => _SettleFirstDialog(open));
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (_) => const _DeleteAccountDialog());
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final idToken = await GoogleAuth.signIn();
      await ApiClient.instance.deleteAccount(idToken);
      await ExpenseNotifier.stop();
      await GoogleAuth.disconnect();
      TripStore.instance.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on GoogleAuthException catch (e) {
      if (!e.canceled) _toast(e.message);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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
                    SliverToBoxAdapter(child: RepaintBoundary(child: _header(user))),
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
                          _settingsButton(),
                          const SizedBox(height: 26),
                          SizedBox(
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _owe,
                                backgroundColor: surface,
                                side: BorderSide(color: negative.withValues(alpha: .3)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: _deleting ? null : _deleteAccount,
                              icon: _deleting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: _owe),
                                    )
                                  : const Icon(Icons.delete_forever_outlined, size: 18),
                              label: Text(
                                _deleting ? 'Deleting Your Account…' : 'Delete Account',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              style: TextButton.styleFrom(foregroundColor: _owe),
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
    // The city the phone is in, blended into the brand gradient.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CityBackdrop(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, top + 4, 8, 26),
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
                  const ThemeToggle(color: Colors.white),
                ],
              ),
              const SizedBox(height: 8),
              // Tap the photo to change it.
              GestureDetector(
                onTap: _savingPhoto ? null : _editPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentGlow,
                        boxShadow: [BoxShadow(color: accentGlow.withValues(alpha: .35), blurRadius: 22)],
                      ),
                      child: UserAvatar(user: user, size: 88),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 8)],
                        ),
                        child: _savingPhoto
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                              )
                            : Icon(Icons.photo_camera_outlined, size: 17, color: accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // The nickname: tap it (or the pencil) to change it.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: InkWell(
                  onTap: _editName,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
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
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined, size: 18, color: Colors.white.withValues(alpha: .75)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The email comes from Google: say so with its logo.
                  if (user.email != null) ...[
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const GoogleLogo(size: 12),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      user.email ?? user.phone ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Their UPI ID, so tripmates who owe them can pay it: tap to change.
              Material(
                color: Colors.white.withValues(alpha: .14),
                shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: .18))),
                child: InkWell(
                  onTap: _editUpiId,
                  customBorder: const StadiumBorder(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_2_rounded, size: 15, color: accentGlow),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            user.upiId == null ? 'Add Your UPI ID' : 'UPI · ${user.upiId}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          user.upiId == null ? Icons.add_rounded : Icons.edit_outlined,
                          size: 14,
                          color: Colors.white.withValues(alpha: .8),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (CityPhoto.instance.city != null && CityPhoto.instance.image != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 12, color: Colors.white.withValues(alpha: .6)),
                    const SizedBox(width: 3),
                    Text(
                      '${CityPhoto.instance.city} · Photo Wikimedia Commons',
                      style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
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
            value: net == null ? '–' : (settled ? 'All Square' : money(net.abs())),
            label: settled ? 'Across All Trips' : (owed ? 'You\'re Owed' : 'You Owe'),
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
                Text(label, style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
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
          Text(
            'Connect Your Google Account',
            style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
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
                  side: BorderSide(color: line),
                ),
              ),
              child: _linking
                  ? SizedBox(
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
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
              label: const Text('Join Trip'),
              style: secondaryButton(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => showCreateTrip(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Trip'),
              style: primaryButton(),
            ),
          ),
        ],
      ),
    ];
  }

  /// App Settings (notifications, font, text size, updates), on its own page.
  Widget _settingsButton() => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
      side: BorderSide(color: line.withValues(alpha: .7)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppSettingsScreen())),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        child: Row(
          children: [
            const IconCircle(icon: Icons.tune_rounded, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('App Settings', style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'Notifications, Font, Text Size, Updates',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_updates.available)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
            Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    ),
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
    child: Text(
      text,
      style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800),
    ),
  );


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
      decoration: BoxDecoration(
        color: paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: muted.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
            ),
            const SizedBox(height: 6),
            Text(widget.subtitle, style: TextStyle(color: muted, fontSize: 13)),
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
                child: Text(_error!, style: TextStyle(color: _owe, fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: onAccent),
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

/// "Delete your account?" with a typed confirmation, since it can't be undone.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _typed = TextEditingController();

  bool get _confirmed => _typed.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: paper,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Text('Delete Your Account?', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This can’t be undone. It permanently removes:\n'
            '• your TripSplit login, profile and nickname\n'
            '• your photo and UPI ID on every trip\n'
            '• invites sent to you or by you\n'
            '• TripSplit’s access to your Google account\n\n'
            'Expenses you shared stay on your trips, so your tripmates’ balances still add up; '
            'they’ll show you as “$deletedUserName”. Your Google account itself isn’t touched.\n\n'
            'Google will ask you to confirm it’s you.',
            style: TextStyle(color: muted, height: 1.45, fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: appInputDecoration('Type DELETE To Confirm', Icons.warning_amber_rounded),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text('Cancel', style: TextStyle(color: muted)),
      ),
      FilledButton(
        onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
        style: FilledButton.styleFrom(backgroundColor: _owe),
        child: const Text('Delete'),
      ),
    ],
  );
}

/// Shown instead of deleting while any trip still has money open for the user.
class _SettleFirstDialog extends StatelessWidget {
  const _SettleFirstDialog(this.open);

  final List<({Trip trip, double amount})> open;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: paper,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: Text('Settle Up First', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your account can’t be deleted while money is still owed on a trip. Clear these on the Balance tab, then try again:',
          style: TextStyle(color: muted, height: 1.45, fontSize: 13.5),
        ),
        const SizedBox(height: 14),
        for (final o in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    o.trip.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  o.amount < 0 ? 'You Owe ${money(-o.amount)}' : 'Owed To You ${money(o.amount)}',
                  style: TextStyle(color: o.amount < 0 ? _owe : positive, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        style: primaryButton(radius: 12),
        child: const Text('OK'),
      ),
    ],
  );
}
