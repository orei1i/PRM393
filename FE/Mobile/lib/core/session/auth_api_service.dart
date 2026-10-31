// lib/core/session/auth_api_service.dart
//
// Email + password auth. JSON (camelCase of the SQL `users` columns):
//
// POST /auth/login    { "email": "…", "password": "…" }
// POST /auth/register { "fullName": "Minh Anh", "email": "…", "password": "…",
//                       "phone": "0912345678" }            // phone optional
// → 200 AuthResponse
// { "accessToken": "…", "refreshToken": "…", "expiresAt": "2026-10-17T10:00:00Z",
//   "user": { "id": 1, "fullName": "Minh Anh", "email": "…", "role": "User",
//             "status": "Active" } }
// errors: 401 invalid_credentials, 403 admin_web_only, 423 account_locked,
//         409 email_taken, 429 too_many_attempts
//
// POST /auth/forgot-password   { "email" }                → 204 (always)
// POST /auth/verify-reset-code { "email", "code" }        → { "resetToken" }
// POST /auth/reset-password    { "resetToken", "newPassword" } → 204
// errors: 400 invalid_code / code_expired (the real BE sends these in
//         `message`, with no `code` field)
//
// Register always creates role `User`: a chef is approved later by an admin
// (chef application). Guest data is merged through the `X-Guest-Token`
// header the auth interceptor sends on these (guest) requests.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/backend_modules.dart';
import '../network/api_endpoints.dart';
import '../network/api_exception.dart';
import '../network/dio_client.dart';
import '../utils/json_helpers.dart';
import '../utils/mock_delay.dart';
import 'mock_auth_db.dart';
import 'user_role.dart';

class AuthResult {
  const AuthResult({
    required this.accessToken,
    required this.displayName,
    this.refreshToken,
    this.expiresAt,
    this.userId,
    this.email,
    this.role = UserRole.user,
  });

  /// `AuthResponse { accessToken, refreshToken, expiresAt, user: { id,
  /// fullName | name, email, role } }`, or the legacy
  /// `{ accessToken, displayName }`.
  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final user = readMap(json['user']);
    return AuthResult(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: readDateTime(json['expiresAt']),
      displayName: (user['fullName'] ?? user['name'] ?? json['displayName'])
              as String? ??
          'Bạn',
      userId: user['id']?.toString(),
      email: user['email'] as String?,
      role: UserRole.fromApi(user['role'] ?? json['role']),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final String displayName;
  final String? userId;
  final String? email;
  final UserRole role;
}

/// POST /auth/register. There is no role field on purpose.
class RegisterRequest {
  const RegisterRequest({
    required this.fullName,
    required this.email,
    required this.password,
    this.phone,
  });

  final String fullName;
  final String email;
  final String password;
  final String? phone;

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'email': email,
        'password': password,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
      };
}

/// Vietnamese messages for the auth error codes (see the file header).
abstract final class AuthErrors {
  static const invalidCredentials = 'Email hoặc mật khẩu không đúng.';
  static const accountLocked = 'Tài khoản đang bị khoá. Liên hệ hỗ trợ.';
  static const adminWebOnly = 'Tài khoản quản trị chỉ dùng trên web quản trị.';
  static const tooManyAttempts =
      'Bạn thử sai quá nhiều lần. Thử lại sau 5 phút.';
  static const emailTaken =
      'Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.';
  static const invalidCode = 'Mã xác minh không đúng.';
  static const codeExpired = 'Mã đã hết hiệu lực, hãy gửi lại mã';
  static const sessionExpired =
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';

  /// Maps a server error of an auth endpoint to the message above (by `code`,
  /// or a code sent as `message`, else by status); other errors are returned
  /// unchanged. A code found in `message` becomes the result's `code`.
  static ApiException localize(ApiException e) {
    final key = e.code ?? e.message;
    final byCode = switch (key) {
      'invalid_credentials' => invalidCredentials,
      'admin_web_only' => adminWebOnly,
      'account_locked' => accountLocked,
      'too_many_attempts' => tooManyAttempts,
      'email_taken' => emailTaken,
      'code_expired' => codeExpired,
      'invalid_code' => invalidCode,
      _ => null,
    };
    if (byCode != null) {
      return ApiException(message: byCode, statusCode: e.statusCode, code: key);
    }
    final byStatus = e.code != null
        ? null
        : switch (e.statusCode) {
            401 => invalidCredentials,
            403 => adminWebOnly,
            423 => accountLocked,
            429 => tooManyAttempts,
            409 => emailTaken,
            _ => null,
          };
    return byStatus == null
        ? e
        : ApiException(message: byStatus, statusCode: e.statusCode);
  }
}

abstract interface class AuthApiService {
  Future<AuthResult> login({required String email, required String password});

  Future<AuthResult> register(RegisterRequest request);

  /// Always succeeds (no hint whether the email is registered). Mock builds
  /// return the code they "sent", so testers can read it on screen; the real
  /// service returns null.
  Future<String?> requestPasswordReset(String email);

  /// → the reset token for [resetPassword].
  Future<String> verifyResetCode({required String email, required String code});

  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  });
}

class RemoteAuthApiService implements AuthApiService {
  RemoteAuthApiService(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await guardApi(call);
    } on ApiException catch (e) {
      throw AuthErrors.localize(e);
    }
  }

  @override
  Future<AuthResult> login({required String email, required String password}) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authLogin,
          data: {'email': email, 'password': password},
        );
        return AuthResult.fromJson(res.data!);
      });

  @override
  Future<AuthResult> register(RegisterRequest request) => _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authRegister,
          data: request.toJson(),
        );
        return AuthResult.fromJson(res.data!);
      });

  @override
  Future<String?> requestPasswordReset(String email) => _call(() async {
        await _dio.post<void>(ApiEndpoints.authForgotPassword,
            data: {'email': email});
        return null;
      });

  @override
  Future<String> verifyResetCode(
          {required String email, required String code}) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.authVerifyResetCode,
          data: {'email': email, 'code': code},
        );
        return res.data!['resetToken'] as String;
      });

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) =>
      _call(() async {
        await _dio.post<void>(
          ApiEndpoints.authResetPassword,
          data: {'resetToken': resetToken, 'newPassword': newPassword},
        );
      });
}

/// In-memory server: see [MockAuthDb] and the seeds in `mock_accounts.dart`.
class MockAuthApiService implements AuthApiService {
  @override
  Future<AuthResult> login(
      {required String email, required String password}) async {
    await mockDelay(600);
    return MockAuthDb.login(email, password);
  }

  @override
  Future<AuthResult> register(RegisterRequest request) async {
    await mockDelay(700);
    return MockAuthDb.register(request);
  }

  @override
  Future<String?> requestPasswordReset(String email) async {
    await mockDelay(500);
    return MockAuthDb.requestReset(email);
  }

  @override
  Future<String> verifyResetCode(
      {required String email, required String code}) async {
    await mockDelay(500);
    return MockAuthDb.verifyCode(email, code);
  }

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    await mockDelay(500);
    MockAuthDb.resetPassword(resetToken, newPassword);
  }
}

final authApiProvider = Provider<AuthApiService>((ref) {
  if (BackendModules.isMock(BackendModule.auth)) return MockAuthApiService();
  return RemoteAuthApiService(ref.watch(dioProvider));
});
