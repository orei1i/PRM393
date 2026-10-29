// lib/features/meal_planner/domain/entities/body_measurement.dart
import '../../../../core/utils/bmi.dart';

/// Where a weigh-in came from (`health_metric_logs.source`).
enum MeasurementSource {
  /// Written by a "Hồ sơ sức khoẻ" save that changed the weight.
  profile('profile'),

  /// "Cập nhật cân nặng" (check-in).
  checkIn('check_in');

  const MeasurementSource(this.apiValue);
  final String apiValue;

  /// Missing or unknown (older servers send no `source`) → [profile].
  static MeasurementSource fromApi(String? value) =>
      value == checkIn.apiValue ? checkIn : profile;
}

/// One weigh-in: weight with the height it was measured at, the BMI the
/// server computed, and the optional waist and body fat of a check-in.
class BodyMeasurement {
  const BodyMeasurement({
    required this.id,
    required this.weightKg,
    required this.heightCm,
    required this.bmi,
    required this.loggedAt,
    this.waistCm,
    this.bodyFatPct,
    this.source = MeasurementSource.checkIn,
  });

  final String id;
  final double weightKg;
  final double heightCm;

  /// One decimal, Asia-Pacific categories ([bmiCategory]).
  final double bmi;

  /// Local time.
  final DateTime loggedAt;
  final double? waistCm;
  final double? bodyFatPct;
  final MeasurementSource source;

  BmiCategory get bmiCategory => Bmi.categorize(bmi);

  /// Waist-to-height ratio (WHtR), unrounded; `null` without a waist.
  double? get waistToHeight =>
      waistCm == null || heightCm <= 0 ? null : waistCm! / heightCm;
}
