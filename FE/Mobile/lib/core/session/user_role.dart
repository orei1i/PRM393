// lib/core/session/user_role.dart

/// `users.role` on the backend. Wire values are exactly [apiValue].
enum UserRole {
  admin('Admin', 'Quản trị viên'),
  user('User', 'Thành viên'),
  chef('Chef', 'Chuyên gia');

  const UserRole(this.apiValue, this.label);

  final String apiValue;

  /// Vietnamese label for tags and menus.
  final String label;

  /// Case-insensitive. The legacy `Member` (the BE entity's old default),
  /// unknown values and null all read as [user].
  static UserRole fromApi(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    for (final role in values) {
      if (role.apiValue.toLowerCase() == raw) return role;
    }
    return user;
  }
}
