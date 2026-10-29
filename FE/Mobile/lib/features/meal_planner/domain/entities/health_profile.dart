// lib/features/meal_planner/domain/entities/health_profile.dart
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/energy.dart';
import 'meal_slot.dart';

export '../../../../core/utils/energy.dart' show ActivityLevel, Gender;

enum HealthGoal {
  loseWeight('lose_weight', 'Giảm cân', -0.15),
  maintain('maintain', 'Giữ cân', 0),
  leanMuscle('lean_muscle', 'Tăng cơ', 0.05),
  gainWeight('gain_weight', 'Tăng cân', 0.10);

  const HealthGoal(this.apiValue, this.label, this.energyAdjustment);
  final String apiValue;
  final String label;

  /// Applied to the TDEE for the daily kcal target (−15 % / 0 / +5 % / +10 %).
  final double energyAdjustment;

  /// Also reads the server's short values (`lose`, `gain`) so both sides
  /// aim at the same calorie target; anything unknown → [maintain].
  static HealthGoal fromApi(String? value) => switch (value?.trim()) {
        'lose' => HealthGoal.loseWeight,
        'gain' => HealthGoal.gainWeight,
        final v => values.firstWhere((g) => g.apiValue == v,
            orElse: () => HealthGoal.maintain),
      };
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
    this.gender,
    this.birthYear,
    this.activityLevel = ActivityLevel.light,
    this.mealPattern = MealPattern.standard,
    double? bmr,
    double? tdee,
  })  : _bmr = bmr,
        _tdee = tdee;

  /// Stands in before the member has set a profile up (a new account,
  /// `GET /health-profile/me` → 404): no allergies, the standard meals of
  /// the day and no energy estimate. Screens check whether a profile exists
  /// and ask to set one up instead of showing these zeros.
  static const empty = HealthProfile(
      heightCm: 0, weightKg: 0, bmi: 0, goal: HealthGoal.maintain);

  final double heightCm;
  final double weightKg;

  /// Cached by the server; recomputed locally if missing.
  final double bmi;
  final HealthGoal goal;

  /// Allergy keys: allergen ids dishes are tagged with (`peanut`, `soy`,
  /// `gluten`…) or, for anything else, the name the member typed or picked
  /// ("Nấm", "lá lốt"). `allergenLabel` shows both.
  final List<String> allergies;
  final List<String> dietaryRestrictions;
  final HealthSync healthSync;

  /// `null` on profiles saved before "Giới tính" existed.
  final Gender? gender;

  /// `null` on profiles saved before "Năm sinh" existed.
  final int? birthYear;
  final ActivityLevel activityLevel;

  /// "Các bữa trong ngày", in day order (at least one slot).
  final List<MealSlot> mealPattern;

  final double? _bmr;
  final double? _tdee;

  /// "29 tuổi" this calendar year.
  int? get age => birthYear == null ? null : Energy.ageFrom(birthYear!);

  /// Gender and birth year are known, so the energy need can be estimated.
  bool get hasEnergyInputs => gender != null && birthYear != null;

  /// Mifflin–St Jeor from the inputs, unrounded. The server's cached `bmr`
  /// (rounded to whole kcal) is only a fallback when gender or birth year is
  /// missing: rounding it again for display could differ from the editor's
  /// live preview by 10 kcal.
  double? get bmr {
    final g = gender;
    final a = age;
    if (g == null || a == null) return _bmr;
    return Energy.bmr(
        gender: g, weightKg: weightKg, heightCm: heightCm, age: a);
  }

  /// BMR × activity, unrounded ("Nhu cầu ≈ 1.960 kcal/ngày" through
  /// [Energy.formatKcal]). Same fallback as [bmr].
  double? get tdee =>
      hasEnergyInputs ? Energy.tdee(bmr!, activityLevel) : _tdee;

  /// kcal/day the planner aims at: [tdee] adjusted for the [goal], to the
  /// nearest 10 kcal.
  int? get dailyKcalTarget {
    final t = tdee;
    return t == null ? null : Energy.dailyTarget(t, goal.energyAdjustment);
  }

  BmiCategory bmiCategory([BmiStandard standard = BmiStandard.asiaPacific]) =>
      Bmi.categorize(bmi, standard: standard);
}
