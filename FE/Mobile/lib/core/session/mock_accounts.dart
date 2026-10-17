// lib/core/session/mock_accounts.dart
import 'user_role.dart';

/// Whether the mock auth server lets the account in.
enum MockAccountStatus { active, locked }

/// A seeded login of the mock auth server ([MockAuthDb]). The ids match the
/// authors and chef profiles in the feature mock data.
///
/// Test accounts (mock builds only; mirrored in the Mobile README table
/// "Tài khoản thử nghiệm"). The passwords below are the single source:
///
/// | Account            | Email                      | Result                     |
/// |--------------------|----------------------------|----------------------------|
/// | [minhAnhAccount]   | minhanh.nguyen@gmail.com   | member Minh Anh            |
/// | [tamChefAccount]   | tam.chefchay@gmail.com     | verified chef Lê Quang Tâm |
/// | [lockedAccount]    | baokhoa.tran@gmail.com     | 423 "đang bị khoá"         |
/// | [adminAccount]     | admin@veganlife.vn         | 403 "web quản trị"         |
/// | [serverErrorEmail] | loi.maychu@veganlife.vn    | 503, any password          |
///
/// Five wrong passwords in a row for one email → 429 for 5 minutes. The
/// password-reset code of the mock is [mockResetCode] (shown on screen).
class MockAccount {
  const MockAccount({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.password,
    required this.role,
    this.phone = '',
    this.createdAt = '2026-07-02T08:15:00Z',
    this.status = MockAccountStatus.active,
  });

  final String userId;
  final String displayName;
  final String email;

  /// Mock builds only. Never logged or shown outside the test-account chips.
  final String password;
  final UserRole role;
  final String phone;
  final String createdAt;
  final MockAccountStatus status;

  /// "Minh Anh (Thành viên)".
  String get label => '$displayName (${role.label})';
}

/// Member persona (the default author in the community mock data).
const minhAnhAccount = MockAccount(
  userId: 'u_me',
  displayName: 'Minh Anh',
  email: 'minhanh.nguyen@gmail.com',
  password: 'minhanh2026',
  role: UserRole.user,
  phone: '0912345678',
);

/// Verified chef: owns the chef-studio seeds.
const tamChefAccount = MockAccount(
  userId: 'u_chef_tam',
  displayName: 'Lê Quang Tâm',
  email: 'tam.chefchay@gmail.com',
  password: 'chefTam2026',
  role: UserRole.chef,
  phone: '0903456789',
  createdAt: '2025-11-20T03:00:00Z',
);

/// Suspended member: right password → 423 "Tài khoản đang bị khoá…".
const lockedAccount = MockAccount(
  userId: 'u_locked',
  displayName: 'Trần Bảo Khoa',
  email: 'baokhoa.tran@gmail.com',
  password: 'baokhoa2026',
  role: UserRole.user,
  status: MockAccountStatus.locked,
);

/// Admin: right password → 403 "Tài khoản quản trị chỉ dùng trên web…".
const adminAccount = MockAccount(
  userId: 'u_admin',
  displayName: 'Quản trị VeganLife',
  email: 'admin@veganlife.vn',
  password: 'admin2026',
  role: UserRole.admin,
);

/// Any password → 503, to try the server-error state.
const serverErrorEmail = 'loi.maychu@veganlife.vn';

/// Code the mock "sends" for "Quên mật khẩu" (the screen shows it).
const mockResetCode = '246810';

/// The two personas testers switch between ("Điền tài khoản thử nghiệm").
const mockAccounts = [minhAnhAccount, tamChefAccount];

/// Every seeded login, error cases included.
const seededAccounts = [
  minhAnhAccount,
  tamChefAccount,
  lockedAccount,
  adminAccount,
];
