import 'package:flutter/widgets.dart';

/// Where TripSplit picks up when it comes back on screen: just as it was left
/// if it was away less than [keepFor], otherwise on the Trip page, at the top.
/// A hop TripSplit itself started (a UPI app, the camera, email) always comes
/// back to where it was, however long it took.
class AppResume {
  AppResume._();

  static const keepFor = Duration(seconds: 10);

  /// Bumped each time the app comes back fresh: the shell opens the Trip tab
  /// and the Trip page scrolls to the top.
  static final fresh = ValueNotifier(0);

  /// Keeps track of the open screens, so coming back fresh can close them.
  static final observer = _RouteLog();

  static DateTime? _sendingAt;
  static bool _sentOut = false;
  static List<Route<dynamic>> _openWhenLeft = const [];

  /// Call just before opening another app on purpose.
  static void sendingOut() => _sendingAt = DateTime.now();

  /// The app has left the screen.
  static void left() {
    final at = _sendingAt;
    _sentOut = at != null && DateTime.now().difference(at) < const Duration(seconds: 5);
    _sendingAt = null;
    _openWhenLeft = observer.routes.skip(1).toList();
  }

  /// Back on screen after [away]. Starting fresh closes the screens that were
  /// open when it left, without animating; one a tapped notification opened
  /// since stays.
  static void cameBack(Duration away) {
    final open = _openWhenLeft;
    _openWhenLeft = const [];
    if (_sentOut || away < keepFor) return;
    final navigator = observer.navigator;
    if (navigator != null) {
      for (final route in open.reversed) {
        if (observer.routes.contains(route)) navigator.removeRoute(route);
      }
    }
    fresh.value++;
  }
}

class _RouteLog extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (i < 0) return;
    if (newRoute == null) {
      routes.removeAt(i);
    } else {
      routes[i] = newRoute;
    }
  }
}
