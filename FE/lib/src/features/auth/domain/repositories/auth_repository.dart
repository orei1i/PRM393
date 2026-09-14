import '../entities/auth_session.dart';

abstract interface class AuthRepository {
  AuthSession get session;
  AuthSession signInDemo(UserRole role);
  void signOut();
}
