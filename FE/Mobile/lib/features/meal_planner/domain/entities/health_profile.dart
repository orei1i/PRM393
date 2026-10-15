// lib/features/meal_planner/domain/entities/health_profile.dart
import '../../../../core/utils/bmi.dart';

enum HealthGoal {
  loseWeight('lose_weight', 'Giảm cân'),
  maintain('maintain', 'Giữ cân'),
  leanMuscle('lean_muscle', 'Tăng cơ'),
  gainWeight('gain_weight', 'Tăng cân');

  const HealthGoal(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static HealthGoal fromApi(String? value) =>
      values.firstWhere((g) => g.apiValue == value,
          orElse: () => HealthGoal.maintain);
}

enum HealthSyncProvider {
  appleHealth('apple_health', 'Apple Health'),
  healthConnect('health_connect', 'Health Connect'),
  // Google Fit APIs are being retired; kept for older accounts.
  googleFit('google_fit', 'Google Fit'),
  none('none', 'Chưa kết nối');

  const HealthSyncProvider(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static HealthSyncProvider fromApi(String? value) =>
      values.firstWhere((p) => p.apiValue == value,
          orElse: () => HealthSyncProvider.none);
}

enum HealthSyncState {
  synced('synced'),
  syncing('syncing'),
  paused('paused');

  const HealthSyncState(this.apiValue);
  final String apiValue;

  static HealthSyncState fromApi(String? value) =>
      values.firstWhere((s) => s.apiValue == value,
          orElse: () => HealthSyncState.paused);
}

class HealthSync {
  const HealthSync(
      {required this.provider, required this.state, this.lastSyncedAt});

  final HealthSyncProvider provider;
  final HealthSyncState state;
  final DateTime? lastSyncedAt;
}

class HealthProfile {
  const HealthProfile({
    required this.heightCm,
    required this.weightKg,
    required this.bmi,
    required this.goal,
    this.allergies = const [],
    this.dietaryRestrictions = const [],
    this.healthSync = const HealthSync(
        provider: HealthSyncProvider.none, state: HealthSyncState.paused),
  });

  final double heightCm;
  final double weightKg;

  /// Cached by the server; recomputed locally if missing.
  final double bmi;
  final HealthGoal goal;

  /// Allergen ids, e.g. `peanut`, `soy`, `gluten`.
  final List<String> allergies;
  final List<String> dietaryRestrictions;
  final HealthSync healthSync;

  BmiCategory bmiCategory([BmiStandard standard = BmiStandard.asiaPacific]) =>
      Bmi.categorize(bmi, standard: standard);
}
