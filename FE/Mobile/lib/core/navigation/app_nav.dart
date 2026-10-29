// lib/core/navigation/app_nav.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_route_stack.dart';
import 'shell_tab.dart';

export 'app_route_stack.dart';
export 'app_routes.dart';
export 'shell_tab.dart';

/// Navigation that keeps the stack short: going back to a page that is
/// already open instead of stacking a copy, replacing a page, finishing a
/// flow on a single page above the shell, or switching shell tabs from a
/// pushed page.
///
/// "The same page" = a route with the same `RouteSettings.name` (see
/// `AppRoutes`), looked up in the navigator's [AppRouteStack]. Without one
/// (unnamed route, or a navigator that has no [AppRouteStack]) every helper
/// except [resetTo] / [toShellTab] simply pushes.
///
/// [replaceExisting], [resetTo], [popToOrReset] and [toShellTab] remove
/// pages without asking their `PopScope`: call them at completion points
/// only, never with an unsaved form in between.
abstract final class AppNav {
  /// Back to the open page named like [route] (popping what is above it),
  /// else pushes [route]. Going back completes with `null` right away.
  static Future<T?> open<T extends Object?>(
      NavigatorState navigator, Route<T> route) {
    final existing = _existing(navigator, route);
    if (existing == null) return navigator.push(route);
    _popTo(navigator, existing);
    return Future<T?>.value();
  }

  /// Removes the open page named like [route] and everything above it,
  /// then pushes [route] (new arguments); else just pushes [route].
  static Future<T?> replaceExisting<T extends Object?>(
      NavigatorState navigator, Route<T> route) {
    final existing = _existing(navigator, route);
    if (existing == null) return navigator.push(route);
    final routes = AppRouteStack.of(navigator)!.routes;
    final at = routes.indexOf(existing);
    final below = at > 0 ? routes[at - 1] : null;
    return navigator.pushAndRemoveUntil(
        route, (r) => below != null && identical(r, below));
  }

  /// Pushes [route] right above the shell (the first route), removing
  /// every page in between.
  static Future<T?> resetTo<T extends Object?>(
          NavigatorState navigator, Route<T> route) =>
      navigator.pushAndRemoveUntil(route, (r) => r.isFirst);

  /// [open] when a page named like [route] is open, else [resetTo].
  static Future<T?> popToOrReset<T extends Object?>(
      NavigatorState navigator, Route<T> route) {
    final existing = _existing(navigator, route);
    if (existing == null) return resetTo(navigator, route);
    _popTo(navigator, existing);
    return Future<T?>.value();
  }

  /// Back to the shell (pops every page above it) and selects [tab]; each
  /// tab keeps its state.
  static void toShellTab(
      NavigatorState navigator, WidgetRef ref, ShellTab tab) {
    // Read before popping: [ref] may belong to a page that is popped.
    final tabs = ref.read(shellTabProvider.notifier);
    navigator.popUntil((r) => r.isFirst);
    tabs.select(tab);
  }

  static Route<dynamic>? _existing(
      NavigatorState navigator, Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null) return null;
    return AppRouteStack.of(navigator)?.lastNamed(name);
  }

  static void _popTo(NavigatorState navigator, Route<dynamic> target) =>
      navigator.popUntil((r) => identical(r, target) || r.isFirst);
}
