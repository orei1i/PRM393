// test/body_metrics/body_progress_test.dart
//
// WP-B (item 6): the rules behind "Theo dõi cân nặng" — BMI, WHtR, healthy
// weight range, chart series, verdicts, rate caution and the check-in due
// rule (spec §4.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/bmi.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/body_progress.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/body_measurement.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';

final _now = DateTime(2026, 10, 29, 9);

BodyMeasurement _m(
  int daysAgo,
  double kg, {
  int hour = 9,
  double? waist,
  double? fat,
  MeasurementSource source = MeasurementSource.checkIn,
}) {
  final day = _now.subtract(Duration(days: daysAgo));
  return BodyMeasurement(
    id: 'm_${daysAgo}_$hour',
    weightKg: kg,
    heightCm: 172,
    bmi: BodyProgress.bmiOf(heightCm: 172, weightKg: kg),
    waistCm: waist,
    bodyFatPct: fat,
    source: source,
    loggedAt: DateTime(day.year, day.month, day.day, hour),
  );
}

HealthProfile _minhAnh(double kg) => HealthProfile(
      heightCm: 172,
      weightKg: kg,
      bmi: BodyProgress.bmiOf(heightCm: 172, weightKg: kg),
      goal: HealthGoal.leanMuscle,
      gender: Gender.female,
      birthYear: DateTime.now().year - 29,
      activityLevel: ActivityLevel.light,
    );

void main() {
  group('BMI, WHtR, healthy range', () {
    test('172 cm, 65,4 kg → BMI 22,1 Bình thường (Asia-Pacific)', () {
      final bmi = BodyProgress.bmiOf(heightCm: 172, weightKg: 65.4);
      expect(bmi, 22.1);
      expect(Bmi.categorize(bmi).label, 'Bình thường');
      expect(BodyProgress.bmiOf(heightCm: 172, weightKg: 66), 22.3);
    });

    test('WHtR: 70 / 172 → 0,41; ≥ 0,5 needs caution', () {
      expect(BodyProgress.formatWhtr(70 / 172), '0,41');
      expect(BodyProgress.whtrNeedsCaution(70 / 172), isFalse);
      expect(BodyProgress.whtrNeedsCaution(86 / 172), isTrue);
      expect(BodyProgress.whtrNeedsCaution(85 / 172), isFalse); // 0,49
      expect(_m(0, 65, waist: 70).waistToHeight, closeTo(0.407, 0.001));
      expect(_m(0, 65).waistToHeight, isNull);
    });

    test('healthy weight for 172 cm: 54,7 – 68,0 kg; BMI band 18,5–22,9', () {
      final band = BodyProgress.healthyWeightRange(172);
      expect(band.min, 54.7);
      expect(band.max, 68.0);
      expect(BodyProgress.bmiBand.min, 18.5);
      expect(BodyProgress.bmiBand.max, 22.9);
    });

    test('signed and trimmed formats', () {
      expect(BodyProgress.formatSignedKg(65.4 - 66.0), '−0,6 kg');
      expect(BodyProgress.formatSignedKg(0.4), '+0,4 kg');
      expect(BodyProgress.formatSignedKg(0.01), '0,0 kg');
      expect(BodyProgress.formatKg(66), '66,0');
      expect(BodyProgress.formatTrim(70), '70');
      expect(BodyProgress.formatTrim(70.5), '70,5');
    });
  });

  group('chart series', () {
    final history = [
      _m(0, 65.4, hour: 20), // latest of today
      _m(0, 65.9, hour: 7),
      _m(5, 65.6),
      _m(8, 66.0),
      _m(28, 65.3),
      _m(40, 65.0),
    ];

    test('Tuần = the last 7 days, one point per day (latest), ascending', () {
      final points = BodyProgress.series(history,
          range: MetricsRange.week, of: MetricsSeries.weight, now: _now);
      expect([for (final p in points) p.value], [65.6, 65.4]);
      expect(points.first.day, DateTime(2026, 10, 24));
      expect(points.last.day, DateTime(2026, 10, 29));
    });

    test('Tháng = the last 30 days; Tất cả = everything', () {
      expect([
        for (final p in BodyProgress.series(history,
            range: MetricsRange.month, of: MetricsSeries.weight, now: _now))
          p.value
      ], [
        65.3,
        66.0,
        65.6,
        65.4
      ]);
      expect(
          BodyProgress.series(history,
                  range: MetricsRange.all, of: MetricsSeries.weight, now: _now)
              .length,
          5);
    });

    test('BMI series uses the measurement BMI', () {
      final points = BodyProgress.series(history,
          range: MetricsRange.week, of: MetricsSeries.bmi, now: _now);
      expect([for (final p in points) p.value], [22.2, 22.1]);
    });

    test('fewer than 2 points in a range (the screen shows a message)', () {
      expect(
          BodyProgress.series([_m(8, 66), _m(14, 65.8)],
              range: MetricsRange.week, of: MetricsSeries.weight, now: _now),
          isEmpty);
    });
  });

  group('verdict', () {
    String label(HealthGoal goal, double d) =>
        BodyProgress.verdict(goal, d).label;

    test('Giảm cân', () {
      expect(
          label(HealthGoal.loseWeight, -0.6), 'Đúng hướng mục tiêu Giảm cân');
      expect(
          label(HealthGoal.loseWeight, -0.2), 'Đúng hướng mục tiêu Giảm cân');
      expect(label(HealthGoal.loseWeight, 0.1), 'Chưa thay đổi');
      expect(label(HealthGoal.loseWeight, 0.2),
          'Chưa đúng hướng mục tiêu Giảm cân');
      expect(BodyProgress.verdict(HealthGoal.loseWeight, -0.6).tone,
          VerdictTone.good);
    });

    test('Tăng cân / Tăng cơ mirrored; Tăng cơ "Ổn định…"', () {
      expect(label(HealthGoal.gainWeight, 0.3), 'Đúng hướng mục tiêu Tăng cân');
      expect(label(HealthGoal.gainWeight, -0.1), 'Chưa thay đổi');
      expect(label(HealthGoal.gainWeight, -0.5),
          'Chưa đúng hướng mục tiêu Tăng cân');
      expect(label(HealthGoal.leanMuscle, -0.6),
          'Chưa đúng hướng mục tiêu Tăng cơ');
      expect(label(HealthGoal.leanMuscle, 0.1),
          'Ổn định — theo dõi thêm vòng eo và tỉ lệ mỡ');
      expect(label(HealthGoal.leanMuscle, 0.2), 'Đúng hướng mục tiêu Tăng cơ');
    });

    test('Giữ cân', () {
      expect(label(HealthGoal.maintain, 1.0), 'Giữ ổn định');
      expect(label(HealthGoal.maintain, -0.4), 'Giữ ổn định');
      expect(label(HealthGoal.maintain, -1.1),
          'Thay đổi nhiều hơn mục tiêu Giữ cân');
      expect(BodyProgress.verdict(HealthGoal.maintain, 1.4).tone,
          VerdictTone.caution);
    });
  });

  test('rate caution: more than 1 kg/week over at least 3 days', () {
    expect(BodyProgress.isFastLoss(-0.6, 8), isFalse); // −0,53/tuần
    expect(BodyProgress.isFastLoss(-2.0, 8), isTrue); // −1,75/tuần
    expect(BodyProgress.isFastLoss(-1.0, 2), isFalse); // too few days
    expect(BodyProgress.isFastLoss(2.0, 8), isFalse);
  });

  group('check-in due', () {
    CheckInPrompt? due({
      bool signedIn = true,
      bool hasProfile = true,
      bool hasPlan = true,
      CheckInCadence cadence = CheckInCadence.week,
      String? snoozedOn,
      int? lastDaysAgo = 8,
    }) =>
        BodyProgress.checkInPrompt(
          signedIn: signedIn,
          hasProfile: hasProfile,
          hasPlan: hasPlan,
          cadence: cadence,
          snoozedOn: snoozedOn,
          lastLoggedAt: lastDaysAgo == null
              ? null
              : _now.subtract(Duration(days: lastDaysAgo, hours: 3)),
          now: _now,
        );

    test('weekly: due from 7 days since the last weigh-in', () {
      final prompt = due()!;
      expect(prompt.daysSinceLast, 8);
      expect(
          prompt.message,
          'Đã 8 ngày từ lần cân trước. Cân lại để xem BMI và tiến độ sau một '
          'tuần theo Thực đơn.');
      expect(due(lastDaysAgo: 7), isNotNull);
      expect(due(lastDaysAgo: 6), isNull);
      expect(due(lastDaysAgo: 0), isNull);
    });

    test('monthly: due from 30 days', () {
      expect(due(cadence: CheckInCadence.month), isNull);
      final prompt = due(cadence: CheckInCadence.month, lastDaysAgo: 30)!;
      expect(prompt.message, contains('sau một tháng theo Thực đơn.'));
    });

    test('never weighed in → start tracking', () {
      final prompt = due(lastDaysAgo: null)!;
      expect(prompt.daysSinceLast, isNull);
      expect(
          prompt.message, 'Ghi cân nặng hôm nay để bắt đầu theo dõi tiến độ.');
    });

    test('"Để sau" hides it until the next day', () {
      expect(due(snoozedOn: '2026-10-29'), isNull);
      expect(due(snoozedOn: '2026-10-28'), isNotNull);
    });

    test('only for a signed-in member with a profile and a plan this week', () {
      expect(due(signedIn: false), isNull);
      expect(due(hasProfile: false), isNull);
      expect(due(hasPlan: false), isNull);
    });

    test('cadence prefs values', () {
      expect(CheckInCadence.fromPrefs('month'), CheckInCadence.month);
      expect(CheckInCadence.fromPrefs(null), CheckInCadence.week);
      expect(CheckInCadence.fromPrefs('x'), CheckInCadence.week);
    });
  });

  group('progress review', () {
    test('Minh Anh 66,0 → 65,4 kg after 8 days (spec §5.2)', () {
      final previous = _m(8, 66.0, waist: 70);
      final current = _m(0, 65.4, waist: 70, fat: 26.2);
      final review = ProgressReview.of(
        current: current,
        previous: previous,
        before: _minhAnh(66.0),
        after: _minhAnh(65.4),
      );
      expect(review.subtitle, 'So với lần cân 21/10 (8 ngày trước)');
      expect(review.weightRow, 'Cân nặng: 66,0 → 65,4 kg (−0,6 kg)');
      expect(review.bmiRow, 'BMI: 22,3 → 22,1 · Bình thường');
      expect(review.waistRow, 'Vòng eo: 70 → 70 cm · WHtR 0,41');
      expect(review.waistCaution, isFalse);
      expect(review.bodyFatRow, isNull,
          reason: 'the previous weigh-in has no body fat');
      final before = _minhAnh(66.0).dailyKcalTarget!;
      final after = _minhAnh(65.4).dailyKcalTarget!;
      if (before != after) {
        expect(review.energyRow,
            'Mục tiêu năng lượng: ≈ ${_kcal(before)} → ≈ ${_kcal(after)} kcal/ngày');
      } else {
        expect(review.energyRow, isNull);
      }
      expect(review.verdict!.label, 'Chưa đúng hướng mục tiêu Tăng cơ');
      expect(review.fastLoss, isFalse);
    });

    test('rows only when both weigh-ins have the field; fast loss', () {
      final review = ProgressReview.of(
        current: _m(0, 64.0, fat: 26.0, waist: 90),
        previous: _m(8, 66.0, fat: 27.0),
        after: _minhAnh(64.0),
      );
      expect(review.waistRow, isNull);
      expect(review.bodyFatRow, 'Tỉ lệ mỡ: 27 → 26 %');
      expect(review.energyRow, isNull, reason: 'no "before" profile');
      expect(review.fastLoss, isTrue);
      expect(BodyProgress.fastLossMessage,
          startsWith('Bạn đang giảm hơn 1 kg mỗi tuần.'));
    });

    test('first weigh-in ever', () {
      final review =
          ProgressReview.of(current: _m(0, 65.4), after: _minhAnh(65.4));
      expect(review.isFirst, isTrue);
      expect(review.subtitle,
          'Đã ghi lần cân đầu tiên. Cập nhật lại sau một tuần để xem tiến độ.');
      expect(review.weightRow, 'Cân nặng: 65,4 kg');
      expect(review.bmiRow, 'BMI: 22,1 · Bình thường');
      expect(review.verdict, isNull);
    });
  });

  group('validation (same as the profile editor)', () {
    test('weight', () {
      expect(BodyProgress.validateWeight(''), 'Nhập cân nặng.');
      expect(BodyProgress.validateWeight('29'), 'Cân nặng từ 30 đến 250 kg');
      expect(BodyProgress.validateWeight('251'), 'Cân nặng từ 30 đến 250 kg');
      expect(BodyProgress.validateWeight('65,45'),
          'Cân nặng chỉ lấy 1 chữ số thập phân');
      expect(BodyProgress.validateWeight('65,4'), isNull);
      expect(BodyProgress.validateWeight('65.4'), isNull);
    });

    test('waist and body fat are optional', () {
      expect(BodyProgress.validateWaist(''), isNull);
      expect(BodyProgress.validateWaist('39'), 'Vòng eo từ 40 đến 200 cm');
      expect(BodyProgress.validateWaist('70,5'), isNull);
      expect(BodyProgress.validateBodyFat(''), isNull);
      expect(BodyProgress.validateBodyFat('71'), 'Tỉ lệ mỡ từ 3 đến 70 %');
      expect(BodyProgress.validateBodyFat('2'), 'Tỉ lệ mỡ từ 3 đến 70 %');
      expect(BodyProgress.validateBodyFat('26,2'), isNull);
    });
  });
}

String _kcal(int kcal) {
  final s = kcal.toString();
  return s.length > 3
      ? '${s.substring(0, s.length - 3)}.${s.substring(s.length - 3)}'
      : s;
}
