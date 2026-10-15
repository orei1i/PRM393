// lib/core/utils/bmi.dart

/// Which cut-offs to use. Vietnam commonly applies the WHO Western Pacific /
/// IDI classification for Asian adults (overweight ≥ 23, obese ≥ 25);
/// the global WHO adult classification uses 25 / 30.
enum BmiStandard { asiaPacific, who }

enum BmiCategory {
  underweight('Thiếu cân'),
  normal('Bình thường'),
  overweight('Thừa cân'),
  obese('Béo phì');

  const BmiCategory(this.label);
  final String label;
}

typedef BmiThresholds = ({
  double underweightBelow,
  double overweightFrom,
  double obeseFrom
});

abstract final class Bmi {
  /// Gauge range shown in the UI.
  static const double gaugeMin = 15;
  static const double gaugeMax = 35;

  static double calculate(
      {required double heightCm, required double weightKg}) {
    final meters = heightCm / 100;
    if (meters <= 0 || weightKg <= 0) return 0;
    return weightKg / (meters * meters);
  }

  static BmiThresholds thresholds(BmiStandard standard) => switch (standard) {
        BmiStandard.asiaPacific => (
            underweightBelow: 18.5,
            overweightFrom: 23.0,
            obeseFrom: 25.0
          ),
        BmiStandard.who => (
            underweightBelow: 18.5,
            overweightFrom: 25.0,
            obeseFrom: 30.0
          ),
      };

  static BmiCategory categorize(double bmi,
      {BmiStandard standard = BmiStandard.asiaPacific}) {
    final t = thresholds(standard);
    if (bmi < t.underweightBelow) return BmiCategory.underweight;
    if (bmi < t.overweightFrom) return BmiCategory.normal;
    if (bmi < t.obeseFrom) return BmiCategory.overweight;
    return BmiCategory.obese;
  }

  /// 0…1 position of [bmi] on the gauge.
  static double gaugePosition(double bmi) =>
      ((bmi.clamp(gaugeMin, gaugeMax) - gaugeMin) / (gaugeMax - gaugeMin))
          .toDouble();
}
