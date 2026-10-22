import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_fonts.dart';
import 'app_resume.dart';
import 'expense_notifier.dart';
import 'screens/expense_screen.dart';
import 'screens/settle_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/home_shell.dart';
import 'screens/nickname_screen.dart';
import 'screens/update_dialog.dart';
import 'settle_watch.dart';
import 'theme.dart';
import 'update_service.dart';
import 'upi_popup.dart';

Future<void> main() async {
  await _initFirebase();
  await AppTheme.instance.load();
  await AppFonts.instance.load();
  _introOnStart = await _awayLongEnough();
  // Instant expense pushes while the app is closed (see ExpenseNotifier).
  if (Firebase.apps.isNotEmpty) FirebaseMessaging.onBackgroundMessage(expensePushHandler);
  runApp(const TripSplitApp());
}

/// Entrypoint for UpiPopupActivity (the "UPI payment detected" quick-add card).
/// It runs in its own engine, so it sets Firebase up too; the sign-in is shared.
@pragma('vm:entry-point')
Future<void> upiPopupMain() async {
  await _initFirebase();
  await AppTheme.instance.load();
  await AppFonts.instance.load();
  runApp(const UpiPopupApp());
}

/// The intro plays only when the app opens [_introGap] or more after it was
/// last closed; a quick hop out and back (a UPI app, the camera) skips it.
const _introGap = Duration(minutes: 1);
const _closedAtKey = 'trip_split.closed_at.v1';
bool _introOnStart = true;

Future<bool> _awayLongEnough() async {
  final closed = await SharedPreferencesAsync()
      .getInt(_closedAtKey)
      .timeout(const Duration(seconds: 2))
      .catchError((Object _) => null);
  if (closed == null) return true;
  return DateTime.now().millisecondsSinceEpoch - closed >= _introGap.inMilliseconds;
}

/// Reads the project settings google-services.json compiled into the APK.
Future<void> _initFirebase() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // No Firebase config (e.g. tests): the app opens on the sign-in screen.
  }
}

class TripSplitApp extends StatefulWidget {
  const TripSplitApp({super.key});

  @override
  State<TripSplitApp> createState() => _TripSplitAppState();
}

class _TripSplitAppState extends State<TripSplitApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  Key _splashKey = UniqueKey();
  bool _showSplash = _introOnStart;
  bool _splashFadingOut = false;
  DateTime? _closedAt;
  bool _toldUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sessions don't expire; this only fires if the server rejects one and
    // Google can't silently renew it.
    ApiClient.instance.onSessionExpired = () => _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    // A change saved offline that the server later refused.
    ApiClient.instance.onWriteError = (error) =>
        _messengerKey.currentState?.showSnackBar(SnackBar(content: Text('Not Saved: ${error.message}')));
    // Light/dark: redraw every screen in place with the new colours.
    AppTheme.instance.addListener(_onTheme);
    // A new font or bold text: the same, everywhere.
    AppFonts.instance.addListener(_onTheme);
    // Settle-ups paid in a UPI app, confirmed from the bank's SMS.
    SettleWatch.instance.init(() => _messengerKey.currentState);
    // A new version: say so once, after the intro.
    Updates.instance.addListener(_tellUpdate);
    Updates.instance.launchCheck();
    // A tapped expense notification, while the app is running: open it.
    ExpenseNotifier.appVisible = true;
    ExpenseNotifier.onOpen = (tripId, expenseId) {
      if (ApiClient.instance.currentUser == null) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ExpenseScreen(tripId: tripId, expenseId: expenseId)),
      );
    };
    // A settle-up reminder: open that balance with the ways to settle it.
    ExpenseNotifier.onSettle = (tripId, otherId) {
      if (ApiClient.instance.currentUser == null) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => SettleScreen(tripId: tripId, otherId: otherId)),
      );
    };
  }

  void _onTheme() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildEverything(context);
    });
  }

  void _tellUpdate() {
    final messenger = _messengerKey.currentState;
    if (_toldUpdate || _showSplash || !Updates.instance.available || messenger == null) return;
    _toldUpdate = true;
    showUpdateBanner(messenger, () => _navigatorKey.currentState!.overlay!.context);
  }

  @override
  void dispose() {
    Updates.instance.removeListener(_tellUpdate);
    AppTheme.instance.removeListener(_onTheme);
    AppFonts.instance.removeListener(_onTheme);
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.instance.onSessionExpired = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // System notifications only while the app isn't on screen.
    ExpenseNotifier.appVisible = state == AppLifecycleState.resumed;
    // Re-arm the intro whenever the app leaves the screen, so the first frame
    // back is already the intro; back within [_introGap], it's dropped again
    // before that frame is drawn.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      if (_closedAt == null) {
        _closedAt = DateTime.now();
        SharedPreferencesAsync().setInt(_closedAtKey, _closedAt!.millisecondsSinceEpoch).catchError((Object _) {});
        AppResume.left();
      }
      setState(() {
        _splashKey = UniqueKey();
        _showSplash = true;
        _splashFadingOut = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      final away = _closedAt == null ? Duration.zero : DateTime.now().difference(_closedAt!);
      _closedAt = null;
      // Away 10 seconds or more: back on the Trip page, at the top.
      AppResume.cameBack(away);
      if (away < _introGap && _showSplash && !_splashFadingOut) setState(() => _showSplash = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.instance.dark;
    return MaterialApp(
      title: 'TripSplit',
      navigatorKey: _navigatorKey,
      navigatorObservers: [AppResume.observer],
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      theme: appThemeData(),
      home: const _AppRoot(),
      // The intro sits above the navigator, so it can replay over whatever screen
      // is open without disturbing it.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: paper,
              systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            ),
            // Bold text and text size from App Settings, on top of the phone's own.
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                boldText: AppFonts.instance.bold || MediaQuery.boldTextOf(context),
                textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(16) / 16 * AppFonts.instance.scale),
              ),
              child: child!,
            ),
          ),
          if (_showSplash)
            IgnorePointer(
              key: _splashKey,
              ignoring: _splashFadingOut,
              child: AnimatedOpacity(
                opacity: _splashFadingOut ? 0 : 1,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                onEnd: () {
                  if (!_splashFadingOut) return;
                  setState(() => _showSplash = false);
                  _tellUpdate();
                },
                child: SplashScreen(onDone: () => setState(() => _splashFadingOut = true)),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.restoreSession().then((loggedIn) {
      if (mounted) setState(() => _loggedIn = loggedIn);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _loggedIn == null
        ? Scaffold(
            key: const ValueKey('loading'),
            backgroundColor: paper,
            body: Center(child: CircularProgressIndicator(color: accent)),
          )
        : KeyedSubtree(
            key: ValueKey(_loggedIn),
            child: !_loggedIn!
                ? const LoginScreen()
                : (ApiClient.instance.currentUser?.nicknameSet ?? true)
                ? const HomeShell()
                : const NicknameScreen(),
          );
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child);
  }
}
