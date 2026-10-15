// lib/core/session/session_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';
import 'auth_api_service.dart';
import 'mock_accounts.dart';
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

class SessionController extends Notifier<AuthSession> {
  static const _kGuestToken = 'vl.guest_token';
  static const _kAccessToken = 'vl.access_token';
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
    final accessToken = _prefs.getString(_kAccessToken);
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

  /// [account] picks the identity in mock mode (see `runGoogleSignIn`);
  /// without it the mock signs in as [minhAnhAccount].
  Future<void> signInWithGoogle({MockAccount? account}) async {
    final result = await ref
        .read(authApiProvider)
        .signInWithGoogle(guestToken: state.guestToken, account: account);
    await _prefs.setString(_kAccessToken, result.accessToken);
    await _prefs.setString(_kDisplayName, result.displayName);
    await _prefs.setString(_kRole, result.role.apiValue);
    if (result.userId case final id?) {
      await _prefs.setString(_kUserId, id);
    } else {
      await _prefs.remove(_kUserId);
    }
    state = AuthSession(
      guestToken: state.guestToken,
      accessToken: result.accessToken,
      displayName: result.displayName,
      userId: result.userId,
      role: result.role,
    );
  }

  Future<void> signOut() async {
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kDisplayName);
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kRole);
    state = AuthSession(guestToken: state.guestToken);
  }

  static String _newGuestToken() {
    final rand = Random.secure().nextInt(0xFFFFFFFF).toRadixString(36);
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'guest_${time}_$rand';
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, AuthSession>(SessionController.new);
