// test/qa_real/open_items_test.dart
// The smaller items the device QA left open: sign-out offline, one avatar, and
// the sample-data banner on the mock booking and payment screens.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/account_button.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/core/widgets/user_avatar.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/presentation/controllers/booking_controllers.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/chef_booking_inbox_screen.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

const _offline = ApiException(message: 'Mất kết nối.', code: 'network');

class _OfflineProfile implements ProfileApiService {
  @override
  Future<UserProfileDto> getMe() async => throw _offline;

  @override
  Future<UserProfileDto> updateMe(
          String userId, UpdateUserRequestDto request) async =>
      throw _offline;

  @override
  Future<void> submitChefApplication(ChefApplicationRequest request) async {}
}

Future<ProviderContainer> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const [], String role = 'User'}) async {
  tester.view
    ..physicalSize = const Size(411, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: 'test-token',
    'vl.user_id': '6ae5962396695f5c139fa9b0',
    'vl.display_name': 'Vũ Quỳnh',
    'vl.role': role,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: home),
  ));
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  testWidgets('Tôi: sign-out is reachable when the profile cannot load',
      (tester) async {
    final container = await _pump(tester, const ProfileScreen(),
        overrides: [profileApiProvider.overrideWithValue(_OfflineProfile())]);
    expect(find.text('Thử lại'), findsOneWidget);

    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất'));
    await tester.pumpAndSettle();
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
  });

  testWidgets('app-bar avatar shows the same initials as everywhere else',
      (tester) async {
    await _pump(
        tester,
        Scaffold(
          appBar: AppBar(actions: const [AccountButton()]),
          body: const UserAvatar(name: 'Vũ Quỳnh'),
        ));
    expect(
        find.descendant(
            of: find.byType(AccountButton), matching: find.text('VQ')),
        findsOneWidget);
    expect(find.text('VQ'), findsNWidgets(2));
  });

  // `AsyncValue(:final value?)` reads `.value`, which rethrows on an AsyncError:
  // a failed load painted the red error screen instead of "Thử lại".
  group('a failed load shows the retry view', () {
    Future<void> check(WidgetTester tester, Widget screen,
        {required List<Override> overrides, String role = 'User'}) async {
      await _pump(tester, screen, overrides: overrides, role: role);
      expect(tester.takeException(), isNull);
      expect(find.text('Thử lại'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('booking detail', (tester) async {
      const id = 'b1';
      await check(tester, const BookingDetailScreen(bookingId: id), overrides: [
        bookingProvider(id).overrideWith((ref) async => throw _offline),
      ]);
    });

    testWidgets('chef inbox', (tester) async {
      await check(tester, const ChefBookingInboxScreen(),
          role: 'Chef',
          overrides: [
            chefInboxProvider.overrideWith((ref) async => throw _offline),
          ]);
    });

    testWidgets('booking history', (tester) async {
      await check(tester, const BookingHistoryScreen(), overrides: [
        myBookingsProvider.overrideWith((ref) async => throw _offline),
      ]);
    });

    test('no screen matches on AsyncValue.value', () {
      final offenders = [
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('AsyncValue(:final value'))
            f.path,
      ];
      expect(offenders, isEmpty);
    });
  });

  group('sample-data banner', () {
    Future<void> check(WidgetTester tester, Widget screen,
        {List<Override> overrides = const [], String role = 'User'}) async {
      BackendModules.debugOverride({BackendModule.community});
      await _pump(tester, screen, overrides: overrides, role: role);
      expect(find.text(DemoDataBanner.label), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // A fully mock build keeps its widget tree.
      BackendModules.debugOverride(const {});
      await _pump(tester, screen, overrides: overrides, role: role);
      expect(find.text(DemoDataBanner.label), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('booking detail', (tester) async {
      const id = 'b1';
      await check(tester, const BookingDetailScreen(bookingId: id), overrides: [
        bookingProvider(id).overrideWith((ref) async => throw _offline),
      ]);
    });

    testWidgets('chef inbox', (tester) async {
      await check(tester, const ChefBookingInboxScreen(),
          role: 'Chef',
          overrides: [
            chefInboxProvider.overrideWith((ref) async => const <BookingDto>[]),
          ]);
    });

    testWidgets('payment', (tester) async {
      await check(tester, const PaymentScreen(orderId: 'missing'));
    });
  });
}
