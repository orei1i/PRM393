// test/m0_session_role_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/json_helpers.dart';
import 'package:veganlife_mobile/core/widgets/account_button.dart';
import 'package:veganlife_mobile/core/widgets/google_sign_in_button.dart';

void main() {
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

  test('mock accounts carry the ids used by the feature mock data', () {
    expect(mockAccounts.map((a) => a.label),
        ['Minh Anh (Thành viên)', 'Lê Quang Tâm (Chuyên gia)']);
    expect(minhAnhAccount.userId, 'u_me');
    expect(tamChefAccount.userId, 'u_chef_tam');
    expect(tamChefAccount.email, 'tam.chefchay@gmail.com');
  });

  test('apiId sends numeric ids as numbers and mock ids as strings', () {
    expect(apiId('42'), 42);
    expect(apiId('svc_tam_consult'), 'svc_tam_consult');
  });

  group('AuthResult.fromJson', () {
    test('reads the user object (fullName or name)', () {
      final chef = AuthResult.fromJson({
        'accessToken': 'jwt',
        'user': {
          'id': 12,
          'fullName': 'Lê Quang Tâm',
          'email': 'tam@x.vn',
          'role': 'Chef',
        },
      });
      expect(chef.userId, '12');
      expect(chef.displayName, 'Lê Quang Tâm');
      expect(chef.role, UserRole.chef);

      final named = AuthResult.fromJson({
        'accessToken': 'jwt',
        'user': {'id': 7, 'name': 'Minh Anh', 'role': 'Member'},
      });
      expect(named.displayName, 'Minh Anh');
      expect(named.role, UserRole.user);
    });

    test('still reads the legacy { accessToken, displayName }', () {
      final legacy =
          AuthResult.fromJson({'accessToken': 'jwt', 'displayName': 'An'});
      expect(legacy.displayName, 'An');
      expect(legacy.userId, isNull);
      expect(legacy.role, UserRole.user);
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

    test('signs in as Minh Anh (User) without an account', () async {
      final container = await containerWith({});
      await container
          .read(sessionControllerProvider.notifier)
          .signInWithGoogle();
      final session = container.read(sessionControllerProvider);
      expect(session.isGuest, isFalse);
      expect(session.displayName, 'Minh Anh');
      expect(session.userId, 'u_me');
      expect(session.role, UserRole.user);
      expect(session.isChef, isFalse);
    });

    test('the chef account survives a restart; sign-out clears it', () async {
      final container = await containerWith({});
      await container
          .read(sessionControllerProvider.notifier)
          .signInWithGoogle(account: tamChefAccount);
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
        'vl.display_name',
        'vl.user_id',
        'vl.role'
      ]) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getString('vl.guest_token'), restored.guestToken);
    });

    test('a mock session saved before accounts existed is Minh Anh', () async {
      final container = await containerWith(
          {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'});
      final session = container.read(sessionControllerProvider);
      expect(session.userId, 'u_me');
      expect(session.role, UserRole.user);
    });
  });

  group('Google sign-in picker (mock)', () {
    Future<SharedPreferences> pumpApp(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [AccountButton()]),
            body: const Center(child: GoogleSignInButton()),
          ),
        ),
      ));
      return prefs;
    }

    testWidgets('choosing the chef signs in as Lê Quang Tâm', (tester) async {
      final prefs = await pumpApp(tester);

      await tester.tap(find.text('Tiếp tục với Google'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn tài khoản Google (mô phỏng)'), findsOneWidget);
      expect(find.text('Minh Anh (Thành viên)'), findsOneWidget);
      expect(find.text('minhanh.nguyen@gmail.com'), findsOneWidget);

      await tester.tap(find.text('Lê Quang Tâm (Chuyên gia)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Đang đăng nhập…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // mock latency
      await tester.pumpAndSettle();
      expect(find.text('Tiếp tục với Google'), findsOneWidget);
      expect(prefs.getString('vl.role'), 'Chef');

      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      expect(find.text('Xin chào, Lê Quang Tâm'), findsOneWidget);
    });

    testWidgets('dismissing the picker stays a guest, silently',
        (tester) async {
      final prefs = await pumpApp(tester);

      await tester.tap(find.text('Tiếp tục với Google'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 120)); // the sheet's barrier
      await tester.pumpAndSettle();

      expect(find.text('Chọn tài khoản Google (mô phỏng)'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Tiếp tục với Google'), findsOneWidget);
      expect(prefs.containsKey('vl.access_token'), isFalse);
    });

    testWidgets('the account menu opens the same picker', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập với Google'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn tài khoản Google (mô phỏng)'), findsOneWidget);

      await tester.tap(find.text('Minh Anh (Thành viên)'));
      await tester.pump(const Duration(seconds: 2)); // mock latency
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      expect(find.text('Xin chào, Minh Anh'), findsOneWidget);
    });
  });
}
