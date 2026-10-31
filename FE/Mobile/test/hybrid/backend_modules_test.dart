// test/hybrid/backend_modules_test.dart
// The module switch, its dart-defines, the persona, the small id and URL
// helpers, and the "Dữ liệu mẫu" banner on the mock entry screens. Passes with
// and without --dart-define=USE_MOCK_DATA=false.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_endpoints.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_persona.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/backend_ids.dart';
import 'package:veganlife_mobile/core/utils/media_url.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/booking/data/booking_api_service.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/screens/chat_screen.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/data/chef_wallet_api_service.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_wallet_screen.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

const _objectId = '6ae5962396695f5c139fa9b0';
const _realUser = {BackendModule.auth};

AuthSession _member({UserRole role = UserRole.user, String id = _objectId}) =>
    AuthSession(guestToken: 'g', accessToken: 't', userId: id, role: role);

/// Prefs of a signed-in real account (no token value matters here).
Future<SharedPreferences> _prefs({UserRole? role}) async {
  SharedPreferences.setMockInitialValues({
    if (role != null) ...{
      SessionController.accessTokenKey: 'test-token',
      'vl.user_id': _objectId,
      'vl.display_name': 'Bạn Thật',
      'vl.role': role.apiValue,
    },
  });
  return SharedPreferences.getInstance();
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('resolveRealModules', () {
    Set<BackendModule> resolve({
      bool useMockData = false,
      String mock = '',
      String real = '',
    }) =>
        BackendModules.resolveRealModules(
            useMockData: useMockData, mockModules: mock, realModules: real);

    test('USE_MOCK_DATA=true: all mock, whatever the other defines say', () {
      expect(resolve(useMockData: true), isEmpty);
      expect(resolve(useMockData: true, real: 'auth,community'), isEmpty);
    });

    test('USE_MOCK_DATA=false: what the BE supports', () {
      expect(resolve(), BackendModules.supportedByBackend);
      expect(resolve(), contains(BackendModule.community));
      expect(resolve(), isNot(contains(BackendModule.bookings)));
      expect(resolve(), isNot(contains(BackendModule.recipeSocial)));
      expect(resolve(), isNot(contains(BackendModule.video)));
    });

    test('BACKEND_MOCK_MODULES forces mock', () {
      final real = resolve(mock: 'community,scanner');
      expect(real, isNot(contains(BackendModule.community)));
      expect(real, isNot(contains(BackendModule.scanner)));
      expect(real, contains(BackendModule.planner));
    });

    test('BACKEND_REAL_MODULES forces real', () {
      expect(resolve(real: 'video'), contains(BackendModule.video));
    });

    test('names ignore case and spaces; unknown names are dropped', () {
      expect(resolve(real: ' chefStudio , CHEFWALLET,nope,,'),
          containsAll([BackendModule.chefStudio, BackendModule.chefWallet]));
      expect(resolve(real: 'nope'), BackendModules.supportedByBackend);
    });

    test('a module named in both defines is mock', () {
      expect(resolve(mock: 'video', real: 'video'),
          isNot(contains(BackendModule.video)));
    });

    test('auth mock makes every module mock', () {
      expect(resolve(mock: 'auth'), isEmpty);
      expect(resolve(mock: 'AUTH', real: 'video'), isEmpty);
    });
  });

  group('BackendModules', () {
    test('without an override it follows USE_MOCK_DATA', () {
      for (final module in BackendModule.values) {
        final expected = !Env.useMockData &&
            BackendModules.supportedByBackend.contains(module);
        expect(BackendModules.isReal(module), expected, reason: module.name);
        expect(BackendModules.isMock(module), !expected, reason: module.name);
      }
      expect(BackendModules.isHybrid, !Env.useMockData);
    });

    test('debugOverride is taken literally and can be reset', () {
      BackendModules.debugOverride({BackendModule.community});
      expect(BackendModules.isReal(BackendModule.community), isTrue);
      expect(BackendModules.isMock(BackendModule.auth), isTrue);
      expect(BackendModules.isHybrid, isTrue);

      BackendModules.debugOverride(const {});
      expect(BackendModules.isMock(BackendModule.community), isTrue);
      expect(BackendModules.isHybrid, isFalse);

      BackendModules.debugOverride(null);
      expect(BackendModules.isReal(BackendModule.community), !Env.useMockData);
    });

    test('capabilities: on while mock, off once the module is real', () {
      BackendModules.debugOverride(const {});
      expect(BackendModules.postEdit, isTrue);
      expect(BackendModules.commentEdit, isTrue);
      expect(BackendModules.commentReplyPaging, isTrue);
      expect(BackendModules.myComments, isTrue);
      expect(BackendModules.restaurantTag, isTrue);
      expect(BackendModules.planAdjust, isTrue);
      expect(BackendModules.checkInExtras, isTrue);
      expect(BackendModules.manualMealMacros, isTrue);

      BackendModules.debugOverride(
          {BackendModule.community, BackendModule.planner});
      expect(BackendModules.postEdit, isFalse);
      expect(BackendModules.commentEdit, isFalse);
      expect(BackendModules.commentReplyPaging, isFalse);
      expect(BackendModules.myComments, isFalse);
      expect(BackendModules.restaurantTag, isFalse);
      expect(BackendModules.planAdjust, isFalse);
      expect(BackendModules.checkInExtras, isFalse);
      expect(BackendModules.manualMealMacros, isFalse);
    });
  });

  group('mockPersonaId', () {
    test('mock auth: the session user, unchanged', () {
      BackendModules.debugOverride(const {});
      expect(mockPersonaId(_member(id: 'u_chef_tam', role: UserRole.chef)),
          'u_chef_tam');
      expect(mockPersonaId(_member(id: 'u_new')), 'u_new');
      expect(mockPersonaId(const AuthSession(guestToken: 'g')), isNull);
    });

    test('real auth: a member is Minh Anh, a chef is Tâm, a guest is nobody',
        () {
      BackendModules.debugOverride(_realUser);
      expect(mockPersonaId(_member()), 'u_me');
      expect(mockPersonaId(_member(role: UserRole.chef)), 'u_chef_tam');
      expect(mockPersonaId(const AuthSession(guestToken: 'g')), isNull);
    });

    test('a real member sees the seeded bookings of the persona', () async {
      BackendModules.debugOverride(_realUser);
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await _prefs(role: UserRole.user)),
      ]);
      addTearDown(container.dispose);
      final bookings = await container.read(bookingApiProvider).myBookings();
      expect(bookings.map((b) => b.id), contains('b_ma_tam_nego'));
    });

    test('a real chef reads the wallet of the persona', () async {
      BackendModules.debugOverride(_realUser);
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await _prefs(role: UserRole.chef)),
      ]);
      addTearDown(container.dispose);
      await expectLater(
          container.read(chefWalletApiProvider).getWallet(), completes);
    });
  });

  group('helpers', () {
    test('Env.apiOriginOf strips the API prefix', () {
      expect(Env.apiOriginOf('http://10.0.2.2:5001/api/v1'),
          'http://10.0.2.2:5001');
      expect(Env.apiOriginOf('http://localhost:5001/api/v1/'),
          'http://localhost:5001');
      expect(Env.apiOriginOf('https://x.vn'), 'https://x.vn');
      expect(Env.apiOriginOf('https://x.vn/'), 'https://x.vn');
      expect(Env.apiBaseUrl, startsWith(Env.apiOrigin));
    });

    test('absoluteMediaUrl', () {
      expect(absoluteMediaUrl(null), isNull);
      expect(absoluteMediaUrl(''), isNull);
      expect(absoluteMediaUrl('/uploads/images/x.png'),
          '${Env.apiOrigin}/uploads/images/x.png');
      expect(absoluteMediaUrl('https://cdn.vn/x.png'), 'https://cdn.vn/x.png');
      expect(absoluteMediaUrl('http://cdn.vn/x.png'), 'http://cdn.vn/x.png');
      expect(absoluteMediaUrl('assets/x.png'), 'assets/x.png');
    });

    test('isBackendId is exactly 24 hex', () {
      expect(isBackendId(_objectId), isTrue);
      expect(isBackendId('6AE5962396695F5C139FA9B0'), isTrue);
      expect(isBackendId(null), isFalse);
      expect(isBackendId('l5'), isFalse);
      expect(isBackendId('u_me'), isFalse);
      expect(isBackendId('8da78bfdfb3147f0a9d8930ec2354bdc'), isFalse);
      expect(isBackendId('${_objectId}0'), isFalse);
      expect(isBackendId('zae5962396695f5c139fa9b0'), isFalse);
    });

    test('isBackendPlanItemId is exactly 32 hex', () {
      expect(isBackendPlanItemId('8da78bfdfb3147f0a9d8930ec2354bdc'), isTrue);
      expect(isBackendPlanItemId(_objectId), isFalse);
      expect(isBackendPlanItemId(null), isFalse);
      expect(isBackendPlanItemId('menu_1'), isFalse);
    });

    test('endpoints the later packages use', () {
      expect(ApiEndpoints.visionScan, '${Env.apiOrigin}/vision/scan');
      expect(Uri.parse(ApiEndpoints.visionScan).path, '/vision/scan');
      expect(ApiEndpoints.commentDelete('c1'), '/comments/c1');
    });
  });

  group('DemoDataBanner', () {
    final banner = find.text(DemoDataBanner.label);

    test('exact label', () {
      expect(DemoDataBanner.label,
          'Dữ liệu mẫu · Máy chủ chưa hỗ trợ tính năng này');
    });

    test('visible only for a mock module of a hybrid build', () {
      BackendModules.debugOverride(const {});
      expect(DemoDataBanner.visibleFor(BackendModule.chefs), isFalse);
      BackendModules.debugOverride(_realUser);
      expect(DemoDataBanner.visibleFor(BackendModule.chefs), isTrue);
      expect(DemoDataBanner.visibleFor(BackendModule.auth), isFalse);
    });

    test('wrap returns the child itself while hidden', () {
      BackendModules.debugOverride(const {});
      const child = SizedBox();
      expect(
          DemoDataBanner.wrap(BackendModule.chefs, child: child), same(child));
      BackendModules.debugOverride(_realUser);
      expect(DemoDataBanner.wrap(BackendModule.chefs, child: child),
          isA<Column>());
    });

    final screens = <String, Widget Function()>{
      'Chuyên gia': () => const ChefDirectoryScreen(),
      'Lịch sử tư vấn': () => const BookingHistoryScreen(),
      'Quán chay': () => const RestaurantNearbyScreen(),
      'Tìm kiếm': () => const SearchScreen(),
      'Hỏi AI': () => const ChatScreen(),
      'Ví': () => const ChefWalletScreen(),
    };

    Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
      tester.view
        ..physicalSize = const Size(411, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await _prefs(role: UserRole.user);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(home: screen),
      ));
      await tester.pump(const Duration(seconds: 2));
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }

    screens.forEach((name, screen) {
      testWidgets('$name: banner in a hybrid build', (tester) async {
        BackendModules.debugOverride(_realUser);
        await pumpScreen(tester, screen());
        expect(banner, findsOneWidget);
        await leave(tester);
      });

      testWidgets('$name: no banner in a fully mock build', (tester) async {
        BackendModules.debugOverride(const {});
        await pumpScreen(tester, screen());
        expect(banner, findsNothing);
        expect(find.byType(DemoDataBanner), findsNothing);
        await leave(tester);
      });
    });
  });

  group('screens that follow the switch', () {
    Future<void> pumpApp(WidgetTester tester, Widget home,
        {List<Override> overrides = const []}) async {
      tester.view
        ..physicalSize = const Size(411, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await _prefs();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: MaterialApp(home: home),
      ));
      await tester.pump();
    }

    testWidgets('login: test-account chips only while auth is mock',
        (tester) async {
      const chips = LoginScreen();
      BackendModules.debugOverride(const {});
      expect(chips.showTestAccounts, isTrue);
      BackendModules.debugOverride(_realUser);
      expect(chips.showTestAccounts, isFalse);
      expect(
          const LoginScreen(showTestAccounts: true).showTestAccounts, isTrue);
      await pumpApp(tester, chips);
      expect(find.textContaining('tài khoản thử nghiệm'), findsNothing);
    });

    test('payment: mock controls follow commerce, not auth', () {
      const screen = PaymentScreen(orderId: 'o1');
      BackendModules.debugOverride(_realUser);
      expect(screen.showMockControls, isTrue);
      BackendModules.debugOverride({BackendModule.commerce});
      expect(screen.showMockControls, isFalse);
      expect(
          const PaymentScreen(orderId: 'o1', showMockControls: true)
              .showMockControls,
          isTrue);
    });

    testWidgets('chat: the "#offline" hint is only in a fully mock build',
        (tester) async {
      final hint = find.textContaining('#offline');
      BackendModules.debugOverride(const {});
      await pumpApp(tester, const ChatScreen());
      expect(hint, findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // Hybrid: the chatbot is still mock, but the banner already says so.
      BackendModules.debugOverride({BackendModule.community});
      await pumpApp(tester, const ChatScreen());
      expect(hint, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    Future<void> toCodeStep(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(FilledButton, 'Gửi mã'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('forgot password: dev hint on real auth', (tester) async {
      BackendModules.debugOverride(_realUser);
      await pumpApp(
        tester,
        const ForgotPasswordScreen(initialEmail: 'a@example.com'),
        overrides: [
          authApiProvider.overrideWithValue(_NoCodeAuthApi()),
        ],
      );
      await toCodeStep(tester);
      expect(
          find.text('(Bản thử nghiệm) Máy chủ chưa gửi email: '
              'xem mã trong nhật ký máy chủ.'),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('forgot password: no dev hint on mock auth', (tester) async {
      BackendModules.debugOverride(const {});
      await pumpApp(
        tester,
        const ForgotPasswordScreen(initialEmail: 'a@example.com'),
        overrides: [
          authApiProvider.overrideWithValue(_NoCodeAuthApi()),
        ],
      );
      await toCodeStep(tester);
      expect(find.text(ForgotPasswordScreen.devCodeHint), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

/// What the real service answers to "Gửi mã": nothing, the code stays on the
/// server.
class _NoCodeAuthApi extends MockAuthApiService {
  @override
  Future<String?> requestPasswordReset(String email) async => null;
}
