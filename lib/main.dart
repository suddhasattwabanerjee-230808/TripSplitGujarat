import 'package:flutter/material.dart';

import 'api_client.dart';
import 'screens/login_screen.dart';
import 'screens/trip_list_screen.dart';
import 'theme.dart';

void main() => runApp(const TripSplitApp());

class TripSplitApp extends StatelessWidget {
  const TripSplitApp({super.key});

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
    if (_loggedIn == null) {
      return const Scaffold(
        backgroundColor: paper,
        body: Center(child: CircularProgressIndicator(color: teal)),
      );
    }
    return _loggedIn! ? const TripListScreen() : const LoginScreen();
  }
}
