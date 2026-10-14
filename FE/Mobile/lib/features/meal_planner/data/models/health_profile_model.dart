// lib/features/meal_planner/data/models/health_profile_model.dart
import '../../../../core/utils/bmi.dart';
import '../../domain/entities/health_profile.dart';
import '../../../../core/utils/json_helpers.dart';

/// GET /health-profile/me
/// ```json
/// {
///   "height_cm": 172, "weight_kg": 66, "bmi": 22.3,
///   "goal": "lean_muscle",
///   "allergies": ["peanut"], "dietary_restrictions": ["low_sodium"],
///   "health_sync": { "provider": "apple_health", "status": "synced", "last_synced_at": "2026-10-14T03:10:00Z" }
/// }
/// ```
class HealthProfileDto {
  const HealthProfileDto({
    required this.heightCm,
    required this.weightKg,
    this.bmi,
    required this.goal,
    required this.allergies,
    required this.dietaryRestrictions,
    this.healthSync,
  });

  factory HealthProfileDto.fromJson(Map<String, dynamic> json) => HealthProfileDto(
        heightCm: readDouble(json['height_cm']),
        weightKg: readDouble(json['weight_kg']),
        bmi: json['bmi'] == null ? null : readDouble(json['bmi']),
        goal: json['goal'] as String? ?? HealthGoal.maintain.apiValue,
        allergies: readStringList(json['allergies']),
        dietaryRestrictions: readStringList(json['dietary_restrictions']),
        healthSync: json['health_sync'] is Map<String, dynamic>
            ? HealthSyncDto.fromJson(json['health_sync'] as Map<String, dynamic>)
            : null,
      );

  final double heightCm;
  final double weightKg;
  final double? bmi;
  final String goal;
  final List<String> allergies;
  final List<String> dietaryRestrictions;
  final HealthSyncDto? healthSync;

  Map<String, dynamic> toJson() => {
        'height_cm': heightCm,
        'weight_kg': weightKg,
        if (bmi != null) 'bmi': bmi,
        'goal': goal,
        'allergies': allergies,
        'dietary_restrictions': dietaryRestrictions,
        if (healthSync != null) 'health_sync': healthSync!.toJson(),
      };

  HealthProfile toEntity() => HealthProfile(
        heightCm: heightCm,
        weightKg: weightKg,
        bmi: bmi ?? Bmi.calculate(heightCm: heightCm, weightKg: weightKg),
        goal: HealthGoal.fromApi(goal),
        allergies: allergies,
        dietaryRestrictions: dietaryRestrictions,
        healthSync: healthSync?.toEntity() ??
            const HealthSync(provider: HealthSyncProvider.none, state: HealthSyncState.paused),
      );
}

class HealthSyncDto {
  const HealthSyncDto({required this.provider, required this.status, this.lastSyncedAt});

  factory HealthSyncDto.fromJson(Map<String, dynamic> json) => HealthSyncDto(
        provider: json['provider'] as String? ?? 'none',
        status: json['status'] as String? ?? 'paused',
        lastSyncedAt: readDateTime(json['last_synced_at']),
      );

  final String provider;
  final String status;
  final DateTime? lastSyncedAt;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'status': status,
        if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt!.toUtc().toIso8601String(),
      };

  HealthSync toEntity() => HealthSync(
        provider: HealthSyncProvider.fromApi(provider),
        state: HealthSyncState.fromApi(status),
        lastSyncedAt: lastSyncedAt,
      );
}
