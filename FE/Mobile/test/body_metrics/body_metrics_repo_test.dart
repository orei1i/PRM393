// test/body_metrics/body_metrics_repo_test.dart
//
// WP-B (item 6): the mock API for weigh-ins (spec §3.5, D12) — seeds dated
// from the planner clock, GET newest first, POST updates the profile and
// the week's targets, errors, profile saves logging `profile` rows, goal
// aliases (M5) and the `_findRecipe` fallback to the recipe catalogue.
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/body_measurement_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/body_measurement.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';

final _now = DateTime(2026, 10, 29, 9);
const _newUserId = 'u_reg_1_1760600000000';

MockMealPlannerRepository _repo(String? userId) =>
    MockMealPlannerRepository(userId: userId, clock: () => _now);

Matcher _apiError(int status, [String? message]) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.message, 'message', message ?? anything);

void main() {
  setUp(MockMealPlannerRepository.reset);

  group('GET /health-profile/me/metrics', () {
    test('Minh Anh: seeds relative to the clock, newest first', () async {
      final rows = await _repo('u_me').getBodyMeasurements();
      expect([for (final r in rows) r.weightKg],
          [66.0, 65.8, 65.6, 65.3, 65.2, 65.0]);
      expect([for (final r in rows) _now.difference(r.loggedAt).inDays],
          [8, 14, 21, 28, 42, 56]);
      expect(rows.first.waistCm, 70);
      expect(rows.first.bmi, 22.3);
      expect(rows[1].bodyFatPct, 27.0);
      expect(rows.last.source, 'profile');
      expect(rows.last.waistCm, 71);
      expect(rows.last.bodyFatPct, 27.8);
      expect(
          [for (final r in rows.take(5)) r.source], everyElement('check_in'));
      expect(rows.every((r) => r.heightCm == 172), isTrue);
      final entity = rows.last.toEntity();
      expect(entity.source, MeasurementSource.profile);
      expect(entity.bmi, 22.0);
    });

    test('Tâm has his profile row; a new account has none', () async {
      final tam = await _repo('u_chef_tam').getBodyMeasurements();
      expect(tam, hasLength(1));
      expect(tam.single.weightKg, 63.0);
      expect(tam.single.source, 'profile');
      expect(_now.difference(tam.single.loggedAt).inDays, 20);
      expect(await _repo(_newUserId).getBodyMeasurements(), isEmpty);
    });

    test('limit and guests', () async {
      expect(await _repo('u_me').getBodyMeasurements(limit: 2), hasLength(2));
      await expectLater(
          _repo(null).getBodyMeasurements(), throwsA(_apiError(401)));
    });

    test('wire format: no source → profile, BMI computed when missing', () {
      final dto = BodyMeasurementDto.fromJson({
        'id': 7,
        'weightKg': 65.4,
        'heightCm': 172,
        'loggedAt': '2026-10-21T01:00:00Z',
      });
      final m = dto.toEntity();
      expect(m.id, '7');
      expect(m.source, MeasurementSource.profile);
      expect(m.bmi, 22.1);
      expect(m.waistCm, isNull);
      expect(m.loggedAt.isUtc, isFalse, reason: 'shown in local time');
    });
  });

  group('POST /health-profile/me/metrics', () {
    test('65,4 kg: logs a check-in, recomputes the profile and the week',
        () async {
      final repo = _repo('u_me');
      final before = (await repo.getHealthProfile())!.toEntity();
      expect((await repo.getCurrentMealPlan())!.dailyTargets.calories,
          before.dailyKcalTarget);

      final result = await repo.logBodyMeasurement(
          const LogMeasurementRequestDto(
              weightKg: 65.4, waistCm: 70, bodyFatPct: 26.2));
      expect(result.measurement.source, 'check_in');
      expect(result.measurement.weightKg, 65.4);
      expect(result.measurement.heightCm, 172);
      expect(result.measurement.bmi, 22.1);
      expect(result.measurement.waistCm, 70);
      expect(result.measurement.bodyFatPct, 26.2);
      expect(result.measurement.loggedAt, _now);

      final profile = result.profile.toEntity();
      expect(profile.weightKg, 65.4);
      expect(profile.bmi, 22.1);
      expect(profile.heightCm, 172);
      expect(profile.goal, HealthGoal.leanMuscle);
      expect(profile.allergies, before.allergies);
      expect(profile.mealPattern, before.mealPattern);
      expect(profile.gender, before.gender);
      expect(profile.birthYear, before.birthYear);
      expect(result.profile.bmr, profile.bmr!.roundToDouble());

      // The saved profile, the history and the week follow.
      expect((await repo.getHealthProfile())!.weightKg, 65.4);
      final rows = await repo.getBodyMeasurements();
      expect(rows, hasLength(7));
      expect(rows.first.weightKg, 65.4);
      expect((await repo.getCurrentMealPlan())!.dailyTargets.calories,
          profile.dailyKcalTarget);
    });

    test('99.9 kg → 503 and nothing saved', () async {
      final repo = _repo('u_me');
      await expectLater(
          repo.logBodyMeasurement(
              const LogMeasurementRequestDto(weightKg: 99.9)),
          throwsA(
              _apiError(503, 'Chưa lưu được cân nặng. Thử lại sau ít phút.')));
      expect(await repo.getBodyMeasurements(), hasLength(6));
      expect((await repo.getHealthProfile())!.weightKg, 66);
    });

    test('ranges → 400', () async {
      final repo = _repo('u_me');
      await expectLater(
          repo.logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 29)),
          throwsA(_apiError(400, 'Cân nặng từ 30 đến 250 kg')));
      await expectLater(
          repo.logBodyMeasurement(
              const LogMeasurementRequestDto(weightKg: 65, waistCm: 39)),
          throwsA(_apiError(400, 'Vòng eo từ 40 đến 200 cm')));
      await expectLater(
          repo.logBodyMeasurement(
              const LogMeasurementRequestDto(weightKg: 65, bodyFatPct: 71)),
          throwsA(_apiError(400, 'Tỉ lệ mỡ từ 3 đến 70 %')));
    });

    test('no profile → 404; guest → 401', () async {
      await expectLater(
          _repo(_newUserId)
              .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 60)),
          throwsA(_apiError(404, 'Bạn chưa tạo hồ sơ sức khỏe.')));
      await expectLater(
          _repo(null)
              .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 60)),
          throwsA(_apiError(401)));
    });
  });

  group('PUT /health-profile/me logs a `profile` row on a weight change', () {
    UpdateHealthProfileRequestDto request(double kg) =>
        UpdateHealthProfileRequestDto(
          heightCm: 172,
          weightKg: kg,
          goal: HealthGoal.leanMuscle,
          allergies: const ['peanut'],
          dietaryRestrictions: const ['low_sodium'],
        );

    test('66 → 65 kg adds one; unchanged (±0,05) adds none', () async {
      final repo = _repo('u_me');
      await repo.updateHealthProfile(request(66.04));
      expect(await repo.getBodyMeasurements(), hasLength(6));

      await repo.updateHealthProfile(request(65));
      final rows = await repo.getBodyMeasurements();
      expect(rows, hasLength(7));
      expect(rows.first.source, 'profile');
      expect(rows.first.weightKg, 65);
      expect(rows.first.bmi, 22.0);
      expect(rows.first.loggedAt, _now);
    });

    test("a new account's first save writes its first row", () async {
      final repo = _repo(_newUserId);
      await repo.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 160,
        weightKg: 52,
        goal: HealthGoal.maintain,
        allergies: [],
        dietaryRestrictions: [],
      ));
      final rows = await repo.getBodyMeasurements();
      expect(rows, hasLength(1));
      expect(rows.single.source, 'profile');
      expect(rows.single.heightCm, 160);
    });
  });

  group('M5: the server goal values', () {
    test('lose / gain read as Giảm cân / Tăng cân', () {
      expect(HealthGoal.fromApi('lose'), HealthGoal.loseWeight);
      expect(HealthGoal.fromApi('gain'), HealthGoal.gainWeight);
      expect(HealthGoal.fromApi('lose_weight'), HealthGoal.loseWeight);
      expect(HealthGoal.fromApi('gain_weight'), HealthGoal.gainWeight);
      expect(HealthGoal.fromApi('lean_muscle'), HealthGoal.leanMuscle);
      expect(HealthGoal.fromApi('maintain'), HealthGoal.maintain);
      expect(HealthGoal.fromApi(null), HealthGoal.maintain);
      expect(HealthGoal.fromApi('bulk'), HealthGoal.maintain);
    });

    test('a BE profile with goal "lose" aims 15 % under the TDEE', () {
      final profile = HealthProfileDto.fromJson({
        'heightCm': 172,
        'weightKg': 66,
        'goal': 'lose',
        'gender': 'Female',
        'birthYear': DateTime.now().year - 29,
        'activityLevel': 'light',
      }).toEntity();
      expect(profile.goal, HealthGoal.loseWeight);
      expect(profile.goal.label, 'Giảm cân');
      expect(profile.goal.energyAdjustment, -0.15);
      expect(profile.dailyKcalTarget, Energy.dailyTarget(profile.tdee!, -0.15));
    });
  });

  test('a catalogue recipe outside the planner pool can be placed (menu_2)',
      () async {
    final repo = _repo('u_me');
    final plan = (await repo.getCurrentMealPlan())!;
    final day = await repo.swapMeal(
      planId: plan.id,
      request: SwapMealRequestDto(
        date: _now,
        slot: MealSlot.dinner,
        recipeId: 'menu_2',
        source: MealSource.recipe,
      ),
    );
    final dinner = day.meals[MealSlot.dinner.apiValue]!;
    expect(dinner.id, 'menu_2');
    expect(dinner.source, 'recipe');
    expect(dinner.nutrition.calories, greaterThan(0));
    await expectLater(
        repo.swapMeal(
          planId: plan.id,
          request: SwapMealRequestDto(
              date: _now, slot: MealSlot.dinner, recipeId: 'nope'),
        ),
        throwsA(_apiError(404)));
  });
}
