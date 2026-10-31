// lib/core/session/session_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart'
    show GlobalKey, NavigatorState, ScaffoldMessengerState, SnackBar, Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_modules.dart';
import '../network/api_endpoints.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';
import '../utils/json_helpers.dart';
import 'auth_api_service.dart';
import 'mock_accounts.dart';
import 'onboarding_controller.dart';
import 'user_role.dart';

/// The app's `MaterialApp.scaffoldMessengerKey`: for messages that do not
/// come from a screen ("Phiên đăng nhập đã hết hạn").
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// The app's `MaterialApp.navigatorKey`: an expired session closes every page
/// above the shell from outside any screen.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// What one person leaves on the device: search history, recent views, the
/// chosen location. Removed when a session ends, so a guest or the next
/// account starts clean.
abstract final class UserDataKeys {
  static const recentSearches = 'vl.recent_searches';
  static const recentViews = 'vl.recent_views';
  static const userLocation = 'vl.user_location';
  static const recentLocations = 'vl.recent_locations';

  static const all = [
    recentSearches,
    recentViews,
    userLocation,
    recentLocations,
  ];
}

/// Goes up each time a session ends: the controllers holding [UserDataKeys]
/// watch it and read their (now empty) keys again. Has no dependency, so bare
/// test containers without a session can watch it too.
final sessionEndCountProvider = StateProvider<int>((_) => 0);

/// Overridden in `main()` with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main()'),
);

class AuthSession {
  const AuthSession({
    required this.guestToken,
    this.accessToken,
    this.displayName,
    this.userId,
    this.role = UserRole.user,
  });

  /// Stable per-install id. The server counts guest AI questions against it.
  final String guestToken;
  final String? accessToken;
  final String? displayName;

  /// Signed-in user's id (`users.id` as a string); null for guests.
  final String? userId;

  /// Meaningful only when signed in; guests read as [UserRole.user].
  final UserRole role;

  bool get isGuest => accessToken == null;

  bool get isChef => !isGuest && role == UserRole.chef;

  Map<String, String> get authHeaders => isGuest
      ? {'X-Guest-Token': guestToken}
      : {'Authorization': 'Bearer $accessToken'};
}

/// Email + password session, kept in `shared_preferences`.
///
/// Production should keep the tokens in secure storage (Keychain /
/// Keystore); that needs a new dependency, not approved yet.
class SessionController extends Notifier<AuthSession> {
  static const _kGuestToken = 'vl.guest_token';
  static const accessTokenKey = 'vl.access_token';
  static const refreshTokenKey = 'vl.refresh_token';
  static const expiresAtKey = 'vl.expires_at';
  static const _kDisplayName = 'vl.display_name';
  static const _kUserId = 'vl.user_id';
  static const _kRole = 'vl.role';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  bool _expiring = false;

  @override
  AuthSession build() {
    var guestToken = _prefs.getString(_kGuestToken);
    if (guestToken == null) {
      guestToken = _newGuestToken();
      unawaited(_prefs.setString(_kGuestToken, guestToken));
    }
    final accessToken = _prefs.getString(accessTokenKey);
    var userId = _prefs.getString(_kUserId);
    // Mock sessions saved before accounts existed were always Minh Anh.
    if (accessToken != null &&
        userId == null &&
        BackendModules.isMock(BackendModule.auth)) {
      userId = minhAnhAccount.userId;
    }
    return AuthSession(
      guestToken: guestToken,
      accessToken: accessToken,
      displayName: _prefs.getString(_kDisplayName),
      userId: accessToken == null ? null : userId,
      role: UserRole.fromApi(_prefs.getString(_kRole)),
    );
  }

  /// `POST /auth/login`. Throws [ApiException] with a Vietnamese message
  /// (wrong password, locked, admin, too many attempts…).
  Future<void> signIn({required String email, required String password}) async {
    final result = await ref
        .read(authApiProvider)
        .login(email: email.trim(), password: password);
    await _start(result);
  }

  /// `POST /auth/register`, then signed in. The account is always a member
  /// (`User`); becoming a chef goes through the chef application.
  Future<AuthResult> register(RegisterRequest request) async {
    final result = await ref.read(authApiProvider).register(request);
    await _start(result);
    return result;
  }

  Future<void> _start(AuthResult result) async {
    await _prefs.setString(accessTokenKey, result.accessToken);
    await _setOrRemove(refreshTokenKey, result.refreshToken);
    await _setOrRemove(
        expiresAtKey, result.expiresAt?.toUtc().toIso8601String());
    await _prefs.setString(_kDisplayName, result.displayName);
    await _prefs.setString(_kRole, result.role.apiValue);
    await _setOrRemove(_kUserId, result.userId);
    state = AuthSession(
      guestToken: state.guestToken,
      accessToken: result.accessToken,
      displayName: result.displayName,
      userId: result.userId,
      role: result.role,
    );
    await ref.read(onboardingProvider.notifier).complete();
  }

  /// Back to guest mode (Trang chủ), never to the Welcome screen.
  Future<void> signOut() async {
    for (final key in [
      accessTokenKey,
      refreshTokenKey,
      expiresAtKey,
      _kDisplayName,
      _kUserId,
      _kRole,
      ...UserDataKeys.all,
    ]) {
      await _prefs.remove(key);
    }
    ref.read(sessionEndCountProvider.notifier).state++;
    state = AuthSession(guestToken: state.guestToken);
    await ref.read(onboardingProvider.notifier).complete();
  }

  /// "Thông tin cá nhân" saved a new name: the composer, the account menu and
  /// everything the app signs with it follow at once.
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (state.isGuest || trimmed.isEmpty || trimmed == state.displayName) {
      return;
    }
    await _prefs.setString(_kDisplayName, trimmed);
    state = AuthSession(
      guestToken: state.guestToken,
      accessToken: state.accessToken,
      displayName: trimmed,
      userId: state.userId,
      role: state.role,
    );
  }

  /// The server no longer accepts this session: every pushed page closes (it
  /// may show private data and could only fail from here on), then back to
  /// guest with a snackbar. Several requests can fail at once, so only the
  /// first call acts. With [token], only if it still is the session's token.
  Future<void> expire({
    String? token,
    String message = AuthErrors.sessionExpired,
  }) async {
    if (_expiring || state.isGuest) return;
    if (token != null && token != state.accessToken) return;
    _expiring = true;
    try {
      rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      await signOut();
      rootScaffoldMessengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      _expiring = false;
    }
  }

  /// At app start, for a session on the real BE: ends it if its JWT is past
  /// `vl.expires_at`, otherwise refreshes the name and role from `GET /users/me`.
  /// A 401 there is handled by `UnauthorizedInterceptor`; a 423 signs out with
  /// the locked message. Network errors change nothing. Never throws.
  Future<void> revalidate() async {
    if (BackendModules.isMock(BackendModule.auth) || state.isGuest) return;
    final expiresAt = readDateTime(_prefs.getString(expiresAtKey));
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      await expire();
      return;
    }
    final token = state.accessToken;
    try {
      final res = await ref.read(dioProvider).get<Object?>(ApiEndpoints.me);
      if (state.accessToken != token) return;
      await _applyServerProfile(readMap(res.data));
    } on DioException catch (e) {
      if (mapDioException(e).statusCode == 423) {
        await expire(token: token, message: AuthErrors.accountLocked);
      }
    } catch (_) {
      // An unexpected body must not disturb app start.
    }
  }

  Future<void> _applyServerProfile(Map<String, dynamic> user) async {
    final name = (user['fullName'] ?? user['name'])?.toString();
    final displayName = name == null || name.isEmpty ? state.displayName : name;
    final role =
        user['role'] == null ? state.role : UserRole.fromApi(user['role']);
    if (displayName == state.displayName && role == state.role) return;
    await _setOrRemove(_kDisplayName, displayName);
    await _prefs.setString(_kRole, role.apiValue);
    state = AuthSession(
      guestToken: state.guestToken,
      accessToken: state.accessToken,
      displayName: displayName,
      userId: state.userId,
      role: role,
    );
  }

  Future<void> _setOrRemove(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  static String _newGuestToken() {
    final rand = Random.secure().nextInt(0xFFFFFFFF).toRadixString(36);
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'guest_${time}_$rand';
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, AuthSession>(SessionController.new);
