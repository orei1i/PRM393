// test/body_metrics/body_metrics_controller_test.dart
//
// WP-B (item 6, AC6.1/AC6.4/AC6.5): a check-in updates the planner (profile
// and the week's energy targets), Tôi's health card and the history; the
// reminder follows its cadence and "Để sau"; a profile save that changes
// the weight shows up in the history.
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/body_progress.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/body_measurement.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/body_metrics_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';

import '../helpers/session_helpers.dart';

final _now = DateTime(2026, 10, 29, 9);

Future<(ProviderContainer, SharedPreferences)> _signedIn(
    MockAccount account) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    plannerClockProvider.overrideWithValue(() => _now),
  ]);
  addTearDown(container.dispose);
  await signInAs(container, account);
  container
    ..listen(mealPlanControllerProvider, (_, __) {})
    ..listen(bodyMeasurementsProvider, (_, __) {})
    ..listen(profileHealthProvider, (_, __) {})
    ..listen(checkInPromptProvider, (_, __) {});
  return (container, prefs);
}

/// Waits for the planner's background reload (mock latency ≈ 1 s).
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    MockAuthDb.reset();
    MockMealPlannerRepository.reset();
  });

  test('a check-in updates the planner, Tôi and the history', () async {
    final (container, _) = await _signedIn(minhAnhAccount);
    final planner = await container.read(mealPlanControllerProvider.future);
    final history = await container.read(bodyMeasurementsProvider.future);
    expect(history.first.weightKg, 66.0);
    expect(
        planner.plan!.dailyTargets.calories, planner.profile.dailyKcalTarget);
    expect(container.read(checkInPromptProvider)?.daysSinceLast, 8);

    final result = await container
        .read(bodyMeasurementsProvider.notifier)
        .log(weightKg: 65.4, waistCm: 70, bodyFatPct: 26.2);
    expect(result.measurement.weightKg, 65.4);
    expect(result.measurement.source, MeasurementSource.checkIn);
    expect(result.previous!.weightKg, 66.0);
    expect(result.profileBefore!.weightKg, 66.0);
    expect(result.profile.weightKg, 65.4);
    expect(result.profile.bmi, 22.1);
    final review = result.review;
    expect(review.weightRow, 'Cân nặng: 66,0 → 65,4 kg (−0,6 kg)');
    expect(review.waistRow, 'Vòng eo: 70 → 70 cm · WHtR 0,41');
    expect(review.bodyFatRow, isNull);
    expect(review.targetBefore, planner.profile.dailyKcalTarget);
    expect(review.targetAfter, result.profile.dailyKcalTarget);

    // History: the new row on top; nothing due any more.
    final after = container.read(bodyMeasurementsProvider).requireValue;
    expect(after, hasLength(history.length + 1));
    expect(after.first.weightKg, 65.4);
    expect(container.read(checkInPromptProvider), isNull);

    // Thực đơn: the header at once, the day cards' target after a reload.
    final state = container.read(mealPlanControllerProvider).requireValue;
    expect(state.profile.weightKg, 65.4);
    expect(state.profile.bmi, 22.1);
    final target = result.profile.dailyKcalTarget!;
    await _until(() =>
        container
            .read(mealPlanControllerProvider)
            .value
            ?.plan
            ?.dailyTargets
            .calories ==
        target);
    expect(
        container
            .read(mealPlanControllerProvider)
            .requireValue
            .plan!
            .dailyTargets
            .calories,
        target);

    // Tôi: refreshed from the server.
    final me = (await container.read(profileHealthProvider.future))!;
    expect(me.weightKg, 65.4);
    expect(me.bmi, 22.1);
  });

  test('a failed check-in (99.9) changes nothing', () async {
    final (container, _) = await _signedIn(minhAnhAccount);
    await container.read(mealPlanControllerProvider.future);
    final history = await container.read(bodyMeasurementsProvider.future);
    await expectLater(
        container.read(bodyMeasurementsProvider.notifier).log(weightKg: 99.9),
        throwsA(anything));
    expect(container.read(bodyMeasurementsProvider).requireValue, history);
    expect(
        container
            .read(mealPlanControllerProvider)
            .requireValue
            .profile
            .weightKg,
        66);
  });

  test('applySavedProfile with no planner loaded yet just reloads it',
      () async {
    final (container, _) = await _signedIn(minhAnhAccount);
    final notifier = container.read(mealPlanControllerProvider.notifier);
    final result = await container
        .read(bodyMeasurementsProvider.notifier)
        .log(weightKg: 65.0);
    await notifier.applySavedProfile(result.profile);
    final state = await container.read(mealPlanControllerProvider.future);
    expect(state.profile.weightKg, 65.0);
  });

  test('a profile save that changes the weight adds a "profile" row', () async {
    final (container, _) = await _signedIn(minhAnhAccount);
    final planner = await container.read(mealPlanControllerProvider.future);
    final before = await container.read(bodyMeasurementsProvider.future);
    final p = planner.profile;
    await container
        .read(mealPlanControllerProvider.notifier)
        .updateHealthProfile(
          heightCm: p.heightCm,
          weightKg: 65.0,
          goal: p.goal,
          allergies: p.allergies,
          dietaryRestrictions: p.dietaryRestrictions,
          gender: p.gender,
          birthYear: p.birthYear,
          activityLevel: p.activityLevel,
          mealPattern: p.mealPattern,
        );
    final after = await container.read(bodyMeasurementsProvider.future);
    expect(after, hasLength(before.length + 1));
    expect(after.first.weightKg, 65.0);
    expect(after.first.source, MeasurementSource.profile);
  });

  group('reminder (AC6.4)', () {
    test('"Để sau" hides it today and is kept per account', () async {
      final (container, prefs) = await _signedIn(minhAnhAccount);
      await container.read(mealPlanControllerProvider.future);
      await container.read(bodyMeasurementsProvider.future);
      expect(container.read(checkInPromptProvider), isNotNull);

      await container.read(checkInPrefsProvider.notifier).snoozeToday();
      expect(container.read(checkInPromptProvider), isNull);
      expect(prefs.getString('vl.checkin.snoozed.u_me'), '2026-10-29');
    });

    test('Mỗi tháng: 8 days since the last weigh-in is not due yet', () async {
      final (container, prefs) = await _signedIn(minhAnhAccount);
      await container.read(mealPlanControllerProvider.future);
      await container.read(bodyMeasurementsProvider.future);
      await container
          .read(checkInPrefsProvider.notifier)
          .setCadence(CheckInCadence.month);
      expect(container.read(checkInPromptProvider), isNull);
      expect(prefs.getString('vl.checkin.cadence.u_me'), 'month');
      await container
          .read(checkInPrefsProvider.notifier)
          .setCadence(CheckInCadence.week);
      expect(container.read(checkInPromptProvider)?.daysSinceLast, 8);
    });

    test('Tâm (20 days, weekly) is due; guests never', () async {
      final (container, _) = await _signedIn(tamChefAccount);
      await container.read(mealPlanControllerProvider.future);
      await container.read(bodyMeasurementsProvider.future);
      expect(container.read(checkInPromptProvider)?.daysSinceLast, 20);

      await container.read(sessionControllerProvider.notifier).signOut();
      expect(await container.read(bodyMeasurementsProvider.future), isEmpty);
      expect(container.read(checkInPromptProvider), isNull);
    });
  });
}
