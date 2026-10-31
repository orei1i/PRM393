// test/qa_fixes/booking_test.dart
// Q7 (applying a chef plan warns with a count), Q8 (payment deadline), Q10
// (no feedback for a future day), Q12 (complaint link), Q13 (contract text),
// Q19 (feedback price), Q20 (overdue day) and Q22 (chef counts).
@Timeout(Duration(seconds: 180))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_rules.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_views.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/booking_detail_screen.dart';
import 'package:veganlife_mobile/features/booking/presentation/screens/complaint_form_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/domain/chef_studio_rules.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/mock_commerce_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';

import 'qa_support.dart';

void main() {
  var userId = 'u_me';
  final bookings = MockBookingRepository(
    currentUserId: () => userId,
    currentUserName: () => userId == 'u_me' ? 'Minh Anh' : 'Lê Quang Tâm',
    currentRole: () => userId == 'u_me' ? UserRole.user : UserRole.chef,
  );
  final commerce = MockCommerceRepository(currentUserId: () => userId);

  setUp(() {
    userId = 'u_me';
    MockCommerceDb.reset();
    MockMealPlannerRepository.reset();
  });

  CreateBookingRequestDto request(DateTime start, {String? needs}) =>
      CreateBookingRequestDto(
        chefId: 'u_chef_tam',
        bookingType: BookingType.dailyFeedback,
        planDays: 3,
        startDate: start,
        goal: 'maintain',
        allergies: const ['peanut'],
        mealPattern: MealPattern.standard,
        budgetPerDay: 80000,
        needs: needs ??
            'Mình cần thực đơn chay giảm cân, bữa sáng nhanh dưới 15 phút.',
      );

  OfferRequestDto offer(DateTime start) => OfferRequestDto(
      price: 1000000,
      planDays: 3,
      bookingType: BookingType.dailyFeedback,
      startDate: start);

  /// Member requests from Tâm, Tâm quotes, the member accepts.
  Future<BookingDto> accepted(DateTime start, {String? needs}) async {
    userId = 'u_me';
    final created = await bookings.createBooking(request(start, needs: needs));
    userId = 'u_chef_tam';
    final quoted = await bookings.sendOffer(created.id, offer(start));
    userId = 'u_me';
    return bookings.respondToOffer(created.id, quoted.currentOffer!.id,
        accept: true);
  }

  PlanDayRequestDto fullDay() => PlanDayRequestDto(meals: [
        for (final slot in MealPattern.standard)
          PlanMealDto(
              slot: slot,
              recipe: PlanRecipeDto(name: 'Món ${slot.label}', calories: 400)),
      ]);

  /// Paid, with day 1 sent ahead of time.
  Future<BookingDto> withDayOneSent(DateTime start) async {
    final b = await accepted(start);
    final order = await bookings.startPayment(b.id);
    await commerce.mockConfirmPayment(order.payment!.id, success: true);
    userId = 'u_chef_tam';
    await bookings.savePlanDay(b.id, 1, fullDay());
    await bookings.sendPlanDay(b.id, 1);
    userId = 'u_me';
    return bookings.getBooking(b.id);
  }

  group('Q8 payment deadline', () {
    final at = DateTime.utc(2026, 10, 31, 8, 40); // 15:40 VN

    test('never after the plan starts', () {
      expect(paymentDeadline(at, DateTime(2026, 11, 1)),
          DateTime.utc(2026, 10, 31, 17), // 00:00 VN, 01/11
          reason: 'starts tomorrow: not 15:40, 02/11');
    });

    test('48 hours when the start is far enough', () {
      expect(paymentDeadline(at, DateTime(2026, 11, 10)),
          at.add(const Duration(hours: 48)));
      expect(paymentDeadline(at, DateTime(2026, 11, 3)),
          at.add(const Duration(hours: 48)));
    });

    test('accepting an offer that starts tomorrow', () async {
      final tomorrow = addDays(vnDateOf(DateTime.now()), 1);
      final b = await accepted(tomorrow);
      final due = b.contract!.paymentDueAt.toUtc();
      expect(due, vnTime(tomorrow, 0, 0));
      expect(due.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('#expire keeps its 30 s', () async {
      final tomorrow = addDays(vnDateOf(DateTime.now()), 5);
      final b = await accepted(tomorrow,
          needs: 'Thử hết hạn thanh toán nhanh #expire cho kế hoạch này.');
      expect(b.contract!.paymentDueAt.difference(b.contract!.createdAt),
          const Duration(seconds: 30));
    });
  });

  group('Q10 feedback on a future day', () {
    Matcher refused(String code) => throwsA(isA<ApiException>()
        .having((e) => e.statusCode, 'statusCode', 409)
        .having((e) => e.code, 'code', code));

    test('the rule', () {
      final now = DateTime.utc(2026, 10, 31, 8); // 15:00 VN, 31/10
      expect(planDayStarted(DateTime(2026, 10, 31), now), isTrue);
      expect(planDayStarted(DateTime(2026, 10, 30), now), isTrue);
      expect(planDayStarted(DateTime(2026, 11, 1), now), isFalse);
      // 18:00Z on 31/10 is already 01:00 on 01/11 in Vietnam.
      expect(
          planDayStarted(DateTime(2026, 11, 1), DateTime.utc(2026, 10, 31, 18)),
          isTrue);
    });

    test('the server refuses until the day starts', () async {
      final tomorrow = addDays(vnDateOf(DateTime.now()), 1);
      final b = await withDayOneSent(tomorrow);
      await expectLater(
          bookings.sendDayFeedback(b.id, 1,
              const DayFeedbackDto(rating: 5, adherence: Adherence.all)),
          refused('day_not_started'));
    });

    testWidgets('the plan tab says when it opens', (tester) async {
      final tomorrow = addDays(vnDateOf(DateTime.now()), 1);
      final b = (await tester.runAsync(() => withDayOneSent(tomorrow)))!;
      await pumpScreen(
          tester, BookingDetailScreen(bookingId: b.id, initialTab: 1));
      await wait(tester, 3000);
      expect(find.text('Phản hồi ngày này'), findsNothing);
      final label = 'Phản hồi từ ${_dayMonth(tomorrow)}';
      expect(find.text(label), findsOneWidget);
      final button = tester.widget<TextButton>(find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is TextButton)));
      expect(button.onPressed, isNull);
      await disposeScreen(tester);
    });
  });

  test('Q13 the contract names the allergen', () {
    final text = MockBookingDb.scopeText(7, BookingType.oneShot,
        MealPattern.standard, const ['peanut', 'lá lốt']);
    expect(text, contains('tránh hoàn toàn: Đậu phộng, lá lốt.'));
    expect(text, isNot(contains('peanut')));
  });

  test('Q13 on a new contract', () async {
    final b = await accepted(addDays(vnDateOf(DateTime.now()), 5));
    expect(b.contract!.scopeText, contains('tránh hoàn toàn: Đậu phộng'));
  });

  group('Q19 feedback price', () {
    test('not below the base price', () {
      expect(ChefProfileRules.feedbackDayPrice(180000, 200000),
          'Giá có phản hồi không thấp hơn giá mỗi ngày.');
      expect(ChefProfileRules.feedbackDayPrice(200000, 200000), isNull);
      expect(ChefProfileRules.feedbackDayPrice(220000, 200000), isNull);
    });

    test('the range check still comes first', () {
      expect(ChefProfileRules.feedbackDayPrice(1, 200000),
          ChefProfileRules.dayPrice(1));
      expect(ChefProfileRules.feedbackDayPrice(null, 200000),
          ChefProfileRules.dayPrice(null));
      expect(ChefProfileRules.feedbackDayPrice(180000, null), isNull);
    });
  });

  test('Q20 a daily day past 06:00 VN is overdue', () {
    final start = DateTime(2026, 10, 31);
    expect(
        dailySendOverdue(start, 1, DateTime.utc(2026, 10, 30, 22, 59)), isFalse,
        reason: '05:59 VN');
    expect(
        dailySendOverdue(start, 1, DateTime.utc(2026, 10, 30, 23, 1)), isTrue,
        reason: '06:01 VN');
    expect(
        dailySendOverdue(start, 2, DateTime.utc(2026, 10, 30, 23, 1)), isFalse);
  });

  test('Q22 "Đang thực hiện" counts the rows of its tab', () async {
    userId = 'u_chef_tam';
    final inbox = await bookings.chefInbox();
    final rows =
        inbox.where((b) => InboxTab.of(b.status) == InboxTab.inProgress);
    expect(rows.length, greaterThan(1), reason: 'an active + a disputed seed');
    expect(chefBookingStats(inbox, DateTime.now()).inProgress, rows.length);
  });

  group('Q7 applying a chef plan warns before overwriting', () {
    const apply = 'Áp dụng kế hoạch vào Thực đơn';

    Future<ProviderContainer> open(WidgetTester tester) async {
      final c = await pumpScreen(
        tester,
        const BookingDetailScreen(
            bookingId: 'b_ma_thuha_active', initialTab: 1),
        size: const Size(411, 2400),
      );
      await wait(tester);
      return c;
    }

    Future<void> run(WidgetTester tester, Future<Object?> Function() f) async {
      final done = f();
      await wait(tester, 3000);
      await done;
    }

    testWidgets('an empty week: nothing to warn about', (tester) async {
      final c = await open(tester);
      await run(tester, () => c.read(mealPlanControllerProvider.future));
      await run(tester,
          () => c.read(mealPlanControllerProvider.notifier).createEmptyPlan());

      await tester.tap(find.text(apply));
      await waitFor(tester, find.byType(SnackBar));
      expect(find.byType(AlertDialog), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets(
        'the exact count; "Huỷ" changes nothing; applying again asks '
        'no more', (tester) async {
      final c = await open(tester);
      await run(tester, () => c.read(mealPlanControllerProvider.future));
      final notifier = c.read(mealPlanControllerProvider.notifier);
      await run(tester, notifier.createEmptyPlan);
      notifier.selectDate(DateTime.now());
      await run(
          tester,
          () => notifier.addManualMeal(
              slot: MealSlot.breakfast, name: 'Bữa sáng của tôi'));

      await tester.tap(find.text(apply));
      await waitFor(tester, find.byType(AlertDialog));
      expect(find.text('Thay 1 món đang có?'), findsOneWidget);
      expect(find.textContaining('1 bữa trong Thực đơn'), findsOneWidget);

      await tester.tap(find.text('Huỷ'));
      await wait(tester, 1000);
      Recipe? mine() => c
          .read(mealPlanControllerProvider)
          .requireValue
          .selectedDay!
          .meals[MealSlot.breakfast];
      expect(mine()!.name, 'Bữa sáng của tôi');
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text(apply));
      await waitFor(tester, find.byType(AlertDialog));
      await tester.tap(find.text('Thay và áp dụng'));
      await waitFor(tester, find.byType(SnackBar));
      expect(mine()!.name, isNot('Bữa sáng của tôi'));
      expect(mine()!.source, MealSource.chef);

      // Everything is the plan's now.
      await tester.pump(const Duration(seconds: 6));
      await wait(tester, 1000);
      await tester.tap(find.text(apply));
      await waitFor(tester, find.byType(SnackBar));
      expect(find.byType(AlertDialog), findsNothing);
      await disposeScreen(tester);
    });
  });

  testWidgets('Q2 the whole way: apply, Thực đơn, tap the chef\'s dish',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(minhAnhSession);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VeganLifeApp(),
    ));
    await wait(tester, 3000);
    rootNavigatorKey.currentState!
        .push(BookingDetailScreen.route('b_ma_thuha_active', initialTab: 1));
    await wait(tester, 3000);
    await tester.tap(find.text('Áp dụng kế hoạch vào Thực đơn'));
    await waitFor(tester, find.text('Thay và áp dụng'));
    await tester.tap(find.text('Thay và áp dụng'));
    await waitFor(tester, find.text('Xem Thực đơn'));
    await wait(tester, 500);
    await tester.tap(find.text('Xem Thực đơn'));
    await wait(tester, 3000);

    final card = find.byWidgetPredicate((w) =>
        w.runtimeType.toString() == 'MealSourceBadge' &&
        (w as dynamic).recipe.source == MealSource.chef);
    expect(card, findsWidgets);
    final badge = tester.widget(card.first) as dynamic;
    final name = badge.recipe.name as String;
    await tester.ensureVisible(find.text(name).first);
    await tester.pump();
    await tester.tap(find.text(name).first);
    await wait(tester, 2000);

    expect(find.byType(RecipeDetailScreen), findsOneWidget);
    expect(find.text('Không tìm thấy công thức'), findsNothing);
    await disposeScreen(tester);
  });

  group('Q12 complaint link', () {
    Future<BookingDto> open(WidgetTester tester) async {
      final booking = (await tester
          .runAsync(() => bookings.getBooking('b_ma_thuha_active')))!;
      await pumpScreen(tester, ComplaintFormScreen(booking: booking));
      await tester.pump();
      return booking;
    }

    final link = find.widgetWithText(TextField, 'Liên kết nguồn (http/https)');
    const badLink = 'Liên kết phải bắt đầu bằng http:// hoặc https://';
    const needsSource =
        'Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh';

    testWidgets('the message clears once the link is valid', (tester) async {
      await open(tester);
      await tester.enterText(link, 'vinmec');
      await tester.tap(find.text('Thêm liên kết nguồn'));
      await tester.pump();
      expect(find.text(badLink), findsOneWidget);

      await tester.enterText(link, 'https://www.vinmec.com/dau-mo');
      await tester.pump();
      expect(find.text(badLink), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('a valid link in the field is enough to send', (tester) async {
      await open(tester);
      await tester.tap(find.text('Có nội dung ảnh hưởng sức khoẻ'));
      await tester.enterText(find.widgetWithText(TextField, 'Mô tả chi tiết'),
          'Ngày 3 có món chiên nhiều dầu dù mình đã ghi rõ cần ít dầu.');
      await tester.tap(find.text('Gửi khiếu nại'));
      await tester.pump();
      expect(find.text(needsSource), findsNWidgets(2), reason: 'hint + error');

      await tester.enterText(link, 'https://www.vinmec.com/dau-mo');
      await tester.pump();
      expect(find.text(needsSource), findsOneWidget, reason: 'the hint only');

      await tester.tap(find.text('Gửi khiếu nại'));
      await wait(tester, 3000);
      final after = (await tester
          .runAsync(() => bookings.getBooking('b_ma_thuha_active')))!;
      expect(after.complaint!.evidence.map((e) => e.url),
          contains('https://www.vinmec.com/dau-mo'));
      await disposeScreen(tester);
    });

    testWidgets('half a link is not dropped silently', (tester) async {
      await open(tester);
      await tester.enterText(link, 'vinmec');
      await tester.tap(find.text('Gửi khiếu nại'));
      await tester.pump();
      expect(find.text(badLink), findsOneWidget);
      await disposeScreen(tester);
    });
  });
}

String _dayMonth(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
