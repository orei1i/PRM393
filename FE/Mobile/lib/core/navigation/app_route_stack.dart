// lib/core/navigation/app_route_stack.dart
import 'package:flutter/widgets.dart';

/// Mirrors the routes of the navigator it observes, bottom to top, so
/// [AppNav] can tell whether a page is already open under the current one.
///
/// Registered once on the app's `MaterialApp.navigatorObservers`; found
/// again through `navigator.widget.observers` ([of]). A navigator without
/// it (e.g. a widget test's plain `MaterialApp`) has no stack: the helpers
/// then simply push.
class AppRouteStack extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  /// The navigator [_routes] belong to: attaching to another one (a new
  /// app tree) starts from an empty stack.
  NavigatorState? _owner;

  /// The stack observing [navigator], if one is registered on it.
  static AppRouteStack? of(NavigatorState navigator) {
    for (final observer in navigator.widget.observers) {
      if (observer is AppRouteStack) return observer;
    }
    return null;
  }

  /// The routes present in the navigator, bottom (the shell) to top,
  /// dialogs and sheets included.
  List<Route<dynamic>> get routes => List.unmodifiable(_sync());

  /// The topmost route named [name], or `null`.
  Route<dynamic>? lastNamed(String name) {
    final routes = _sync();
    for (var i = routes.length - 1; i >= 0; i--) {
      if (routes[i].settings.name == name) return routes[i];
    }
    return null;
  }

  /// How many routes are named [name].
  int countNamed(String name) =>
      _sync().where((r) => r.settings.name == name).length;

  List<Route<dynamic>> _sync() {
    final current = navigator;
    if (!identical(current, _owner)) {
      _routes.clear();
      _owner = current;
    }
    return _routes;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final routes = _sync()..remove(route);
    // Several routes added at once (initial routes) are reported top first,
    // so place each one right above the route it was pushed on.
    if (previousRoute == null) {
      routes.insert(0, route);
      return;
    }
    final below = routes.indexOf(previousRoute);
    if (below < 0) {
      routes.add(route);
    } else {
      routes.insert(below + 1, route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync().remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync().remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final routes = _sync();
    final at = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (newRoute == null) {
      if (at >= 0) routes.removeAt(at);
    } else if (at >= 0) {
      routes[at] = newRoute;
    } else {
      routes.add(newRoute);
    }
  }
}
