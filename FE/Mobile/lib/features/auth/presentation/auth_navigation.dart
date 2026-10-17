// lib/features/auth/presentation/auth_navigation.dart
import 'package:flutter/widgets.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

/// Opens Đăng nhập / Tạo tài khoản from any prompt (sign-in sheet, guest
/// gates, account menu, Welcome). Both resolve to `true` only once the user
/// is signed in.
abstract final class AuthNavigation {
  static Future<bool> login(NavigatorState navigator, {String? email}) async =>
      await navigator.push<bool>(LoginScreen.route(email: email)) ?? false;

  static Future<bool> register(NavigatorState navigator) async =>
      await navigator.push<bool>(RegisterScreen.route()) ?? false;
}

/// Completes [route] with [result]: popped when it is on top, otherwise
/// removed in place (e.g. a sign-in sheet under "Hồ sơ chuyên gia", which
/// replaced Tạo tài khoản after a chef sign-up).
void completeRoute<T>(NavigatorState navigator, Route<T> route, T result) {
  if (!route.isActive) return;
  if (route.isCurrent) {
    navigator.pop<T>(result);
  } else {
    navigator.removeRoute<T>(route, result);
  }
}
