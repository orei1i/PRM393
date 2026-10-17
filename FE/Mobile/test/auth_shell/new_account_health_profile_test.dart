// test/auth_shell/new_account_health_profile_test.dart
//
// Device QA B1 (p01_28_chef_submitted, bug_new_account_inherits_health_profile,
// bug_new_account_health_profile_detail): an account registered on the
// device showed Minh Anh's seed health profile (172 cm · 66 kg · Tăng cơ ·
// dị ứng đậu phộng). A new account has none; every per-user store follows
// the signed-in id, and the demo accounts keep their seeds.
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/features/booking/data/mock_booking_repository.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/booking/domain/booking_enums.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_slot.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

import '../helpers/session_helpers.dart';

const _huy = RegisterRequest(
  fullName: 'Phạm Quang Huy',
  email: 'qa.chef.huy2@gmail.com',
  password: 'quanghuy2026',
);

void main() {
  setUp(() {
    MockAuthDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  Future<ProviderContainer> guestContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    container
      ..listen(mealPlanControllerProvider, (_, __) {})
      ..listen(userAllergiesProvider, (_, __) {})
      ..listen(pantryControllerProvider, (_, __) {})
      ..listen(profileHealthProvider, (_, __) {});
    return container;
  }

  test(
      'register → no health profile, no plan, no allergies, empty fridge; '
      'Minh Anh keeps hers', () async {
    final container = await guestContainer();
    final session = container.read(sessionControllerProvider.notifier);
    final created = await session.register(_huy);
    expect(created.userId, isNot(minhAnhAccount.userId));

    final planner = await container.read(mealPlanControllerProvider.future);
    expect(planner.hasHealthProfile, isFalse);
    expect(planner.plan, isNull);
    expect(await container.read(profileHealthProvider.future), isNull);
    expect(await container.read(userAllergiesProvider.future), isEmpty);
    expect(await container.read(pantryControllerProvider.future), isEmpty);

    await session.signOut();
    await signInAs(container, minhAnhAccount);
    final me = (await container.read(profileHealthProvider.future))!;
    expect(me.heightCm, 172);
    expect(me.allergies, ['peanut']);
    expect(await container.read(userAllergiesProvider.future), ['peanut']);
    expect((await container.read(mealPlanControllerProvider.future)).plan,
        isNotNull);

    // Back to the new account: still nothing borrowed.
    await session.signOut();
    await session.signIn(email: _huy.email, password: _huy.password);
    expect(await container.read(profileHealthProvider.future), isNull);
    expect(await container.read(userAllergiesProvider.future), isEmpty);
  });

  test('a new account shares no health profile with the chef', () async {
    final now = DateTime.utc(2026, 10, 17, 3);
    MockCommerceDb.reset(clock: () => now);
    var userId = 'u_reg_1_1760600000000';
    final bookings = MockBookingRepository(
      currentUserId: () => userId,
      currentUserName: () => 'Phạm Quang Huy',
      currentRole: () => UserRole.user,
    );
    final request = CreateBookingRequestDto(
      chefId: 'u_chef_tam',
      bookingType: BookingType.dailyFeedback,
      planDays: 7,
      startDate: DateTime(2026, 10, 20),
      goal: 'maintain',
      allergies: const [],
      mealPattern: MealPattern.standard,
      needs: 'Mình cần thực đơn chay đủ chất, bữa sáng nhanh dưới 15 phút.',
    );
    final mine = await bookings.createBooking(request);
    expect(mine.shareHealthProfile, isTrue);
    expect(mine.memberHealth, isNull);

    userId = minhAnhAccount.userId;
    final hers = await bookings.createBooking(request);
    expect(hers.memberHealth!.heightCm, 172);
    // B3: the target her Thực đơn aims at (2.060 at 29), same rounding.
    final target = Energy.dailyTarget(
        Energy.tdee(
            Energy.bmr(
                gender: Gender.female,
                weightKg: 66,
                heightCm: 172,
                age: Energy.ageFrom(1997)),
            ActivityLevel.light),
        0.05);
    expect(hers.memberHealth!.dailyKcalTarget, target);
    expect(hers.memberHealth!.summary,
        contains('≈ ${Energy.formatKcal(target)} kcal/ngày'));
  });

  testWidgets('Tôi: the health card asks to set it up, the form is empty',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Phạm Quang Huy',
      'vl.user_id': 'u_reg_1_1760600000000',
      'vl.role': 'User',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Hồ sơ sức khoẻ'), findsOneWidget);
    expect(find.text('Thiết lập'), findsOneWidget);
    expect(find.textContaining('Bạn chưa có hồ sơ sức khoẻ'), findsOneWidget);
    expect(find.textContaining('172 cm'), findsNothing);
    expect(find.textContaining('đậu phộng'), findsNothing);

    await tester.tap(find.text('Thiết lập'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(HealthProfileEditScreen), findsOneWidget);
    expect(find.text('Thiết lập hồ sơ sức khoẻ'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Chiều cao (cm)'))
            .controller!
            .text,
        isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
