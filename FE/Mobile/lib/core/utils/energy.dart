// lib/core/utils/energy.dart
//
// Daily energy need from the health profile ("Hồ sơ sức khoẻ"): BMR with the
// Mifflin–St Jeor equation, TDEE from the activity level, then the goal
// adjustment. Estimates for meal planning only, not medical advice.
//
// The single source of truth for these numbers: every screen (Hồ sơ sức
// khoẻ, the Thực đơn header and day card, the booking request a chef reads)
// computes them here from the unrounded inputs and shows them through
// [Energy.formatKcal], so one profile never reads "1.960" in one place and
// "1.970" in another.

import 'formatters.dart';

/// "Giới tính" (`health_profiles.gender`): Male / Female / Other on the wire.
enum Gender {
  male('Male', 'Nam', 5),
  female('Female', 'Nữ', -161),

  /// Mifflin–St Jeor has no constant for it: the mean of the two.
  other('Other', 'Khác', -78);

  const Gender(this.apiValue, this.label, this.bmrConstant);

  final String apiValue;
  final String label;

  /// The `s` term of 10·kg + 6,25·cm − 5·tuổi + s.
  final double bmrConstant;

  /// Case-insensitive; `null` when missing or unknown (legacy profiles).
  static Gender? fromApi(String? value) {
    final v = value?.trim().toLowerCase();
    for (final g in values) {
      if (g.apiValue.toLowerCase() == v) return g;
    }
    return null;
  }
}

/// "Mức vận động" (`health_profiles.activity_level`) and its TDEE factor.
enum ActivityLevel {
  sedentary('sedentary', 'Ít', 'Ít vận động, chủ yếu ngồi', 1.2),
  light('light', 'Nhẹ', 'Tập nhẹ 1–3 buổi mỗi tuần', 1.375),
  moderate('moderate', 'Vừa', 'Tập vừa 3–5 buổi mỗi tuần', 1.55),
  active('active', 'Nhiều', 'Tập nặng 6–7 buổi mỗi tuần', 1.725);

  const ActivityLevel(this.apiValue, this.label, this.description, this.factor);

  final String apiValue;

  /// "Ít" / "Nhẹ" / "Vừa" / "Nhiều".
  final String label;
  final String description;
  final double factor;

  /// Missing or unknown → [light].
  static ActivityLevel fromApi(String? value) =>
      values.firstWhere((a) => a.apiValue == value?.trim().toLowerCase(),
          orElse: () => ActivityLevel.light);
}

abstract final class Energy {
  /// Ages the estimate is meant for ("Năm sinh không hợp lệ (13–100 tuổi)").
  static const minAge = 13;
  static const maxAge = 100;

  /// Age this calendar year ("29 tuổi").
  static int ageFrom(int birthYear, {DateTime? now}) =>
      (now ?? DateTime.now()).year - birthYear;

  static bool isValidBirthYear(int birthYear, {DateTime? now}) {
    final age = ageFrom(birthYear, now: now);
    return age >= minAge && age <= maxAge;
  }

  /// Mifflin–St Jeor, kcal/day.
  static double bmr({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
  }) =>
      10 * weightKg + 6.25 * heightCm - 5 * age + gender.bmrConstant;

  /// kcal/day with daily activity.
  static double tdee(double bmr, ActivityLevel activity) =>
      bmr * activity.factor;

  /// The planner's daily kcal target: [tdee] adjusted by the goal (for
  /// example −0,15 to lose weight, +0,10 to gain), to the nearest 10 kcal
  /// like everything shown ("thực đơn nhắm 2.060 kcal", the day card's
  /// "… / 2.060 kcal", the chef's "≈ 2.060 kcal/ngày").
  static int dailyTarget(double tdee, double goalAdjustment) =>
      roundForDisplay(tdee * (1 + goalAdjustment));

  /// The one rounding rule for energy estimates: to the nearest 10 kcal
  /// (1.964,9 → 1.960; 1.965 → 1.970). Round the exact value once; rounding
  /// an already rounded one (1.964,9 → 1.965 → 1.970) is what made screens
  /// disagree.
  static int roundForDisplay(num kcal) => (kcal / 10).round() * 10;

  /// An energy estimate as shown: 1964.875 → "1.960", 2063 → "2.060".
  static String formatKcal(num kcal) => formatInt(roundForDisplay(kcal));
}
