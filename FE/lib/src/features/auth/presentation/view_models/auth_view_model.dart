import '../../../../core/state/view_model.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthViewModel extends ViewModel {
  AuthViewModel(this._repository);
  final AuthRepository _repository;

  AuthSession get session => _repository.session;
  UserRole get role => session.role;
  bool get isGuest => role == UserRole.guest;
  bool get isAdmin => session.administrator;
  bool get canParticipate => session.authenticated;
  String? get userId => session.userId;
  String get name => session.displayName;
  String get homeRoute => isAdmin
      ? '/admin'
      : isGuest
      ? '/explore'
      : '/community';

  void switchRole(UserRole role) {
    if (role == this.role) return;
    _repository.signInDemo(role);
    emit();
  }

  void signInAsMember() => switchRole(UserRole.member);
  void signOut() => switchRole(UserRole.guest);
}
