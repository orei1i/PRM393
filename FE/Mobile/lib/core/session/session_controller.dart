// lib/core/session/session_controller.dart
import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_api_service.dart';

/// Overridden in `main()` with the real instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden in main()'),
);

class AuthSession {
  const AuthSession({required this.guestToken, this.accessToken, this.displayName});

  /// Stable per-install id. The server counts guest AI questions against it.
  final String guestToken;
  final String? accessToken;
  final String? displayName;

  bool get isGuest => accessToken == null;

  Map<String, String> get authHeaders => isGuest
      ? {'X-Guest-Token': guestToken}
      : {'Authorization': 'Bearer $accessToken'};
}

class SessionController extends Notifier<AuthSession> {
  static const _kGuestToken = 'vl.guest_token';
  static const _kAccessToken = 'vl.access_token';
  static const _kDisplayName = 'vl.display_name';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AuthSession build() {
    var guestToken = _prefs.getString(_kGuestToken);
    if (guestToken == null) {
      guestToken = _newGuestToken();
      unawaited(_prefs.setString(_kGuestToken, guestToken));
    }
    return AuthSession(
      guestToken: guestToken,
      accessToken: _prefs.getString(_kAccessToken),
      displayName: _prefs.getString(_kDisplayName),
    );
  }

  Future<void> signInWithGoogle() async {
    final result = await ref
        .read(authApiProvider)
        .signInWithGoogle(guestToken: state.guestToken);
    await _prefs.setString(_kAccessToken, result.accessToken);
    await _prefs.setString(_kDisplayName, result.displayName);
    state = AuthSession(
      guestToken: state.guestToken,
      accessToken: result.accessToken,
      displayName: result.displayName,
    );
  }

  Future<void> signOut() async {
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kDisplayName);
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
