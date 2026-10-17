// lib/features/auth/domain/auth_validators.dart

/// Form rules of Đăng nhập / Tạo tài khoản / Quên mật khẩu (same as the
/// BE `RegisterRequest` / `ResetPasswordRequest` validation).
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _phone = RegExp(r'^(0|\+84)\d{9}$');
  static final _letter = RegExp(r'\p{L}', unicode: true);
  static final _digit = RegExp(r'\d');

  static const passwordRule = 'Mật khẩu cần ít nhất 8 ký tự, gồm chữ và số';

  static String? email(String? value) =>
      _email.hasMatch((value ?? '').trim()) ? null : 'Email không hợp lệ';

  /// Sign-in only checks presence; the server decides the rest.
  static String? loginPassword(String? value) =>
      (value ?? '').isEmpty ? 'Nhập mật khẩu' : null;

  static String? newPassword(String? value) {
    final p = value ?? '';
    return p.length >= 8 && _letter.hasMatch(p) && _digit.hasMatch(p)
        ? null
        : passwordRule;
  }

  static String? confirmPassword(String? value, String password) =>
      value == password ? null : 'Mật khẩu nhập lại không khớp';

  static String? fullName(String? value) {
    final n = (value ?? '').trim().length;
    return n < 2 || n > 100 ? 'Họ và tên cần từ 2 đến 100 ký tự' : null;
  }

  /// Optional: empty is fine.
  static String? phone(String? value) {
    final p = (value ?? '').replaceAll(' ', '');
    if (p.isEmpty) return null;
    return _phone.hasMatch(p) ? null : 'Số điện thoại không hợp lệ';
  }

  static String? resetCode(String? value) =>
      RegExp(r'^\d{6}$').hasMatch((value ?? '').trim())
          ? null
          : 'Mã gồm 6 chữ số';

  /// "minhanh@gmail.com" → "m•••@gmail.com".
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return '${email[0]}•••${email.substring(at)}';
  }
}
