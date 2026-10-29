// lib/features/meal_planner/presentation/controllers/body_metrics_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/utils/formatters.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../data/meal_planner_api_service.dart';
import '../../data/models/body_measurement_model.dart';
import '../../domain/body_progress.dart';
import '../../domain/entities/body_measurement.dart';
import '../../domain/entities/health_profile.dart';
import 'meal_plan_controller.dart';

/// A saved weigh-in and what the progress review compares.
class CheckInResult {
  const CheckInResult({
    required this.measurement,
    required this.profile,
    this.previous,
    this.profileBefore,
  });

  final BodyMeasurement measurement;

  /// The latest weigh-in before this one (`null` for the first).
  final BodyMeasurement? previous;

  /// The health profile before the weigh-in, when it was known.
  final HealthProfile? profileBefore;

  /// The profile the server recomputed from the new weight.
  final HealthProfile profile;

  ProgressReview get review => ProgressReview.of(
        current: measurement,
        previous: previous,
        before: profileBefore,
        after: profile,
      );
}

/// The member's weigh-ins, newest first (none for guests). Reloads on an
/// account change and after a "Hồ sơ sức khoẻ" save (which can log a row).
final bodyMeasurementsProvider =
    AsyncNotifierProvider<BodyMetricsController, List<BodyMeasurement>>(
        BodyMetricsController.new);

class BodyMetricsController extends AsyncNotifier<List<BodyMeasurement>> {
  @override
  Future<List<BodyMeasurement>> build() async {
    final api = ref.watch(mealPlannerApiProvider);
    if (ref.watch(plannerUserIdProvider) == null) return const [];
    final rows = await api.getBodyMeasurements();
    return [for (final r in rows) r.toEntity()]
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  /// "Cập nhật cân nặng": logs the weigh-in; the planner (header, energy
  /// targets of the week) and Tôi follow the recomputed profile. Throws on
  /// failure (the sheet keeps the input).
  Future<CheckInResult> log({
    required double weightKg,
    double? waistCm,
    double? bodyFatPct,
  }) async {
    final api = ref.read(mealPlannerApiProvider);
    List<BodyMeasurement>? history;
    try {
      history = state.valueOrNull ?? await future;
    } catch (_) {
      history = null; // unknown: reloaded after the save
    }
    final before = await _currentProfile();
    final result = await api.logBodyMeasurement(LogMeasurementRequestDto(
      weightKg: weightKg,
      waistCm: waistCm,
      bodyFatPct: bodyFatPct,
    ));
    final measurement = result.measurement.toEntity();
    final profile = result.profile.toEntity();
    if (history != null) {
      state = AsyncData([measurement, ...history]);
    } else {
      ref.invalidateSelf();
    }
    if (ref.exists(mealPlanControllerProvider)) {
      unawaited(ref
          .read(mealPlanControllerProvider.notifier)
          .applySavedProfile(profile));
    }
    ref.invalidate(profileHealthProvider);
    return CheckInResult(
      measurement: measurement,
      previous: history?.firstOrNull,
      profileBefore: before,
      profile: profile,
    );
  }

  /// The profile on screen (planner or Tôi), else a fresh read.
  Future<HealthProfile?> _currentProfile() async {
    if (ref.exists(mealPlanControllerProvider)) {
      final planner = ref.read(mealPlanControllerProvider).valueOrNull;
      if (planner != null) return planner.healthProfile;
    }
    if (ref.exists(profileHealthProvider)) {
      final shown = ref.read(profileHealthProvider);
      if (shown.hasValue && !shown.hasError) return shown.value;
    }
    try {
      return (await ref.read(mealPlannerApiProvider).getHealthProfile())
          ?.toEntity();
    } catch (_) {
      return null; // the review just leaves the energy row out
    }
  }
}

/// Per-account reminder settings, kept on the device.
class CheckInPrefs {
  const CheckInPrefs({this.cadence = CheckInCadence.week, this.snoozedOn});

  final CheckInCadence cadence;

  /// "Để sau" was tapped on this day (`yyyy-MM-dd`).
  final String? snoozedOn;
}

final checkInPrefsProvider =
    NotifierProvider<CheckInPrefsController, CheckInPrefs>(
        CheckInPrefsController.new);

class CheckInPrefsController extends Notifier<CheckInPrefs> {
  static String cadenceKey(String userId) => 'vl.checkin.cadence.$userId';
  static String snoozeKey(String userId) => 'vl.checkin.snoozed.$userId';

  /// Bare test containers have no SharedPreferences: kept in memory.
  SharedPreferences? get _prefs {
    try {
      return ref.read(sharedPreferencesProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  CheckInPrefs build() {
    final userId = ref.watch(plannerUserIdProvider);
    final prefs = _prefs;
    if (userId == null || prefs == null) return const CheckInPrefs();
    return CheckInPrefs(
      cadence: CheckInCadence.fromPrefs(prefs.getString(cadenceKey(userId))),
      snoozedOn: prefs.getString(snoozeKey(userId)),
    );
  }

  /// "Nhắc cập nhật cân nặng": Mỗi tuần / Mỗi tháng.
  Future<void> setCadence(CheckInCadence cadence) async {
    state = CheckInPrefs(cadence: cadence, snoozedOn: state.snoozedOn);
    final userId = ref.read(plannerUserIdProvider);
    if (userId != null) {
      await _prefs?.setString(cadenceKey(userId), cadence.prefsValue);
    }
  }

  /// "Để sau": no reminder again until tomorrow.
  Future<void> snoozeToday() async {
    final today = toApiDate(ref.read(plannerClockProvider)());
    state = CheckInPrefs(cadence: state.cadence, snoozedOn: today);
    final userId = ref.read(plannerUserIdProvider);
    if (userId != null) await _prefs?.setString(snoozeKey(userId), today);
  }
}

/// Why the Thực đơn tab shows "Cập nhật cân nặng" now; `null` → hidden
/// (guest, no profile or plan this week, snoozed today, weighed recently,
/// or still loading).
final checkInPromptProvider = Provider<CheckInPrompt?>((ref) {
  final userId = ref.watch(plannerUserIdProvider);
  if (userId == null) return null;
  final planner = ref.watch(mealPlanControllerProvider).valueOrNull;
  final history = ref.watch(bodyMeasurementsProvider).valueOrNull;
  if (planner == null || history == null) return null;
  final prefs = ref.watch(checkInPrefsProvider);
  final now = ref.watch(plannerClockProvider)();
  return BodyProgress.checkInPrompt(
    signedIn: true,
    hasProfile: planner.hasHealthProfile,
    hasPlan: planner.plan?.dayFor(dateOnly(now)) != null,
    cadence: prefs.cadence,
    snoozedOn: prefs.snoozedOn,
    lastLoggedAt: history.firstOrNull?.loggedAt,
    now: now,
  );
});
