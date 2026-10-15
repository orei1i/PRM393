// lib/core/session/auth_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../network/api_endpoints.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';
import '../utils/json_helpers.dart';
import '../utils/mock_delay.dart';
import 'mock_accounts.dart';
import 'user_role.dart';

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.displayName,
    this.userId,
    this.role = UserRole.user,
  });

  /// `{ accessToken, user: { id, fullName | name, email, role } }`, or the
  /// legacy `{ accessToken, displayName }`.
  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final user = readMap(json['user']);
    return AuthResult(
      accessToken: json['accessToken'] as String,
      displayName: (user['fullName'] ?? user['name'] ?? json['displayName'])
              as String? ??
          'Bạn',
      userId: user['id']?.toString(),
      role: UserRole.fromApi(user['role'] ?? json['role']),
    );
  }

  final String accessToken;
  final String displayName;
  final String? userId;
  final UserRole role;
}

abstract interface class AuthApiService {
  /// Signs in with Google. [guestToken] lets the server merge guest data
  /// (free chat history, saved recipes) into the new account.
  ///
  /// [account] is the identity picked in the mock account picker; the real
  /// service ignores it (Google decides who signs in).
  Future<AuthResult> signInWithGoogle({
    required String guestToken,
    MockAccount? account,
  });
}

class RemoteAuthApiService implements AuthApiService {
  RemoteAuthApiService(this._dio);

  final Dio _dio;

  @override
  Future<AuthResult> signInWithGoogle({
    required String guestToken,
    MockAccount? account,
  }) async {
    // TODO(auth): obtain a Google ID token with `package:google_sign_in`
    // (or Firebase/Supabase Auth) and pass it to [exchangeGoogleIdToken].
    throw const ApiException(
      message: 'Đăng nhập Google chưa được cấu hình cho bản build này.',
      code: 'not_configured',
    );
  }

  /// POST /auth/google { idToken, guestToken } → { accessToken, user }
  Future<AuthResult> exchangeGoogleIdToken({
    required String idToken,
    required String guestToken,
  }) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authGoogle,
          data: {'idToken': idToken, 'guestToken': guestToken},
        );
        return AuthResult.fromJson(res.data!);
      });
}

class MockAuthApiService implements AuthApiService {
  @override
  Future<AuthResult> signInWithGoogle({
    required String guestToken,
    MockAccount? account,
  }) async {
    await mockDelay(900);
    final picked = account ?? minhAnhAccount;
    return AuthResult(
      accessToken: 'mock.jwt.${DateTime.now().millisecondsSinceEpoch}',
      displayName: picked.displayName,
      userId: picked.userId,
      role: picked.role,
    );
  }
}

final authApiProvider = Provider<AuthApiService>((ref) {
  if (Env.useMockData) return MockAuthApiService();
  return RemoteAuthApiService(ref.watch(dioProvider));
});
