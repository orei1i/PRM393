import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  AuthSession _session = const AuthSession(role: UserRole.guest);
  @override
  AuthSession get session => _session;

  @override
  AuthSession signInDemo(UserRole role) {
    _session = switch (role) {
      UserRole.guest => const AuthSession(role: UserRole.guest),
      UserRole.member => const AuthSession(
        role: UserRole.member,
        userId: AppConstants.memberId,
        displayName: AppConstants.memberName,
      ),
      UserRole.admin => const AuthSession(
        role: UserRole.admin,
        userId: 'admin-demo',
        displayName: 'VeganLife Admin',
      ),
    };
    return _session;
  }

  @override
  void signOut() => _session = const AuthSession(role: UserRole.guest);
}
