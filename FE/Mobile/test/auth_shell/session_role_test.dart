// test/auth_shell/session_role_test.dart
//
// Email + password session (P1): roles, AuthResponse parsing, the mock auth
// server's rules, the session controller and the account menu.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/onboarding_controller.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/json_helpers.dart';
import 'package:veganlife_mobile/core/widgets/account_button.dart';
import 'package:veganlife_mobile/features/auth/domain/auth_validators.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';

import '../helpers/session_helpers.dart';

Matcher _apiError(int status, String message) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.message, 'message', message);

void main() {
  setUp(() {
    MockAuthDb.reset();
    MockProfileRepository.reset();
  });

  group('UserRole.fromApi', () {
    test('reads the legacy Member, any casing and null as User', () {
      for (final value in ['Member', 'member', 'USER', 'User', null, 'Guest']) {
        expect(UserRole.fromApi(value), UserRole.user, reason: '$value');
      }
    });

    test('reads Chef and Admin case-insensitively', () {
      expect(UserRole.fromApi('Chef'), UserRole.chef);
      expect(UserRole.fromApi(' chef '), UserRole.chef);
      expect(UserRole.fromApi('admin'), UserRole.admin);
      expect(UserRole.chef.apiValue, 'Chef');
      expect(UserRole.chef.label, 'Chuyên gia');
    });
  });

  test('seeded accounts: feature-data ids, valid emails and passwords', () {
    expect(mockAccounts.map((a) => a.label),
        ['Minh Anh (Thành viên)', 'Lê Quang Tâm (Chuyên gia)']);
    expect(minhAnhAccount.userId, 'u_me');
    expect(tamChefAccount.userId, 'u_chef_tam');
    expect(tamChefAccount.role, UserRole.chef);
    for (final a in seededAccounts) {
      expect(AuthValidators.email(a.email), isNull, reason: a.email);
      expect(AuthValidators.newPassword(a.password), isNull, reason: a.email);
    }
    expect(AuthValidators.email(serverErrorEmail), isNull);
    expect(AuthValidators.resetCode(mockResetCode), isNull);
  });

  test('apiId sends numeric ids as numbers and mock ids as strings', () {
    expect(apiId('42'), 42);
    expect(apiId('svc_tam_consult'), 'svc_tam_consult');
  });

  group('AuthResult.fromJson', () {
    test('reads the AuthResponse: tokens, expiry and the user object', () {
      final chef = AuthResult.fromJson({
        'accessToken': 'jwt',
        'refreshToken': 'refresh',
        'expiresAt': '2026-10-17T10:00:00Z',
        'user': {
          'id': 12,
          'fullName': 'Lê Quang Tâm',
          'email': 'tam@x.vn',
          'role': 'Chef',
          'status': 'Active',
        },
      });
      expect(chef.userId, '12');
      expect(chef.displayName, 'Lê Quang Tâm');
      expect(chef.email, 'tam@x.vn');
      expect(chef.role, UserRole.chef);
      expect(chef.refreshToken, 'refresh');
      expect(chef.expiresAt?.toUtc(), DateTime.utc(2026, 10, 17, 10));

      final named = AuthResult.fromJson({
        'accessToken': 'jwt',
        'user': {'id': 7, 'name': 'Minh Anh', 'role': 'Member'},
      });
      expect(named.displayName, 'Minh Anh');
      expect(named.role, UserRole.user);
      expect(named.refreshToken, isNull);
      expect(named.expiresAt, isNull);
    });

    test('still reads the legacy { accessToken, displayName }', () {
      final legacy =
          AuthResult.fromJson({'accessToken': 'jwt', 'displayName': 'An'});
      expect(legacy.displayName, 'An');
      expect(legacy.userId, isNull);
      expect(legacy.role, UserRole.user);
    });

    test('RegisterRequest has no role and drops an empty phone', () {
      const request = RegisterRequest(
          fullName: 'An', email: 'an@x.vn', password: 'abc12345', phone: '');
      expect(request.toJson(),
          {'fullName': 'An', 'email': 'an@x.vn', 'password': 'abc12345'});
    });
  });

  test('server auth errors get the Vietnamese messages', () {
    String localized(int status, [String? code]) => AuthErrors.localize(
            ApiException(message: 'raw', statusCode: status, code: code))
        .message;
    expect(localized(401), 'Email hoặc mật khẩu không đúng.');
    expect(localized(401, 'invalid_credentials'),
        'Email hoặc mật khẩu không đúng.');
    expect(localized(403, 'admin_web_only'),
        'Tài khoản quản trị chỉ dùng trên web quản trị.');
    expect(localized(423), 'Tài khoản đang bị khoá. Liên hệ hỗ trợ.');
    expect(localized(429), 'Bạn thử sai quá nhiều lần. Thử lại sau 5 phút.');
    expect(localized(409, 'email_taken'),
        'Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.');
    expect(
        localized(400, 'code_expired'), 'Mã đã hết hiệu lực, hãy gửi lại mã');
    expect(localized(400, 'invalid_code'), 'Mã xác minh không đúng.');
    expect(localized(500), 'raw');
  });

  group('mock auth server', () {
    test('wrong password, locked, admin and server-error seeds', () {
      expect(() => MockAuthDb.login(minhAnhAccount.email, 'sai-mat-khau1'),
          throwsA(_apiError(401, 'Email hoặc mật khẩu không đúng.')));
      expect(() => MockAuthDb.login('khong.co@veganlife.vn', 'abc12345'),
          throwsA(_apiError(401, 'Email hoặc mật khẩu không đúng.')));
      expect(
          () => MockAuthDb.login(lockedAccount.email, lockedAccount.password),
          throwsA(_apiError(423, 'Tài khoản đang bị khoá. Liên hệ hỗ trợ.')));
      expect(
          () => MockAuthDb.login(adminAccount.email, adminAccount.password),
          throwsA(_apiError(
              403, 'Tài khoản quản trị chỉ dùng trên web quản trị.')));
      expect(
          () => MockAuthDb.login(serverErrorEmail, 'abc12345'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 503)));
    });

    test('emails are trimmed and case-insensitive', () {
      final result = MockAuthDb.login(
          '  ${tamChefAccount.email.toUpperCase()} ', tamChefAccount.password);
      expect(result.userId, 'u_chef_tam');
      expect(result.role, UserRole.chef);
      expect(result.refreshToken, isNotNull);
      expect(result.expiresAt, isNotNull);
    });

    test('five wrong passwords lock the email for 5 minutes', () {
      var now = DateTime(2026, 10, 17, 9);
      MockAuthDb.clock = () => now;
      for (var i = 0; i < 4; i++) {
        expect(() => MockAuthDb.login(minhAnhAccount.email, 'sai$i-matkhau'),
            throwsA(_apiError(401, 'Email hoặc mật khẩu không đúng.')));
      }
      const locked = 'Bạn thử sai quá nhiều lần. Thử lại sau 5 phút.';
      expect(() => MockAuthDb.login(minhAnhAccount.email, 'sai4-matkhau'),
          throwsA(_apiError(429, locked)));
      // Even the right password waits.
      expect(
          () => MockAuthDb.login(minhAnhAccount.email, minhAnhAccount.password),
          throwsA(_apiError(429, locked)));
      // Other emails are not affected.
      expect(MockAuthDb.login(tamChefAccount.email, tamChefAccount.password),
          isA<AuthResult>());

      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(
          MockAuthDb.login(minhAnhAccount.email, minhAnhAccount.password)
              .userId,
          'u_me');
    });

    test('register: always a member, can sign in, a used email is 409', () {
      final created = MockAuthDb.register(const RegisterRequest(
          fullName: 'Ngô Thảo',
          email: 'thao.ngo@gmail.com',
          password: 'thao2026x',
          phone: '0987654321'));
      expect(created.role, UserRole.user);
      expect(created.displayName, 'Ngô Thảo');
      expect(MockAuthDb.byId(created.userId!)?.phone, '0987654321');
      expect(MockAuthDb.login('thao.ngo@gmail.com', 'thao2026x').userId,
          created.userId);

      const taken =
          'Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.';
      for (final email in [
        minhAnhAccount.email,
        ' THAO.NGO@gmail.com',
        adminAccount.email
      ]) {
        expect(
            () => MockAuthDb.register(RegisterRequest(
                fullName: 'Ai đó', email: email, password: 'abc12345')),
            throwsA(_apiError(409, taken)),
            reason: email);
      }
    });

    test('forgot password: code, 3 wrong tries, resend, new password', () {
      expect(MockAuthDb.requestReset('khong.co@veganlife.vn'), isNull);
      expect(MockAuthDb.requestReset(minhAnhAccount.email), mockResetCode);

      expect(
          () => MockAuthDb.verifyCode(minhAnhAccount.email, '000000'),
          throwsA(
              _apiError(400, 'Mã xác minh không đúng. Bạn còn 2 lần thử.')));
      expect(
          () => MockAuthDb.verifyCode(minhAnhAccount.email, '000001'),
          throwsA(
              _apiError(400, 'Mã xác minh không đúng. Bạn còn 1 lần thử.')));
      const expired = 'Mã đã hết hiệu lực, hãy gửi lại mã';
      expect(() => MockAuthDb.verifyCode(minhAnhAccount.email, '000002'),
          throwsA(_apiError(400, expired)));
      // Dead now, even with the right code.
      expect(() => MockAuthDb.verifyCode(minhAnhAccount.email, mockResetCode),
          throwsA(_apiError(400, expired)));

      MockAuthDb.requestReset(minhAnhAccount.email);
      final token = MockAuthDb.verifyCode(minhAnhAccount.email, mockResetCode);
      MockAuthDb.resetPassword(token, 'moi2026abc');
      expect(() => MockAuthDb.resetPassword(token, 'lan2nua2026'),
          throwsA(isA<ApiException>()),
          reason: 'a reset token works once');

      expect(
          MockAuthDb.login(minhAnhAccount.email, 'moi2026abc').userId, 'u_me');
      expect(
          () => MockAuthDb.login(minhAnhAccount.email, minhAnhAccount.password),
          throwsA(_apiError(401, 'Email hoặc mật khẩu không đúng.')));
    });

    test('a reset code lasts 10 minutes', () {
      var now = DateTime(2026, 10, 17, 9);
      MockAuthDb.clock = () => now;
      MockAuthDb.requestReset(tamChefAccount.email);
      now = now.add(const Duration(minutes: 10));
      expect(() => MockAuthDb.verifyCode(tamChefAccount.email, mockResetCode),
          throwsA(_apiError(400, 'Mã đã hết hiệu lực, hãy gửi lại mã')));
    });
  });

  group('SessionController', () {
    Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final instance = await SharedPreferences.getInstance();
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(instance)]);
      addTearDown(container.dispose);
      return container;
    }

    test('signs Minh Anh in with email + password; tokens are kept', () async {
      final container = await containerWith({});
      expect(container.read(onboardingProvider), isFalse);
      await signInAs(container, minhAnhAccount);
      final session = container.read(sessionControllerProvider);
      expect(session.isGuest, isFalse);
      expect(session.displayName, 'Minh Anh');
      expect(session.userId, 'u_me');
      expect(session.role, UserRole.user);
      expect(session.isChef, isFalse);

      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString('vl.access_token'), session.accessToken);
      expect(prefs.getString('vl.refresh_token'), startsWith('mock.refresh.'));
      expect(DateTime.tryParse(prefs.getString('vl.expires_at')!), isNotNull);
      expect(prefs.getBool('vl.onboarded'), isTrue);
      expect(container.read(onboardingProvider), isTrue);
    });

    test('a failed sign-in throws the message and stays a guest', () async {
      final container = await containerWith({});
      await expectLater(
          container
              .read(sessionControllerProvider.notifier)
              .signIn(email: tamChefAccount.email, password: 'sai2026abc'),
          throwsA(_apiError(401, 'Email hoặc mật khẩu không đúng.')));
      expect(container.read(sessionControllerProvider).isGuest, isTrue);
      expect(
          container
              .read(sharedPreferencesProvider)
              .getString('vl.access_token'),
          isNull);
    });

    test('the chef account survives a restart; sign-out clears it', () async {
      final container = await containerWith({});
      await signInAs(container, tamChefAccount);
      expect(container.read(sessionControllerProvider).isChef, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vl.user_id'), 'u_chef_tam');
      expect(prefs.getString('vl.role'), 'Chef');

      // A new container reads the same prefs, like an app restart.
      final restarted = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(restarted.dispose);
      final restored = restarted.read(sessionControllerProvider);
      expect(restored.displayName, 'Lê Quang Tâm');
      expect(restored.userId, 'u_chef_tam');
      expect(restored.role, UserRole.chef);

      await restarted.read(sessionControllerProvider.notifier).signOut();
      final guest = restarted.read(sessionControllerProvider);
      expect(guest.isGuest, isTrue);
      expect(guest.userId, isNull);
      expect(guest.isChef, isFalse);
      for (final key in [
        'vl.access_token',
        'vl.refresh_token',
        'vl.expires_at',
        'vl.display_name',
        'vl.user_id',
        'vl.role'
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getString('vl.guest_token'), restored.guestToken);
      // Signed out → Trang chủ as a guest, never the Welcome screen.
      expect(restarted.read(onboardingProvider), isTrue);
    });

    test('a mock session saved before accounts existed is Minh Anh', () async {
      final container = await containerWith(
          {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'});
      final session = container.read(sessionControllerProvider);
      expect(session.userId, 'u_me');
      expect(session.role, UserRole.user);
      // Already signed in: no Welcome screen.
      expect(container.read(onboardingProvider), isTrue);
    });

    test(
        'register signs in a member (also when "Chuyên gia" was picked); '
        'GET /users/me knows the new account', () async {
      final container = await containerWith({});
      final result = await container
          .read(sessionControllerProvider.notifier)
          .register(const RegisterRequest(
              fullName: 'Đỗ Gia Huy',
              email: 'giahuy.do@gmail.com',
              password: 'giahuy2026',
              phone: '0901234567'));
      final session = container.read(sessionControllerProvider);
      expect(session.isGuest, isFalse);
      expect(session.userId, result.userId);
      expect(session.role, UserRole.user);
      expect(session.displayName, 'Đỗ Gia Huy');

      final me = (await container.read(profileApiProvider).getMe()).toEntity();
      expect(me.id, result.userId);
      expect(me.fullName, 'Đỗ Gia Huy');
      expect(me.email, 'giahuy.do@gmail.com');
      expect(me.phone, '0901234567');
      expect(me.role, UserRole.user);
      expect(me.signedInWithGoogle, isFalse);
      expect(me.postCount, 0);

      // The new account signs in again after signing out.
      await container.read(sessionControllerProvider.notifier).signOut();
      await container
          .read(sessionControllerProvider.notifier)
          .signIn(email: 'giahuy.do@gmail.com', password: 'giahuy2026');
      expect(container.read(sessionControllerProvider).userId, result.userId);
    });

    test('seeded profiles sign in with email (no Google badge)', () async {
      final container = await containerWith({});
      await signInAs(container, minhAnhAccount);
      final me = (await container.read(profileApiProvider).getMe()).toEntity();
      expect(me.email, minhAnhAccount.email);
      expect(me.signedInWithGoogle, isFalse);
    });
  });

  group('account menu', () {
    Future<SharedPreferences> pumpMenu(WidgetTester tester,
        [Map<String, Object> prefs = const {}]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [AccountButton()])),
        ),
      ));
      return sp;
    }

    testWidgets('guest: "Đăng nhập" and "Tạo tài khoản", no Google',
        (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập'), findsOneWidget);
      expect(find.text('Tạo tài khoản'), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);

      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signed in from the menu: "Xin chào, …" then "Đăng xuất"',
        (tester) async {
      final prefs = await pumpMenu(tester);
      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email'), tamChefAccount.email);
      await tester.enterText(find.widgetWithText(TextFormField, 'Mật khẩu'),
          tamChefAccount.password);
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump(const Duration(seconds: 2)); // mock latency
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(prefs.getString('vl.role'), 'Chef');

      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      expect(find.text('Xin chào, Lê Quang Tâm'), findsOneWidget);
      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(prefs.containsKey('vl.access_token'), isFalse);
    });
  });
}
