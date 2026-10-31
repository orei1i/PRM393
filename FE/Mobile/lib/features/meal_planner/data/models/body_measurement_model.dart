// lib/features/meal_planner/data/models/body_measurement_model.dart
//
// GET /health-profile/me/metrics?limit=100 → newest first
// [ { "id": "m_1", "weightKg": 66.0, "heightCm": 172, "bmi": 22.3,
//     "waistCm": 70, "bodyFatPct": 27.0, "source": "check_in",
//     "loggedAt": "2026-10-21T01:00:00Z" } ]
// `waistCm`, `bodyFatPct` and `source` are optional (older servers send
// neither; a row without `source` came from a profile save).
//
// POST /health-profile/me/metrics   { "weightKg": 65.4, "waistCm": 70, "bodyFatPct": 26.2 }
// → 201 { "measurement": { …, "source": "check_in" }, "profile": HealthProfileDto }
// The server uses the saved height, recomputes BMI/BMR/TDEE, updates the
// profile and the current week's targets (like PUT /health-profile/me) and
// logs one row.
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/body_measurement.dart';
import 'health_profile_model.dart';

class BodyMeasurementDto {
  const BodyMeasurementDto({
    required this.id,
    required this.weightKg,
    required this.heightCm,
    required this.loggedAt,
    this.bmi,
    this.waistCm,
    this.bodyFatPct,
    this.source,
  });

  factory BodyMeasurementDto.fromJson(Map<String, dynamic> json) {
    double? optional(String key) =>
        json[key] == null ? null : readDouble(json[key]);
    return BodyMeasurementDto(
      id: json['id']?.toString() ?? '',
      weightKg: readDouble(json['weightKg']),
      heightCm: readDouble(json['heightCm']),
      bmi: optional('bmi'),
      waistCm: optional('waistCm'),
      bodyFatPct: optional('bodyFatPct'),
      source: json['source'] as String?,
      loggedAt: readDateTime(json['loggedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final double weightKg;
  final double heightCm;

  /// Server value (one decimal); computed from weight and height if missing.
  final double? bmi;
  final double? waistCm;
  final double? bodyFatPct;

  /// `profile` | `check_in`; missing → `profile`.
  final String? source;
  final DateTime loggedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'weightKg': weightKg,
        'heightCm': heightCm,
        if (bmi != null) 'bmi': bmi,
        if (waistCm != null) 'waistCm': waistCm,
        if (bodyFatPct != null) 'bodyFatPct': bodyFatPct,
        if (source != null) 'source': source,
        'loggedAt': loggedAt.toUtc().toIso8601String(),
      };

  BodyMeasurement toEntity() => BodyMeasurement(
        id: id,
        weightKg: weightKg,
        heightCm: heightCm,
        bmi: bmi ??
            (Bmi.calculate(heightCm: heightCm, weightKg: weightKg) * 10)
                    .roundToDouble() /
                10,
        waistCm: waistCm,
        bodyFatPct: bodyFatPct,
        source: MeasurementSource.fromApi(source),
        loggedAt: loggedAt,
      );
}

/// POST /health-profile/me/metrics ("Cập nhật cân nặng"). Height is the
/// saved one; waist and body fat are optional.
class LogMeasurementRequestDto {
  const LogMeasurementRequestDto({
    required this.weightKg,
    this.waistCm,
    this.bodyFatPct,
  });

  final double weightKg;
  final double? waistCm;
  final double? bodyFatPct;

  Map<String, dynamic> toJson() => {
        'weightKg': weightKg,
        if (waistCm != null) 'waistCm': waistCm,
        if (bodyFatPct != null) 'bodyFatPct': bodyFatPct,
      };
}

/// The logged row and the profile the server recomputed from it.
class LogMeasurementResultDto {
  const LogMeasurementResultDto(
      {required this.measurement, required this.profile});

  factory LogMeasurementResultDto.fromJson(Map<String, dynamic> json) =>
      LogMeasurementResultDto(
        measurement: BodyMeasurementDto.fromJson(readMap(json['measurement'])),
        profile: HealthProfileDto.fromJson(readMap(json['profile'])),
      );

  final BodyMeasurementDto measurement;
  final HealthProfileDto profile;

  Map<String, dynamic> toJson() => {
        'measurement': measurement.toJson(),
        'profile': profile.toJson(),
      };
}
