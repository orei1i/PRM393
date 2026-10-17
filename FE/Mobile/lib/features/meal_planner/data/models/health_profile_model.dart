// lib/features/meal_planner/data/models/health_profile_model.dart
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../../core/utils/labels.dart';
import '../../domain/allergy_match.dart';
import '../../domain/entities/health_profile.dart';
import '../../domain/entities/meal_slot.dart';

/// GET /health-profile/me
/// ```json
/// {
///   "heightCm": 172, "weightKg": 66, "bmi": 22.3,
///   "goal": "lean_muscle",
///   "gender": "Female", "birthYear": 1997, "activityLevel": "light",
///   "mealPattern": ["breakfast", "lunch", "snack_pm", "dinner"],
///   "allergies": [ { "allergenId": "peanut", "name": "Đậu phộng" },
///                  { "allergenId": null, "name": "lá lốt" } ],
///   "bmr": 1429, "tdee": 1965,
///   "dietaryRestrictions": ["low_sodium"],
///   "healthSync": { "provider": "apple_health", "status": "synced", "lastSyncedAt": "2026-10-14T03:10:00Z" }
/// }
/// ```
/// `gender`, `birthYear`, `activityLevel` and `mealPattern` live on
/// `health_profiles`; allergies on `user_allergies` (catalog id or a custom
/// name). Older servers send `allergies` as plain ids (`["peanut"]`) and no
/// pattern (→ 3 meals); both are read.
class HealthProfileDto {
  const HealthProfileDto({
    required this.heightCm,
    required this.weightKg,
    this.bmi,
    required this.goal,
    required this.allergies,
    required this.dietaryRestrictions,
    this.healthSync,
    this.gender,
    this.birthYear,
    this.activityLevel,
    this.mealPattern = const [],
    this.bmr,
    this.tdee,
  });

  factory HealthProfileDto.fromJson(Map<String, dynamic> json) =>
      HealthProfileDto(
        heightCm: readDouble(json['heightCm']),
        weightKg: readDouble(json['weightKg']),
        bmi: json['bmi'] == null ? null : readDouble(json['bmi']),
        goal: json['goal'] as String? ?? HealthGoal.maintain.apiValue,
        allergies: readAllergyKeys(json['allergies']),
        dietaryRestrictions: readStringList(json['dietaryRestrictions']),
        healthSync: json['healthSync'] is Map<String, dynamic>
            ? HealthSyncDto.fromJson(json['healthSync'] as Map<String, dynamic>)
            : null,
        gender: json['gender'] as String?,
        birthYear:
            json['birthYear'] == null ? null : readInt(json['birthYear']),
        activityLevel: json['activityLevel'] as String?,
        mealPattern:
            MealPattern.toApi(MealPattern.fromApi(json['mealPattern'])),
        bmr: json['bmr'] == null ? null : readDouble(json['bmr']),
        tdee: json['tdee'] == null ? null : readDouble(json['tdee']),
      );

  final double heightCm;
  final double weightKg;
  final double? bmi;
  final String goal;

  /// Allergy keys (see `HealthProfile.allergies`).
  final List<String> allergies;
  final List<String> dietaryRestrictions;
  final HealthSyncDto? healthSync;

  /// `Male` | `Female` | `Other`.
  final String? gender;
  final int? birthYear;

  /// `sedentary` | `light` | `moderate` | `active`.
  final String? activityLevel;

  /// Slot api values in day order.
  final List<String> mealPattern;
  final double? bmr;
  final double? tdee;

  Map<String, dynamic> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        if (bmi != null) 'bmi': bmi,
        'goal': goal,
        if (gender != null) 'gender': gender,
        if (birthYear != null) 'birthYear': birthYear,
        if (activityLevel != null) 'activityLevel': activityLevel,
        'mealPattern': mealPattern,
        'allergies': allergiesToJson(allergies),
        if (bmr != null) 'bmr': bmr,
        if (tdee != null) 'tdee': tdee,
        'dietaryRestrictions': dietaryRestrictions,
        if (healthSync != null) 'healthSync': healthSync!.toJson(),
      };

  HealthProfile toEntity() => HealthProfile(
        heightCm: heightCm,
        weightKg: weightKg,
        bmi: bmi ?? Bmi.calculate(heightCm: heightCm, weightKg: weightKg),
        goal: HealthGoal.fromApi(goal),
        allergies: allergies,
        dietaryRestrictions: dietaryRestrictions,
        healthSync: healthSync?.toEntity() ??
            const HealthSync(
                provider: HealthSyncProvider.none,
                state: HealthSyncState.paused),
        gender: Gender.fromApi(gender),
        birthYear: birthYear,
        activityLevel: ActivityLevel.fromApi(activityLevel),
        mealPattern: MealPattern.fromApi(mealPattern),
        bmr: bmr,
        tdee: tdee,
      );

  /// `["peanut"]` (legacy) or `[{ "allergenId", "name" }]` → keys: the
  /// allergen id when dishes are tagged with it, the name otherwise.
  static List<String> readAllergyKeys(Object? value) {
    if (value is! List<Object?>) return const [];
    final keys = <String>[];
    for (final item in value) {
      final key = switch (item) {
        final String id => id.trim(),
        final Map<String, dynamic> m => () {
            final id = m['allergenId']?.toString();
            final name = (m['name'] as String?)?.trim();
            if (id != null && isDishAllergenId(id)) return id;
            return (name == null || name.isEmpty) ? (id ?? '') : name;
          }(),
        _ => '',
      };
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }
    return keys;
  }

  /// Keys → `[{ "allergenId", "name" }]`; the server resolves custom names
  /// to catalog allergens itself (accent-insensitive).
  static List<Map<String, Object?>> allergiesToJson(Iterable<String> keys) => [
        for (final k in keys)
          {
            'allergenId': isDishAllergenId(k) ? k : null,
            'name': isDishAllergenId(k) ? allergenLabel(k) : k,
          },
      ];
}

/// PUT /health-profile/me → [HealthProfileDto] with the server-recomputed
/// `bmi` (the `health_profiles.bmi` cache), `bmr` and `tdee`. Fields left
/// `null` here keep their saved value.
class UpdateHealthProfileRequestDto {
  const UpdateHealthProfileRequestDto({
    required this.heightCm,
    required this.weightKg,
    required this.goal,
    required this.allergies,
    required this.dietaryRestrictions,
    this.gender,
    this.birthYear,
    this.activityLevel,
    this.mealPattern,
  });

  final double heightCm;
  final double weightKg;
  final HealthGoal goal;

  /// Allergy keys (ids or custom names).
  final List<String> allergies;

  /// Sent back unchanged (not edited on this screen).
  final List<String> dietaryRestrictions;
  final Gender? gender;
  final int? birthYear;
  final ActivityLevel? activityLevel;
  final List<MealSlot>? mealPattern;

  Map<String, dynamic> toJson() => {
        'heightCm': heightCm,
        'weightKg': weightKg,
        'goal': goal.apiValue,
        if (gender != null) 'gender': gender!.apiValue,
        if (birthYear != null) 'birthYear': birthYear,
        if (activityLevel != null) 'activityLevel': activityLevel!.apiValue,
        if (mealPattern != null) 'mealPattern': MealPattern.toApi(mealPattern!),
        'allergies': HealthProfileDto.allergiesToJson(allergies),
        'dietaryRestrictions': dietaryRestrictions,
      };
}

class HealthSyncDto {
  const HealthSyncDto(
      {required this.provider, required this.status, this.lastSyncedAt});

  factory HealthSyncDto.fromJson(Map<String, dynamic> json) => HealthSyncDto(
        provider: json['provider'] as String? ?? 'none',
        status: json['status'] as String? ?? 'paused',
        lastSyncedAt: readDateTime(json['lastSyncedAt']),
      );

  final String provider;
  final String status;
  final DateTime? lastSyncedAt;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'status': status,
        if (lastSyncedAt != null)
          'lastSyncedAt': lastSyncedAt!.toUtc().toIso8601String(),
      };

  HealthSync toEntity() => HealthSync(
        provider: HealthSyncProvider.fromApi(provider),
        state: HealthSyncState.fromApi(status),
        lastSyncedAt: lastSyncedAt,
      );
}
