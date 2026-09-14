enum UserRole { guest, member, admin }

class AuthSession {
  const AuthSession({
    required this.role,
    this.userId,
    this.displayName = 'Guest',
  });
  final UserRole role;
  final String? userId;
  final String displayName;

  bool get authenticated => role != UserRole.guest;
  bool get administrator => role == UserRole.admin;
}
