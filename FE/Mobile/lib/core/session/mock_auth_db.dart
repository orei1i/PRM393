// lib/core/session/mock_auth_db.dart
import 'package:flutter/foundation.dart';

import '../network/api_exception.dart';
import 'auth_api_service.dart';
import 'mock_accounts.dart';
import 'user_role.dart';

/// A user row of the mock auth server.
class MockUserRecord {
  MockUserRecord({
    required this.id,
    required this.fullName,
    required this.email,
    required this.password,
    required this.role,
    required this.phone,
    required this.createdAt,
    this.locked = false,
  });

  final String id;
  String fullName;
  final String email;
  String password;
  final UserRole role;
  final String phone;
  final String createdAt;
  final bool locked;
}

class _ResetCode {
  _ResetCode(this.code, this.expiresAt);

  final String code;
  final DateTime expiresAt;
  int attempts = 0;
}

/// In-memory auth server for mock builds: the seeded accounts of
/// `mock_accounts.dart` plus the ones registered in this run (lost on
/// restart, like every mock). Mirrors the BE rules: 5 wrong passwords → 429
/// for 5 minutes; reset codes last 10 minutes and 3 tries.
abstract final class MockAuthDb {
  static const maxFailures = 5;
  static const lockout = Duration(minutes: 5);
  static const codeLifetime = Duration(minutes: 10);
  static const maxCodeAttempts = 3;

  /// Moved by tests to expire codes and lockouts.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static final Map<String, MockUserRecord> _users = {};
  static final Map<String, int> _failures = {};
  static final Map<String, DateTime> _lockedUntil = {};
  static final Map<String, _ResetCode> _codes = {};
  static final Map<String, String> _resetTokens = {};
  static int _seq = 0;

  @visibleForTesting
  static void reset() {
    _users.clear();
    _failures.clear();
    _lockedUntil.clear();
    _codes.clear();
    _resetTokens.clear();
    _seq = 0;
    clock = DateTime.now;
  }

  static String _key(String email) => email.trim().toLowerCase();

  static Map<String, MockUserRecord> get _db {
    if (_users.isEmpty) {
      for (final a in seededAccounts) {
        _users[_key(a.email)] = MockUserRecord(
          id: a.userId,
          fullName: a.displayName,
          email: a.email,
          password: a.password,
          role: a.role,
          phone: a.phone,
          createdAt: a.createdAt,
          locked: a.status == MockAccountStatus.locked,
        );
      }
    }
    return _users;
  }

  /// The user behind a session's `userId` (seeded or registered).
  static MockUserRecord? byId(String id) {
    for (final u in _db.values) {
      if (u.id == id) return u;
    }
    return null;
  }

  static AuthResult _session(MockUserRecord u) {
    final now = clock();
    return AuthResult(
      accessToken: 'mock.jwt.${u.id}.${now.microsecondsSinceEpoch}',
      refreshToken: 'mock.refresh.${u.id}.${now.microsecondsSinceEpoch}',
      expiresAt: now.toUtc().add(const Duration(hours: 1)),
      displayName: u.fullName,
      userId: u.id,
      email: u.email,
      role: u.role,
    );
  }

  static AuthResult login(String email, String password) {
    final key = _key(email);
    if (key == serverErrorEmail) {
      throw const ApiException(
          message: 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.',
          statusCode: 503);
    }
    final until = _lockedUntil[key];
    if (until != null && clock().isBefore(until)) {
      throw const ApiException(
          message: AuthErrors.tooManyAttempts,
          statusCode: 429,
          code: 'too_many_attempts');
    }
    final user = _db[key];
    if (user == null || user.password != password) {
      final failures = (_failures[key] ?? 0) + 1;
      _failures[key] = failures;
      if (failures >= maxFailures) {
        _failures.remove(key);
        _lockedUntil[key] = clock().add(lockout);
        throw const ApiException(
            message: AuthErrors.tooManyAttempts,
            statusCode: 429,
            code: 'too_many_attempts');
      }
      throw const ApiException(
          message: AuthErrors.invalidCredentials,
          statusCode: 401,
          code: 'invalid_credentials');
    }
    _failures.remove(key);
    _lockedUntil.remove(key);
    if (user.locked) {
      throw const ApiException(
          message: AuthErrors.accountLocked,
          statusCode: 423,
          code: 'account_locked');
    }
    if (user.role == UserRole.admin) {
      throw const ApiException(
          message: AuthErrors.adminWebOnly,
          statusCode: 403,
          code: 'admin_web_only');
    }
    return _session(user);
  }

  /// Always role User, whatever the screen's "Bạn là" choice.
  static AuthResult register(RegisterRequest request) {
    final key = _key(request.email);
    if (_db.containsKey(key) || key == serverErrorEmail) {
      throw const ApiException(
          message: AuthErrors.emailTaken, statusCode: 409, code: 'email_taken');
    }
    final user = MockUserRecord(
      id: 'u_reg_${++_seq}_${clock().millisecondsSinceEpoch}',
      fullName: request.fullName.trim(),
      email: request.email.trim(),
      password: request.password,
      role: UserRole.user,
      phone: request.phone ?? '',
      createdAt: clock().toUtc().toIso8601String(),
    );
    _db[key] = user;
    return _session(user);
  }

  /// "Sends" a code when the email is registered and returns it (null
  /// otherwise; the screen says the same thing either way).
  static String? requestReset(String email) {
    final key = _key(email);
    if (!_db.containsKey(key)) return null;
    _codes[key] = _ResetCode(mockResetCode, clock().add(codeLifetime));
    return mockResetCode;
  }

  static String verifyCode(String email, String code) {
    final key = _key(email);
    final entry = _codes[key];
    if (entry == null || !clock().isBefore(entry.expiresAt)) {
      _codes.remove(key);
      throw const ApiException(
          message: AuthErrors.codeExpired,
          statusCode: 400,
          code: 'code_expired');
    }
    if (entry.code != code.trim()) {
      entry.attempts++;
      final left = maxCodeAttempts - entry.attempts;
      if (left <= 0) {
        _codes.remove(key);
        throw const ApiException(
            message: AuthErrors.codeExpired,
            statusCode: 400,
            code: 'code_expired');
      }
      throw ApiException(
          message: '${AuthErrors.invalidCode} Bạn còn $left lần thử.',
          statusCode: 400,
          code: 'invalid_code');
    }
    _codes.remove(key);
    final token = 'mock.reset.$key.${clock().microsecondsSinceEpoch}';
    _resetTokens[token] = key;
    return token;
  }

  static void resetPassword(String resetToken, String newPassword) {
    final key = _resetTokens.remove(resetToken);
    final user = key == null ? null : _db[key];
    if (user == null) {
      throw const ApiException(
          message: AuthErrors.codeExpired,
          statusCode: 400,
          code: 'code_expired');
    }
    user.password = newPassword;
    _failures.remove(key);
    _lockedUntil.remove(key);
  }
}
