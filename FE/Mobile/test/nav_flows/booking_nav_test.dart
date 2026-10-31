// test/nav_flows/booking_nav_test.dart
// WP-C: booking flows end on short stacks (§6 N2–N8), in the whole app
// (root route stack registered), on the mock server.
@Timeout(Duration(seconds: 240))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/book_chef_plan_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_history_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/plan_editor_screen.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_profile_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/commerce/presentation/screens/payment_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
  'vl.onboarded': true,
};

const _tam = {
  'vl.access_token': 'mock.jwt.tam',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
  'vl.onboarded': true,
};

/// A member with no booking yet.
const _newMember = {
  'vl.access_token': 'mock.jwt.new',
  'vl.display_name': 'Bạn Mới',
  'vl.user_id': 'u_nav_new',
  'vl.role': 'User',
  'vl.onboarded': true,
};

void main() {
  // Real Roboto metrics (shipped with the SDK), as in the shell smoke tests.
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  setUp(() {
    MockCommerceDb.reset();
    MockMealPlannerRepository.reset();
  });

  final nav = find.byKey(const ValueKey('shell-nav'));
  Finder navLabel(String label) =>
      find.descendant(of: nav, matching: find.text(label));

  Future<ProviderContainer> pumpApp(WidgetTester tester,
      [Map<String, Object> prefs = _minhAnh]) async {
    tester.view
      ..physicalSize = const Size(411, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const VeganLifeApp(),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> wait(WidgetTester tester, [int seconds = 3]) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  NavigatorState root(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  List<String?> stack(WidgetTester tester) =>
      [for (final r in AppRouteStack.of(root(tester))!.routes) r.settings.name];

  int shownTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find
          .descendant(
              of: find.byType(AppShell), matching: find.byType(IndexedStack))
          .first)
      .index!;

  /// Android Back.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await wait(tester, 1);
  }

  Future<void> push(WidgetTester tester, Route<Object?> route,
      [int seconds = 3]) async {
    root(tester).push(route);
    await wait(tester, seconds);
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  /// From a directory on screen: Lê Quang Tâm › "Đặt chuyên gia lên thực
  /// đơn" › "Gửi yêu cầu".
  Future<void> bookTam(WidgetTester tester) async {
    await tester.tap(find.text('Lê Quang Tâm').first);
    await wait(tester);
    expect(find.byType(ChefProfileScreen), findsOneWidget);
    await tapVisible(tester, find.text('Đặt chuyên gia lên thực đơn').first);
    await wait(tester);
    expect(find.byType(BookChefPlanScreen), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nhu cầu & ghi chú'),
        'Mình cần thực đơn chay tăng cơ, bữa sáng nhanh dưới 15 phút.');
    await tapVisible(tester, find.text('Gửi yêu cầu'));
    await wait(tester, 4);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
  }

  group('N2/N3 "Gửi yêu cầu": one Back to the tab it started from', () {
    testWidgets('N2 Chuyên gia › hồ sơ › Đặt › Gửi', (tester) async {
      await pumpApp(tester);
      await tester.tap(navLabel('Chuyên gia'));
      await wait(tester);
      await bookTam(tester);

      final names = stack(tester);
      expect(names, hasLength(2), reason: '$names');
      expect(names.last, startsWith('/booking/'));
      expect(find.byType(ChefProfileScreen, skipOffstage: false), findsNothing);
      expect(
          find.byType(BookChefPlanScreen, skipOffstage: false), findsNothing);

      await systemBack(tester);
      expect(stack(tester), ['/']);
      expect(shownTab(tester), ShellTab.chefs.index);
      await wait(tester);
    });

    testWidgets('N3 Thực đơn › Chọn chuyên gia › hồ sơ › Đặt › Gửi',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(navLabel('Thực đơn'));
      await wait(tester);
      // What the "Nhờ chuyên gia thiết kế" card pushes.
      await push(
          tester,
          MaterialPageRoute<void>(
              builder: (_) => const ChefDirectoryScreen(pickMode: true)));
      expect(find.text('Chọn chuyên gia'), findsOneWidget);
      await bookTam(tester);

      final names = stack(tester);
      expect(names, hasLength(2), reason: '$names');
      expect(names.last, startsWith('/booking/'));

      await systemBack(tester);
      expect(stack(tester), ['/']);
      expect(shownTab(tester), ShellTab.planner.index);
      await wait(tester);
    });
  });

  group('N4 payment › "Lịch sử tư vấn"', () {
    final member = MockBookingRepository(
      currentUserId: () => 'u_me',
      currentUserName: () => 'Minh Anh',
      currentRole: () => UserRole.user,
    );

    /// Accepts Tâm's offer on `b_ma_tam_nego` and opens its order.
    Future<String> openOrder(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final nego = await member.getBooking('b_ma_tam_nego');
          await member.respondToOffer(nego.id, nego.currentOffer!.id,
              accept: true);
          return member.startPayment(nego.id);
        }))!
            .id;

    Future<void> payAndOpenHistory(WidgetTester tester) async {
      await tapVisible(tester, find.text('Mô phỏng đã thanh toán'));
      await wait(tester);
      expect(find.text('Thanh toán thành công'), findsOneWidget);
      await tapVisible(
          tester, find.widgetWithText(OutlinedButton, 'Lịch sử tư vấn'));
      await wait(tester);
    }

    testWidgets('back to the history already open; its items open once',
        (tester) async {
      final orderId = await openOrder(tester);
      await pumpApp(tester);
      await push(tester, BookingHistoryScreen.route());
      await push(tester, BookingDetailScreen.route('b_ma_tam_nego'));
      await push(tester, PaymentScreen.route(orderId), 2);
      expect(stack(tester),
          ['/', '/booking-history', '/booking/b_ma_tam_nego', null]);

      await payAndOpenHistory(tester);
      expect(stack(tester), ['/', '/booking-history']);
      expect(find.byType(BookingHistoryScreen), findsOneWidget);

      // The paid booking opens as one detail page over the history.
      await tester.tap(find.text('Lê Quang Tâm').first);
      await wait(tester);
      expect(
          stack(tester), ['/', '/booking-history', '/booking/b_ma_tam_nego']);
      await systemBack(tester);
      await systemBack(tester);
      expect(stack(tester), ['/']);
      await wait(tester);
    });

    testWidgets('no history open: a single one above the shell',
        (tester) async {
      final orderId = await openOrder(tester);
      await pumpApp(tester);
      await tester.tap(navLabel('Chuyên gia'));
      await wait(tester);
      await push(tester, BookingDetailScreen.route('b_ma_tam_nego'));
      await push(tester, PaymentScreen.route(orderId), 2);

      await payAndOpenHistory(tester);
      expect(stack(tester), ['/', '/booking-history']);
      await systemBack(tester);
      expect(stack(tester), ['/']);
      expect(shownTab(tester), ShellTab.chefs.index);
      await wait(tester);
    });
  });

  testWidgets(
      'N5 empty "Lịch sử tư vấn" › "Khám phá chuyên gia" is the Chuyên gia '
      'tab, not another directory', (tester) async {
    await pumpApp(tester, _newMember);
    await tester.tap(navLabel('Tôi'));
    await wait(tester);
    await push(tester, BookingHistoryScreen.route());
    expect(find.text('Khám phá chuyên gia'), findsOneWidget);

    await tester.tap(find.text('Khám phá chuyên gia'));
    await wait(tester);
    expect(stack(tester), ['/']);
    expect(shownTab(tester), ShellTab.chefs.index);
    expect(find.text('Chọn chuyên gia', skipOffstage: false), findsNothing);
    expect(find.byType(ChefDirectoryScreen), findsOneWidget);
    await wait(tester);
  });

  testWidgets('N6 Chuyên gia app bar "Lịch sử tư vấn": one history page',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(navLabel('Chuyên gia'));
    await wait(tester);
    await tester.tap(find.byTooltip('Lịch sử tư vấn'));
    await wait(tester);
    expect(stack(tester), ['/', '/booking-history']);
    expect(find.byType(BookingHistoryScreen), findsOneWidget);

    await systemBack(tester);
    expect(stack(tester), ['/']);
    expect(shownTab(tester), ShellTab.chefs.index);
    await wait(tester);
  });

  testWidgets(
      'N7 "Áp dụng kế hoạch vào Thực đơn" › "Xem Thực đơn" lands on the '
      'Thực đơn tab', (tester) async {
    final container = await pumpApp(tester);
    await push(
        tester, BookingDetailScreen.route('b_ma_thuha_active', initialTab: 1));
    await tapVisible(tester, find.text('Áp dụng kế hoạch vào Thực đơn'));
    // The seeded week holds other dishes: replacing them is confirmed first.
    for (var i = 0;
        i < 16 && find.byType(AlertDialog).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.text('Thay và áp dụng'));
    for (var i = 0; i < 40 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await wait(tester, 1); // the snackbar slides in
    final snack = find.byType(SnackBar);
    expect(find.descendant(of: snack, matching: find.textContaining('món')),
        findsOneWidget);
    expect(find.descendant(of: snack, matching: find.text('Xem Thực đơn')),
        findsOneWidget);

    await tester.tap(find.text('Xem Thực đơn'));
    await wait(tester);
    expect(stack(tester), ['/']);
    expect(container.read(shellTabProvider), ShellTab.planner);
    expect(shownTab(tester), ShellTab.planner.index);
    await wait(tester);
  });

  testWidgets(
      'N8 "Gửi toàn bộ kế hoạch" closes the editor: back on the booking with '
      '"Đã gửi toàn bộ kế hoạch"', (tester) async {
    var userId = 'u_me';
    final bookings = MockBookingRepository(
      currentUserId: () => userId,
      currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
      currentRole: () => userId == 'u_me' ? UserRole.user : UserRole.chef,
    );
    final commerce = MockCommerceRepository(currentUserId: () => userId);
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day + 3);
    PlanMealDto meal(MealSlot slot, String name) => PlanMealDto(
        slot: slot, recipe: PlanRecipeDto(name: name, calories: 400));

    // A paid 3-day one-shot plan, every day drafted by Tâm.
    final bookingId = (await tester.runAsync(() async {
      final created = await bookings.createBooking(CreateBookingRequestDto(
        chefId: 'u_chef_tam',
        bookingType: BookingType.oneShot,
        planDays: 3,
        startDate: start,
        goal: 'maintain',
        allergies: const [],
        mealPattern: MealPattern.standard,
        needs: 'Mình cần thực đơn chay ba ngày, nấu nhanh dưới 30 phút.',
      ));
      userId = 'u_chef_tam';
      final quoted = await bookings.sendOffer(
          created.id,
          OfferRequestDto(
              price: 450000,
              planDays: 3,
              bookingType: BookingType.oneShot,
              startDate: start));
      userId = 'u_me';
      await bookings.respondToOffer(created.id, quoted.currentOffer!.id,
          accept: true);
      final order = await bookings.startPayment(created.id);
      await commerce.mockConfirmPayment(order.payment!.id, success: true);
      userId = 'u_chef_tam';
      for (var day = 1; day <= 3; day++) {
        await bookings.savePlanDay(
            created.id,
            day,
            PlanDayRequestDto(meals: [
              meal(MealSlot.breakfast, 'Cháo yến mạch $day'),
              meal(MealSlot.lunch, 'Cơm gạo lứt đậu hũ $day'),
              meal(MealSlot.dinner, 'Canh rong biển $day'),
            ]));
      }
      return created.id;
    }))!;

    await pumpApp(tester, _tam);
    await push(tester, BookingDetailScreen.route(bookingId));
    await tapVisible(tester, find.text('Soạn kế hoạch').first);
    await wait(tester);
    expect(find.byType(PlanEditorScreen), findsOneWidget);

    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Gửi toàn bộ kế hoạch'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Gửi toàn bộ kế hoạch?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await wait(tester, 4);

    expect(find.byType(PlanEditorScreen, skipOffstage: false), findsNothing);
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    expect(stack(tester), ['/', '/booking/$bookingId']);
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('Đã gửi toàn bộ kế hoạch')),
        findsOneWidget);
    final sent = (await tester.runAsync(() => bookings.getBooking(bookingId)))!;
    expect(sent.deliveredDays, 3);
    await wait(tester);
  });
}
