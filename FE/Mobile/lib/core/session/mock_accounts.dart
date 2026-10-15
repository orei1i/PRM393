// lib/core/session/mock_accounts.dart
import 'user_role.dart';

/// A demo identity offered by the mock "Tiếp tục với Google" picker. The ids
/// match the authors and chef profiles in the feature mock data.
class MockAccount {
  const MockAccount({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String email;
  final UserRole role;

  /// "Minh Anh (Thành viên)".
  String get label => '$displayName (${role.label})';
}

/// Signed in by default (`signInWithGoogle()` without an account).
const minhAnhAccount = MockAccount(
  userId: 'u_me',
  displayName: 'Minh Anh',
  email: 'minhanh.nguyen@gmail.com',
  role: UserRole.user,
);

/// Verified chef: owns the chef-studio seeds.
const tamChefAccount = MockAccount(
  userId: 'u_chef_tam',
  displayName: 'Lê Quang Tâm',
  email: 'tam.chefchay@gmail.com',
  role: UserRole.chef,
);

const mockAccounts = [minhAnhAccount, tamChefAccount];
