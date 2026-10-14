// lib/core/session/auth_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../network/api_endpoints.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';
import '../utils/mock_delay.dart';

class AuthResult {
  const AuthResult({required this.accessToken, required this.displayName});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        accessToken: json['access_token'] as String,
        displayName: (json['display_name'] as String?) ?? 'Bạn',
      );

  final String accessToken;
  final String displayName;
}

abstract interface class AuthApiService {
  /// Signs in with Google. [guestToken] lets the server merge guest data
  /// (free chat history, saved recipes) into the new account.
  Future<AuthResult> signInWithGoogle({required String guestToken});
}

class RemoteAuthApiService implements AuthApiService {
  RemoteAuthApiService(this._dio);

  final Dio _dio;

  @override
  Future<AuthResult> signInWithGoogle({required String guestToken}) async {
    // TODO(auth): obtain a Google ID token with `package:google_sign_in`
    // (or Firebase/Supabase Auth) and pass it to [exchangeGoogleIdToken].
    throw const ApiException(
      message: 'Đăng nhập Google chưa được cấu hình cho bản build này.',
      code: 'not_configured',
    );
  }

  /// POST /auth/google { id_token, guest_token } → { access_token, display_name }
  Future<AuthResult> exchangeGoogleIdToken({
    required String idToken,
    required String guestToken,
  }) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authGoogle,
          data: {'id_token': idToken, 'guest_token': guestToken},
        );
        return AuthResult.fromJson(res.data!);
      });
}

class MockAuthApiService implements AuthApiService {
  @override
  Future<AuthResult> signInWithGoogle({required String guestToken}) async {
    await mockDelay(900);
    return AuthResult(
      accessToken: 'mock.jwt.${DateTime.now().millisecondsSinceEpoch}',
      displayName: 'Bạn',
    );
  }
}

final authApiProvider = Provider<AuthApiService>((ref) {
  if (Env.useMockData) return MockAuthApiService();
  return RemoteAuthApiService(ref.watch(dioProvider));
});
