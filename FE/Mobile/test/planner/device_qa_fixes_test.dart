// test/planner/device_qa_fixes_test.dart
//
// Regressions from device QA (FE/_screenshots/feedback/mobile):
// - B1: a newly registered account inherited Minh Anh's seed health profile
//   (172 cm, 66 kg, Nữ 1997, Tăng cơ, dị ứng đậu phộng). New accounts have
//   none: Thực đơn and Hồ sơ sức khoẻ ask to set one up; the demo accounts
//   keep theirs.
// - B3: the daily energy read 1.960 / 2.060 kcal on Hồ sơ sức khoẻ but
//   1.970 / 2.063 on Thực đơn and the booking contract. One formula, one
//   rounding rule (nearest 10 kcal) everywhere. A save that changes the
//   target also re-aims the current week, so the day cards follow it.
// - B8: "Hoàn tác" after deleting a fridge item put it back on top instead
//   of where it was, and (found re-testing it) never timed out: snackbars
//   with an action now leave after their duration unless a screen reader
//   is on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/features/booking/data/mock/mock_booking_db.dart';
import 'package:veganlife_mobile/features/booking/data/models/booking_models.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/health_header_card.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/macro_progress_bar.dart';

/// An account registered in this run (`MockAuthDb.register` ids look alike).
const _newUserId = 'u_reg_1_1760600000000';

Map<String, Object> _session(String userId, String name) => {
      'vl.access_token': 'mock.jwt',
      'vl.display_name': name,
      'vl.user_id': userId,
      'vl.role': 'User',
    };

Future<void> _pump(WidgetTester tester, Widget home,
    {required Map<String, Object> session,
    Size size = const Size(411, 2000)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

ProviderContainer _container(String? userId,
    {List<Override> overrides = const []}) {
  final container = ProviderContainer(overrides: [
    plannerUserIdProvider.overrideWithValue(userId),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Minh Anh's seed, as the QA device had it (age 29 this year).
HealthProfile _minhAnh({double? bmr, double? tdee}) => HealthProfile(
      heightCm: 172,
      weightKg: 66,
      bmi: 22.3,
      goal: HealthGoal.leanMuscle,
      gender: Gender.female,
      birthYear: DateTime.now().year - 29,
      activityLevel: ActivityLevel.light,
      bmr: bmr,
      tdee: tdee,
    );

/// The fridge as the API lists it after "Hoàn tác": the restored row on top
/// (the real API has no position), like [RemotePantryApiService].
class _NewestFirstPantry extends MockPantryRepository {
  _NewestFirstPantry() : super(userId: 'u_me');

  @override
  Future<List<PantryItemDto>> restoreItem(AddPantryItemDto item,
          {required int index}) =>
      addItems([item]);
}

void main() {
  setUpAll(() async {
    // Real Roboto metrics (the default test font draws wide squares).
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

  setUp(MockMealPlannerRepository.reset);

  group('B1: a new account has no health profile', () {
    test('mock API: none for a new id (404 → null); demo accounts keep theirs',
        () async {
      final fresh = MockMealPlannerRepository(userId: _newUserId);
      expect(await fresh.getHealthProfile(), isNull);
      expect(await fresh.getCurrentMealPlan(), isNull,
          reason: 'no demo week either');
      expect(await MockMealPlannerRepository().getHealthProfile(), isNull,
          reason: 'a guest borrows nobody\'s profile');

      final me =
          (await MockMealPlannerRepository(userId: 'u_me').getHealthProfile())!;
      expect(me.heightCm, 172);
      expect(me.allergies, ['peanut']);
      expect(
          await MockMealPlannerRepository(userId: 'u_me').getCurrentMealPlan(),
          isNotNull);
      final tam = (await MockMealPlannerRepository(userId: 'u_chef_tam')
          .getHealthProfile())!;
      expect(tam.heightCm, 168);
    });

    test('setting one up is stored for that account only', () async {
      final fresh = MockMealPlannerRepository(userId: _newUserId);
      final saved =
          await fresh.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 180,
        weightKg: 75,
        goal: HealthGoal.maintain,
        allergies: ['soy'],
        dietaryRestrictions: [],
        gender: Gender.male,
        birthYear: 1995,
      ));
      expect(saved.mealPattern, ['breakfast', 'lunch', 'dinner'],
          reason: 'no pattern sent → 3 meals');
      expect(saved.toEntity().dailyKcalTarget, isNotNull);
      expect((await fresh.getHealthProfile())!.allergies, ['soy']);

      final me =
          (await MockMealPlannerRepository(userId: 'u_me').getHealthProfile())!;
      expect(me.heightCm, 172, reason: 'Minh Anh untouched');
      expect(me.allergies, ['peanut']);
    });

    test('planner state, allergies and the fridge are empty for a new account',
        () async {
      final container = _container(_newUserId);
      container
        ..listen(mealPlanControllerProvider, (_, __) {})
        ..listen(userAllergiesProvider, (_, __) {})
        ..listen(pantryControllerProvider, (_, __) {});
      final state = await container.read(mealPlanControllerProvider.future);
      expect(state.hasHealthProfile, isFalse);
      expect(state.healthProfile, isNull);
      expect(state.plan, isNull);
      expect(state.profile.allergies, isEmpty);
      expect(await container.read(userAllergiesProvider.future), isEmpty);
      expect(await container.read(pantryControllerProvider.future), isEmpty);

      // Setting it up from the planner keeps the state in step.
      await container
          .read(mealPlanControllerProvider.notifier)
          .updateHealthProfile(
        heightCm: 160,
        weightKg: 52,
        goal: HealthGoal.loseWeight,
        allergies: const ['gluten'],
        dietaryRestrictions: const [],
      );
      final after = container.read(mealPlanControllerProvider).requireValue;
      expect(after.hasHealthProfile, isTrue);
      expect(after.profile.heightCm, 160);
      expect(after.plan, isNull, reason: 'no week made behind their back');
      expect(await container.read(userAllergiesProvider.future), ['gluten']);
    });

    testWidgets(
        'Thực đơn asks to set the profile up; the form starts empty and saves',
        (tester) async {
      await _pump(tester, const MealPlannerScreen(),
          session: _session(_newUserId, 'Phạm Quang Huy'));
      await _wait(tester);
      expect(find.byType(HealthHeaderCard), findsNothing);
      expect(find.byType(HealthProfileSetupCard), findsOneWidget);
      expect(find.text('Thiết lập hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.textContaining('172'), findsNothing);
      expect(find.textContaining('Đậu phộng'), findsNothing);
      expect(find.text('Chưa có thực đơn tuần này'), findsOneWidget);

      await tester.tap(find.text('Thiết lập hồ sơ'));
      await _wait(tester);
      expect(find.byType(HealthProfileEditScreen), findsOneWidget);
      expect(find.text('Thiết lập hồ sơ sức khoẻ'), findsOneWidget);
      final height = find.widgetWithText(TextFormField, 'Chiều cao (cm)');
      final weight = find.widgetWithText(TextFormField, 'Cân nặng (kg)');
      expect(tester.widget<TextFormField>(height).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(weight).controller!.text, isEmpty);
      expect(find.text('Nhập chiều cao và cân nặng hợp lệ để xem BMI'),
          findsOneWidget);

      await tester.enterText(height, '170');
      await tester.enterText(weight, '60');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.byType(HealthProfileEditScreen), findsNothing);
      expect(find.byType(HealthProfileSetupCard), findsNothing);
      expect(find.byType(HealthHeaderCard), findsOneWidget);
      expect(find.text('170 cm'), findsOneWidget);
      expect(find.text('Đã lưu hồ sơ sức khoẻ'), findsOneWidget);
      await _wait(tester, 7000); // snackbar
    });

    testWidgets('Minh Anh still opens her own profile', (tester) async {
      await _pump(tester, const HealthProfileEditScreen(),
          session: _session('u_me', 'Minh Anh'));
      await _wait(tester);
      expect(
          tester
              .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Chiều cao (cm)'))
              .controller!
              .text,
          '172');
      expect(find.text('Thiết lập hồ sơ sức khoẻ'), findsNothing);
    });
  });

  group('B3: one energy figure everywhere', () {
    test('QA case: cached tdee 1965 no longer reads 1.970; target 2.060', () {
      // What the server caches after a save: bmr/tdee rounded to whole kcal.
      final saved = _minhAnh(bmr: 1429, tdee: 1965);
      final preview = _minhAnh(); // the editor's live preview
      expect(saved.tdee, closeTo(1964.875, 1e-9));
      expect(Energy.formatKcal(saved.tdee!), '1.960');
      expect(Energy.formatKcal(preview.tdee!), '1.960');
      expect(saved.dailyKcalTarget, 2060);
      expect(preview.dailyKcalTarget, 2060);
      expect(Energy.formatKcal(2063), '2.060');

      // Legacy profile without gender/birth year: the server's cache is all
      // there is, shown with the same rule.
      const legacy = HealthProfile(
          heightCm: 168,
          weightKg: 63,
          bmi: 22.3,
          goal: HealthGoal.maintain,
          tdee: 2105);
      expect(Energy.formatKcal(legacy.tdee!), '2.110');
      expect(legacy.dailyKcalTarget, 2110);
    });

    test('the chef reads the same target as the planner', () {
      final profile = _minhAnh(bmr: 1429, tdee: 1965);
      final shared = MemberHealthDto.fromJson(
          Map<String, dynamic>.from(MockBookingDb.memberHealthJson(profile)));
      expect(shared.dailyKcalTarget, 2060);
      expect(shared.summary, contains('≈ 2.060 kcal/ngày'));
      // A server that still sends an unrounded target reads the same.
      expect(const MemberHealthDto(dailyKcalTarget: 2063).summary,
          '≈ 2.060 kcal/ngày');
    });

    testWidgets('day card shows the target with the same rounding',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DailyMacroCard(
            date: DateTime(2026, 10, 17),
            totals: const Nutrition(
                calories: 2020, proteinG: 112, carbsG: 251, fatG: 63),
            targets: const Nutrition(
                calories: 2063, proteinG: 100, carbsG: 268, fatG: 67),
          ),
        ),
      ));
      expect(find.textContaining('2.020 / 2.060 kcal', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('2.063', findRichText: true), findsNothing);
    });

    testWidgets(
        'after a save, Thực đơn and Hồ sơ sức khoẻ read the same need and '
        'target', (tester) async {
      // The QA step: save the profile (adds "lá lốt"), so the server caches
      // its rounded bmr/tdee.
      final saving = MockMealPlannerRepository(userId: 'u_me')
          .updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 172,
        weightKg: 66,
        goal: HealthGoal.leanMuscle,
        allergies: ['peanut', 'lá lốt'],
        dietaryRestrictions: ['low_sodium'],
      ));
      await tester.pump(const Duration(seconds: 2));
      final cached = await saving;
      expect(cached.tdee, cached.tdee!.roundToDouble());

      final exact = Energy.tdee(
          Energy.bmr(
              gender: Gender.female,
              weightKg: 66,
              heightCm: 172,
              age: Energy.ageFrom(1997)),
          ActivityLevel.light);
      final need = Energy.formatKcal(exact);
      final target =
          Energy.formatKcal(Energy.dailyTarget(exact, 0.05)); // Tăng cơ
      await _pump(tester, const MealPlannerScreen(),
          session: _session('u_me', 'Minh Anh'));
      await _wait(tester);
      expect(
          find.textContaining('Nhu cầu ≈ $need kcal/ngày', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('/ $target kcal', findRichText: true),
          findsOneWidget);

      await tester.tap(find.byType(HealthHeaderCard));
      await _wait(tester);
      expect(find.text('Nhu cầu ≈ $need kcal/ngày'), findsOneWidget);
      expect(find.textContaining('thực đơn nhắm $target kcal'), findsOneWidget);
    });

    test('a save that changes the target re-aims the week (day cards follow)',
        () async {
      final container = _container('u_me');
      container.listen(mealPlanControllerProvider, (_, __) {});
      final before = await container.read(mealPlanControllerProvider.future);
      expect(before.plan!.dailyTargets.calories, 2060);

      // QA step: Mức vận động Nhẹ → Vừa, Lưu (editor read "nhắm 2.330").
      final saved = await container
          .read(mealPlanControllerProvider.notifier)
          .updateHealthProfile(
            heightCm: 172,
            weightKg: 66,
            goal: HealthGoal.leanMuscle,
            allergies: const ['peanut'],
            dietaryRestrictions: const ['low_sodium'],
            gender: Gender.female,
            birthYear: DateTime.now().year - 29,
            activityLevel: ActivityLevel.moderate,
          );
      final target = saved.dailyKcalTarget!;
      expect(target, isNot(2060));
      expect(
          (await MockMealPlannerRepository(userId: 'u_me')
                  .getCurrentMealPlan())!
              .dailyTargets
              .calories,
          target,
          reason: 'the server re-aims the current week');

      // The planner reloads the week in the background.
      for (var i = 0; i < 20; i++) {
        final plan = container.read(mealPlanControllerProvider).value?.plan;
        if (plan?.dailyTargets.calories == target) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final after = container.read(mealPlanControllerProvider).requireValue;
      expect(after.plan!.dailyTargets.calories, target);
      expect(after.plan!.days.length, before.plan!.days.length,
          reason: 'same dishes, only the target changed');
    });
  });

  group('B8: "Hoàn tác" puts a fridge item back where it was', () {
    List<String> names(List<PantryItem> items) =>
        [for (final i in items) i.ingredient];

    test('controller and API keep the original order', () async {
      final container = _container('u_me');
      container.listen(pantryControllerProvider, (_, __) {});
      final notifier = container.read(pantryControllerProvider.notifier);
      final before = await container.read(pantryControllerProvider.future);
      expect(names(before), ['Đậu hũ', 'Cà chua', 'Nấm rơm', 'Gạo lứt']);

      final tomato = before[1];
      await notifier.remove(tomato);
      expect(names(container.read(pantryControllerProvider).requireValue),
          ['Đậu hũ', 'Nấm rơm', 'Gạo lứt']);
      await notifier.restore(tomato);
      final after = container.read(pantryControllerProvider).requireValue;
      expect(names(after), names(before));
      expect(after[1].source, PantrySource.scan, reason: 'still "Quét"');
      // A fresh read from the API agrees (no jump on the next refresh).
      expect([
        for (final p in await MockPantryRepository(userId: 'u_me').getPantry())
          p.ingredient
      ], names(before));

      // The last one too.
      final rice = after.last;
      await notifier.remove(rice);
      await notifier.restore(rice);
      expect(names(container.read(pantryControllerProvider).requireValue),
          names(before));
    });

    test('an undo tapped before the delete finished restores it once',
        () async {
      final container = _container('u_me');
      container.listen(pantryControllerProvider, (_, __) {});
      final notifier = container.read(pantryControllerProvider.notifier);
      final before = await container.read(pantryControllerProvider.future);
      final removal = notifier.remove(before[2]);
      final undo = notifier.restore(before[2]);
      await removal;
      await undo;
      expect(names(container.read(pantryControllerProvider).requireValue),
          names(before));
      expect(MockPantryRepository.itemsOf('u_me').map((p) => p.ingredient),
          names(before));
    });

    test('an API that lists the restored row on top: still back in place',
        () async {
      final container = _container('u_me', overrides: [
        pantryApiProvider.overrideWithValue(_NewestFirstPantry()),
      ]);
      container.listen(pantryControllerProvider, (_, __) {});
      final notifier = container.read(pantryControllerProvider.notifier);
      final before = await container.read(pantryControllerProvider.future);
      await notifier.remove(before[1]);
      await notifier.restore(before[1]);
      expect(names(container.read(pantryControllerProvider).requireValue),
          names(before));
    });

    testWidgets('swipe, then "Hoàn tác": the row is between its neighbours',
        (tester) async {
      await _pump(tester, const PantryScreen(),
          session: _session('u_me', 'Minh Anh'), size: const Size(411, 1400));
      await _wait(tester);
      await tester.drag(find.text('Cà chua'), const Offset(-500, 0));
      await tester.pump();
      await _wait(tester);
      expect(find.text('Cà chua'), findsNothing);
      await tester.tap(find.text('Hoàn tác'));
      await _wait(tester, 1000);
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('Đậu hũ'), lessThan(y('Cà chua')));
      expect(y('Cà chua'), lessThan(y('Nấm rơm')));
      expect(y('Nấm rơm'), lessThan(y('Gạo lứt')));
      await _wait(tester, 4000); // snackbar
    });

    // Flutter keeps a snackbar with an action until it is dismissed; on the
    // device "Hoàn tác" (and "Đã lưu hồ sơ sức khoẻ · Tạo lại thực đơn")
    // never left, covering the tab bar and swallowing swipes.
    for (final reader in [false, true]) {
      testWidgets(
          '"Hoàn tác" ${reader ? 'stays for a screen reader' : 'times out'}',
          (tester) async {
        await _pump(
            tester,
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(accessibleNavigation: reader),
                child: const PantryScreen(),
              ),
            ),
            session: _session('u_me', 'Minh Anh'),
            size: const Size(411, 1400));
        await _wait(tester);
        await tester.drag(find.text('Cà chua'), const Offset(-500, 0));
        await tester.pump();
        await _wait(tester);
        expect(find.text('Hoàn tác'), findsOneWidget);
        await _wait(tester, 6000);
        expect(find.text('Hoàn tác'), reader ? findsOneWidget : findsNothing);
      });
    }
  });
}
