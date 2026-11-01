// lib/features/meal_planner/domain/body_progress.dart
//
// "Theo dõi cân nặng": the rules behind the check-in, the progress review
// and the weight chart, free of Flutter so they are unit-tested on their own.
// BMI uses the Asia-Pacific cut-offs (`Bmi.categorize`); energy targets come
// from `HealthProfile.dailyKcalTarget` (core/utils/energy.dart, nearest
// 10 kcal). Estimates for meal planning only, not medical advice.
import '../../../core/utils/bmi.dart';
import '../../../core/utils/energy.dart';
import '../../../core/utils/formatters.dart';
import 'entities/body_measurement.dart';
import 'entities/health_profile.dart';

/// "Nhắc cập nhật cân nặng": how long after the last weigh-in the planner
/// asks for a new one. Kept per device and account.
enum CheckInCadence {
  week('week', 'Mỗi tuần', 7, 'một tuần'),
  month('month', 'Mỗi tháng', 30, 'một tháng');

  const CheckInCadence(this.prefsValue, this.label, this.days, this.period);

  /// Stored in SharedPreferences (`vl.checkin.cadence.<userId>`).
  final String prefsValue;
  final String label;
  final int days;

  /// "sau một tuần theo Thực đơn".
  final String period;

  /// Missing or unknown → [week].
  static CheckInCadence fromPrefs(String? value) =>
      value == month.prefsValue ? month : week;
}

/// Chart range: the last 7 / 30 days, or everything fetched (≤ 100 rows).
enum MetricsRange {
  week('Tuần', 7),
  month('Tháng', 30),
  all('Tất cả', null);

  const MetricsRange(this.label, this.days);
  final String label;

  /// Calendar days before today that are included; `null` = no limit.
  final int? days;
}

/// What the chart plots.
enum MetricsSeries {
  weight('Cân nặng', 'kg'),
  bmi('BMI', '');

  const MetricsSeries(this.label, this.unit);
  final String label;

  /// Unit after a value ("65,4 kg"); empty for BMI.
  final String unit;

  double of(BodyMeasurement m) => this == weight ? m.weightKg : m.bmi;
}

/// One chart point: the last weigh-in of a calendar [day].
class ChartPoint {
  const ChartPoint(this.day, this.value);

  final DateTime day;
  final double value;
}

/// The "Cập nhật cân nặng" card's reason to show.
class CheckInPrompt {
  const CheckInPrompt({required this.cadence, this.daysSinceLast});

  final CheckInCadence cadence;

  /// `null` → the member has never weighed in.
  final int? daysSinceLast;

  String get message => daysSinceLast == null
      ? 'Ghi cân nặng hôm nay để bắt đầu theo dõi tiến độ.'
      : 'Đã $daysSinceLast ngày từ lần cân trước. Cân lại để xem BMI và '
          'tiến độ sau ${cadence.period} theo Thực đơn.';
}

enum VerdictTone { good, neutral, caution }

/// Whether the weight moved the way the profile goal wants.
class ProgressVerdict {
  const ProgressVerdict(this.label, this.tone);

  final String label;
  final VerdictTone tone;
}

/// "Tiến độ của bạn": a new weigh-in against the previous one.
class ProgressReview {
  const ProgressReview({
    required this.current,
    required this.goal,
    this.previous,
    this.targetBefore,
    this.targetAfter,
  });

  /// [before] / [after]: the health profile before and after the weigh-in
  /// (their daily energy targets are compared).
  factory ProgressReview.of({
    required BodyMeasurement current,
    BodyMeasurement? previous,
    HealthProfile? before,
    required HealthProfile after,
  }) =>
      ProgressReview(
        current: current,
        previous: previous,
        goal: after.goal,
        targetBefore: before?.dailyKcalTarget,
        targetAfter: after.dailyKcalTarget,
      );

  final BodyMeasurement current;

  /// `null` for the first weigh-in ever.
  final BodyMeasurement? previous;
  final HealthGoal goal;
  final int? targetBefore;
  final int? targetAfter;

  bool get isFirst => previous == null;

  /// Calendar days since [previous].
  int? get days => previous == null
      ? null
      : BodyProgress.daysBetween(previous!.loggedAt, current.loggedAt);

  /// kg, one decimal.
  double? get deltaKg => previous == null
      ? null
      : BodyProgress.round1(current.weightKg - previous!.weightKg);

  String get subtitle {
    final p = previous;
    if (p == null) {
      return 'Đã ghi lần cân đầu tiên. Cập nhật lại sau một tuần để xem '
          'tiến độ.';
    }
    final d = days!;
    final ago = d == 0 ? 'hôm nay' : '$d ngày trước';
    return 'So với lần cân ${formatDayMonth(p.loggedAt)} ($ago)';
  }

  String get weightRow {
    final p = previous;
    final now = BodyProgress.formatKg(current.weightKg);
    if (p == null) return 'Cân nặng: $now kg';
    return 'Cân nặng: ${BodyProgress.formatKg(p.weightKg)} → $now kg '
        '(${BodyProgress.formatSignedKg(deltaKg!)})';
  }

  String get bmiRow {
    final p = previous;
    final now = '${formatDecimal(current.bmi)} · ${current.bmiCategory.label}';
    if (p == null) return 'BMI: $now';
    return 'BMI: ${formatDecimal(p.bmi)} → $now';
  }

  /// Only when the daily target changed.
  String? get energyRow {
    final a = targetBefore;
    final b = targetAfter;
    if (a == null || b == null || a == b) return null;
    return 'Mục tiêu năng lượng: ≈ ${Energy.formatKcal(a)} → '
        '≈ ${Energy.formatKcal(b)} kcal/ngày';
  }

  ProgressVerdict? get verdict => switch (deltaKg) {
        final d? => BodyProgress.verdict(goal, d),
        null => null,
      };

  /// Losing more than 1 kg a week (over at least 3 days).
  bool get fastLoss => switch ((deltaKg, days)) {
        (final d?, final n?) => BodyProgress.isFastLoss(d, n),
        _ => false,
      };
}

abstract final class BodyProgress {
  static const minWeightKg = 30.0;
  static const maxWeightKg = 250.0;

  /// The "Bình thường" BMI band (Asia-Pacific) drawn on the BMI chart.
  static const bmiBand = (min: 18.5, max: 22.9);

  static const fastLossMessage = 'Bạn đang giảm hơn 1 kg mỗi tuần. Giảm quá '
      'nhanh có thể không tốt — cân nhắc hỏi chuyên gia dinh dưỡng.';

  static const disclaimer =
      'Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế.';

  static double round1(double v) => (v * 10).roundToDouble() / 10;

  /// BMI as the server caches it (one decimal); 172 cm, 65,4 kg → 22,1.
  static double bmiOf({required double heightCm, required double weightKg}) =>
      round1(Bmi.calculate(heightCm: heightCm, weightKg: weightKg));

  /// Weights with a "Bình thường" BMI at [heightCm]: 18,5·h² – 23·h², one
  /// decimal (172 cm → 54,7 – 68,0 kg).
  static ({double min, double max}) healthyWeightRange(double heightCm) {
    final m = heightCm / 100;
    return (min: round1(18.5 * m * m), max: round1(23 * m * m));
  }

  /// Calendar days from [from] to [to] (local dates, DST-safe).
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  /// Points for the chart: one per calendar day (the day's last weigh-in)
  /// within [range] of [now], oldest first.
  static List<ChartPoint> series(
    Iterable<BodyMeasurement> measurements, {
    required MetricsRange range,
    required MetricsSeries of,
    required DateTime now,
  }) {
    final byDay = <DateTime, BodyMeasurement>{};
    for (final m in measurements) {
      final day = dateOnly(m.loggedAt);
      if (range.days case final n? when daysBetween(day, now) > n) continue;
      final kept = byDay[day];
      if (kept == null || m.loggedAt.isAfter(kept.loggedAt)) byDay[day] = m;
    }
    final days = byDay.keys.toList()..sort();
    return [for (final d in days) ChartPoint(d, of.of(byDay[d]!))];
  }

  /// The BMI chart of "Cập nhật cân nặng": every weigh-in, then what is being
  /// typed ([typedWeightKg], `null` while invalid) as today's point at
  /// [heightCm], replacing a weigh-in already logged today.
  static List<ChartPoint> bmiPreviewSeries(
    Iterable<BodyMeasurement> measurements, {
    required double heightCm,
    required DateTime now,
    double? typedWeightKg,
  }) {
    final points = series(measurements,
        range: MetricsRange.all, of: MetricsSeries.bmi, now: now);
    if (typedWeightKg == null) return points;
    final today = dateOnly(now);
    return [
      for (final p in points)
        if (p.day != today) p,
      ChartPoint(today, bmiOf(heightCm: heightCm, weightKg: typedWeightKg)),
    ];
  }

  /// When the planner asks for a weigh-in: a member with a health profile
  /// and a plan this week, not snoozed today ([snoozedOn] = `yyyy-MM-dd`),
  /// who never weighed in or did [cadence] days ago or more.
  static CheckInPrompt? checkInPrompt({
    required bool signedIn,
    required bool hasProfile,
    required bool hasPlan,
    required CheckInCadence cadence,
    required DateTime now,
    String? snoozedOn,
    DateTime? lastLoggedAt,
  }) {
    if (!signedIn || !hasProfile || !hasPlan) return null;
    if (snoozedOn != null && snoozedOn.compareTo(toApiDate(now)) >= 0) {
      return null;
    }
    if (lastLoggedAt == null) return CheckInPrompt(cadence: cadence);
    final days = daysBetween(lastLoggedAt, now);
    if (days < cadence.days) return null;
    return CheckInPrompt(cadence: cadence, daysSinceLast: days);
  }

  /// [deltaKg] (new − previous) against the profile goal.
  static ProgressVerdict verdict(HealthGoal goal, double deltaKg) {
    final d = round1(deltaKg);
    final target = 'mục tiêu ${goal.label}';
    switch (goal) {
      case HealthGoal.maintain:
        return d.abs() <= 1.0
            ? const ProgressVerdict('Giữ ổn định', VerdictTone.good)
            : ProgressVerdict(
                'Thay đổi nhiều hơn $target', VerdictTone.caution);
      case HealthGoal.loseWeight:
        if (d <= -0.2) {
          return ProgressVerdict('Đúng hướng $target', VerdictTone.good);
        }
        if (d >= 0.2) {
          return ProgressVerdict(
              'Chưa đúng hướng $target', VerdictTone.caution);
        }
        return const ProgressVerdict('Chưa thay đổi', VerdictTone.neutral);
      case HealthGoal.gainWeight || HealthGoal.leanMuscle:
        if (d >= 0.2) {
          return ProgressVerdict('Đúng hướng $target', VerdictTone.good);
        }
        if (d <= -0.2) {
          return ProgressVerdict(
              'Chưa đúng hướng $target', VerdictTone.caution);
        }
        return goal == HealthGoal.leanMuscle
            ? const ProgressVerdict(
                'Ổn định — tiếp tục theo dõi', VerdictTone.neutral)
            : const ProgressVerdict('Chưa thay đổi', VerdictTone.neutral);
    }
  }

  /// Over at least 3 days, losing faster than 1 kg a week.
  static bool isFastLoss(double deltaKg, int days) =>
      days >= 3 && deltaKg / days * 7 < -1.0;

  // ------------------------------------------------------------- formatting

  /// 65.4 → "65,4" (always one decimal).
  static String formatKg(double kg) => formatDecimal(kg);

  /// −0.6 → "−0,6 kg", 0.4 → "+0,4 kg", 0 → "0,0 kg".
  static String formatSignedKg(double delta) {
    final d = round1(delta);
    if (d == 0) return '0,0 kg';
    return '${d > 0 ? '+' : '−'}${formatDecimal(d.abs())} kg';
  }

  /// 70 → "70", 70.5 → "70,5".
  static String formatTrim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : formatDecimal(v);

  // ------------------------------------------------------------- validation

  static double? parse(String? text) =>
      double.tryParse((text ?? '').trim().replaceAll(',', '.'));

  /// The rule of the check-in sheet for a weight that is already a number; its
  /// message, or `null`.
  static String? validateMeasurement(double weightKg) =>
      validateWeight('$weightKg');

  /// Same rules as the "Hồ sơ sức khoẻ" editor.
  static String? validateWeight(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Nhập cân nặng.';
    final kg = parse(text);
    if (kg == null) return 'Cân nặng chưa hợp lệ.';
    final parts = text.replaceAll(',', '.').split('.');
    if (parts.length > 1 && parts[1].length > 1) {
      return 'Cân nặng chỉ lấy 1 chữ số thập phân';
    }
    if (kg < minWeightKg || kg > maxWeightKg) {
      return 'Cân nặng từ 30 đến 250 kg';
    }
    return null;
  }
}
