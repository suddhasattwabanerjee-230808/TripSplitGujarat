import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/trip_list_screen.dart';
import 'screens/update_dialog.dart';
import 'theme.dart';
import 'update_service.dart';

void main() => runApp(const TripSplitApp());

class TripSplitApp extends StatefulWidget {
  const TripSplitApp({super.key});

  @override
  State<TripSplitApp> createState() => _TripSplitAppState();
}

class _TripSplitAppState extends State<TripSplitApp> with WidgetsBindingObserver {
  Key _splashKey = UniqueKey();
  bool _showSplash = true;
  bool _splashFadingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-arm the intro whenever the app leaves the screen, so it plays on every
    // return. Arming it while hidden means the first frame back is already the intro.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      setState(() {
        _splashKey = UniqueKey();
        _showSplash = true;
        _splashFadingOut = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: teal, brightness: Brightness.light);
    return MaterialApp(
      title: 'TripSplit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(backgroundColor: paper, foregroundColor: ink),
      ),
      home: const _AppRoot(),
      // The intro sits above the navigator, so it can replay over whatever screen
      // is open without disturbing it.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            child: child!,
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
                  if (_splashFadingOut) setState(() => _showSplash = false);
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
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (info != null && mounted) showUpdateDialog(context, info);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _loggedIn == null
        ? const Scaffold(
            key: ValueKey('loading'),
            backgroundColor: paper,
            body: Center(child: CircularProgressIndicator(color: teal)),
          )
        : KeyedSubtree(
            key: ValueKey(_loggedIn),
            child: _loggedIn! ? const TripListScreen() : const LoginScreen(),
          );
    return AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: child);
  }
}
