// lib/core/session/session_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import 'auth_api_service.dart';
import 'mock_accounts.dart';
import 'onboarding_controller.dart';
import 'user_role.dart';

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
    if (accessToken != null && userId == null && Env.useMockData) {
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
    ]) {
      await _prefs.remove(key);
    }
    state = AuthSession(guestToken: state.guestToken);
    await ref.read(onboardingProvider.notifier).complete();
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
