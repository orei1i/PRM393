// test/qa_fixes/session_test.dart
// Q1 (nothing of a user stays on the device after sign-out), Q4 (a rename
// reaches the session) and the session expiry that closes pushed pages.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/search/domain/entities/search_result.dart';
import 'package:veganlife_mobile/features/search/presentation/controllers/global_search_controller.dart';

import '../helpers/session_helpers.dart';
import '../hybrid/planner_test_support.dart';
import 'qa_support.dart';

const _hoanKiem = UserLocation(
  point: GeoPoint(21.0287, 105.8524),
  label: 'Hồ Hoàn Kiếm',
  source: UserLocationSource.search,
);

Future<void> _leaveTraces(ProviderContainer c) async {
  await c.read(recentSearchesProvider.notifier).add('bun rieu');
  await c.read(recentViewsProvider.notifier).add(const RecentView(
      kind: SuggestKind.recipe, id: 'l5', title: 'Bún riêu chay'));
  await c.read(userLocationProvider.future);
  await c.read(userLocationProvider.notifier).setLocation(_hoanKiem);
}

Future<void> _expectClean(ProviderContainer c) async {
  expect(c.read(recentSearchesProvider), isEmpty);
  expect(c.read(recentViewsProvider), isEmpty);
  expect(c.read(recentLocationsProvider), isEmpty);
  expect((await c.read(userLocationProvider.future)).label,
      MockLocationService.label);
  final prefs = c.read(sharedPreferencesProvider);
  for (final key in UserDataKeys.all) {
    expect(prefs.containsKey(key), isFalse, reason: key);
  }
}

void main() {
  setUp(MockAuthDb.reset);

  group('Q1 sign-out leaves nothing behind', () {
    test('a guest starts clean, then the next account too', () async {
      final c = await qaContainer();
      await _leaveTraces(c);
      expect(c.read(recentSearchesProvider), ['bun rieu']);
      expect(c.read(recentLocationsProvider), hasLength(1));

      await c.read(sessionControllerProvider.notifier).signOut();
      await _expectClean(c);

      await signInAs(c, tamChefAccount);
      await _expectClean(c);
    });

    test('nor does an expired session', () async {
      final c = await qaContainer();
      await _leaveTraces(c);
      await c.read(sessionControllerProvider.notifier).expire();
      await _expectClean(c);
    });

    test('settings and the guest token are not user data', () async {
      final c = await qaContainer(session: {
        ...minhAnhSession,
        'vl.theme_mode': 'dark',
        'vl.guest_token': 'guest_1',
      });
      await c.read(sessionControllerProvider.notifier).signOut();
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('vl.theme_mode'), 'dark');
      expect(prefs.getString('vl.guest_token'), 'guest_1');
    });

    test('the keys stay the ones older versions wrote', () {
      expect(RecentSearchesController.prefsKey, 'vl.recent_searches');
      expect(RecentViewsController.prefsKey, 'vl.recent_views');
      expect(UserLocationController.prefsKey, 'vl.user_location');
      expect(RecentLocationsController.prefsKey, 'vl.recent_locations');
    });
  });

  group('Q4 a rename reaches the session', () {
    test('mock: session, saved name, new posts, the next sign-in', () async {
      final c = await qaContainer();
      addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
      await c.read(profileControllerProvider.future);

      await c
          .read(profileControllerProvider.notifier)
          .updateInfo(fullName: 'Minh Anh Mới');

      expect(c.read(sessionControllerProvider).displayName, 'Minh Anh Mới');
      expect(c.read(sharedPreferencesProvider).getString('vl.display_name'),
          'Minh Anh Mới');

      final post = await c.read(communityApiProvider).createPost(
            const CreatePostRequestDto(
              type: PostType.discussion,
              title: 'Tên mới của mình',
              body: 'Nội dung đủ dài để đăng được lên bảng tin.',
              tags: [],
              mediaType: PostMediaType.text,
            ),
          );
      expect(post.toEntity().author.name, 'Minh Anh Mới');

      final login =
          MockAuthDb.login(minhAnhAccount.email, minhAnhAccount.password);
      expect(login.displayName, 'Minh Anh Mới');
    });

    testWidgets('the composer follows the session name', (tester) async {
      final c = await pumpScreen(tester, const CreatePostScreen());
      await tester.pump();
      expect(find.text('Minh Anh'), findsOneWidget);
      await c
          .read(sessionControllerProvider.notifier)
          .updateDisplayName('Minh Anh Mới');
      await tester.pump();
      expect(find.text('Minh Anh Mới'), findsOneWidget);
      expect(find.text('Minh Anh'), findsNothing);
      await disposeScreen(tester);
    });

    test('a failed save keeps the old name', () async {
      final c = await qaContainer();
      addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
      await c.read(profileControllerProvider.future);
      await expectLater(
          c
              .read(profileControllerProvider.notifier)
              .updateInfo(fullName: 'Tên #fail'),
          throwsA(isA<ApiException>()));
      expect(c.read(sessionControllerProvider).displayName, 'Minh Anh');
    });

    group('real BE', () {
      setUp(() =>
          BackendModules.debugOverride(BackendModules.supportedByBackend));
      tearDown(() => BackendModules.debugOverride(null));

      test('a saved PUT renames the session', () async {
        var name = 'FE Test';
        final backend = FakeBackend();
        backend.routes['GET /users/me'] = (_) => (
              200,
              envelope({'id': testUserId, 'fullName': name, 'email': 'a@b.vn'})
            );
        backend.routes['PUT /users/$testUserId'] = (request) {
          name = (request.data as Map)['fullName'] as String;
          return (200, envelope({'id': testUserId, 'fullName': name}));
        };
        final c = await backendContainer(backend);
        addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
        await c.read(profileControllerProvider.future);

        await c
            .read(profileControllerProvider.notifier)
            .updateInfo(fullName: 'Tên Mới');

        expect(c.read(sessionControllerProvider).displayName, 'Tên Mới');
      });

      test('a refused PUT (B3) keeps the old name', () async {
        final backend = FakeBackend()
          ..on('GET /users/me', 200,
              envelope({'id': testUserId, 'fullName': 'FE Test'}))
          ..on('PUT /users/$testUserId', 403,
              {'success': false, 'message': 'Forbidden'});
        final c = await backendContainer(backend);
        addTearDown(c.listen(profileControllerProvider, (_, __) {}).close);
        await c.read(profileControllerProvider.future);

        await expectLater(
            c
                .read(profileControllerProvider.notifier)
                .updateInfo(fullName: 'Tên Mới'),
            throwsA(isA<ApiException>()));
        expect(c.read(sessionControllerProvider).displayName, 'FE Test');
      });
    });
  });

  group('session expiry', () {
    Future<ProviderContainer> pumpApp(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(411, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(minhAnhSession);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const VeganLifeApp(),
      ));
      await wait(tester, 3000);
      return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    }

    void pushPrivatePage(String text) =>
        rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Center(child: Text(text)))));

    testWidgets('pushed pages and dialogs close, back at the shell as a guest',
        (tester) async {
      final c = await pumpApp(tester);
      pushPrivatePage('Hợp đồng của Minh Anh');
      await wait(tester, 500);
      pushPrivatePage('Thanh toán của Minh Anh');
      await wait(tester, 500);
      showDialog<void>(
        context: rootNavigatorKey.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Hộp thoại')),
      );
      await wait(tester, 500);
      expect(find.text('Hộp thoại'), findsOneWidget);

      await c.read(sessionControllerProvider.notifier).expire();
      await wait(tester, 1000);

      expect(find.text('Hộp thoại'), findsNothing);
      expect(find.text('Thanh toán của Minh Anh'), findsNothing);
      expect(find.text('Hợp đồng của Minh Anh'), findsNothing);
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(c.read(sessionControllerProvider).isGuest, isTrue);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text(AuthErrors.sessionExpired), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('a stale token closes nothing', (tester) async {
      final c = await pumpApp(tester);
      pushPrivatePage('Hợp đồng của Minh Anh');
      await wait(tester, 500);

      await c
          .read(sessionControllerProvider.notifier)
          .expire(token: 'token cũ');
      await wait(tester, 500);

      expect(find.text('Hợp đồng của Minh Anh'), findsOneWidget);
      expect(c.read(sessionControllerProvider).isGuest, isFalse);
      await disposeScreen(tester);
    });
  });
}
