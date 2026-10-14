// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/bmi.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/meal_planner_mock_data.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';

void main() {
  group('Bmi', () {
    test('calculates kg/m²', () {
      expect(Bmi.calculate(heightCm: 172, weightKg: 66), closeTo(22.31, 0.01));
    });

    test('uses Asia-Pacific cut-offs by default', () {
      expect(Bmi.categorize(22.3), BmiCategory.normal);
      expect(Bmi.categorize(23.5), BmiCategory.overweight);
      expect(Bmi.categorize(23.5, standard: BmiStandard.who), BmiCategory.normal);
      expect(Bmi.categorize(17), BmiCategory.underweight);
    });
  });

  group('formatters', () {
    test('Vietnamese thousands and decimals', () {
      expect(formatInt(1670), '1.670');
      expect(formatDecimal(22.31), '22,3');
    });

    test('week starts on Monday', () {
      final wednesday = DateTime(2026, 10, 14);
      expect(startOfWeek(wednesday), DateTime(2026, 10, 12));
      expect(weekdayShort(wednesday), 'T4');
    });
  });

  group('MealPlanDto', () {
    test('round-trips JSON and maps slots', () {
      final json = {
        'id': 'mp_test',
        'start_date': '2026-10-12',
        'goal': 'lean_muscle',
        'daily_targets': mockDailyTargets,
        'days': [
          {
            'date': '2026-10-12',
            'meals': {'breakfast': mockBreakfasts[0], 'lunch': mockLunches[5], 'dinner': mockDinners[0]},
          },
        ],
      };
      final dto = MealPlanDto.fromJson(json);
      final again = MealPlanDto.fromJson(dto.toJson());
      final plan = again.toEntity();

      expect(plan.days, hasLength(1));
      final day = plan.days.first;
      expect(day.meals.keys, containsAll(MealSlot.values));
      expect(day.totals.calories, 420 + 700 + 610);
      expect(day.conflictCount(['peanut']), 1);
    });
  });

  group('DetectedIngredientDto', () {
    test('low confidence items start unconfirmed', () {
      final dto = DetectedIngredientDto.fromJson({
        'id': 'd1',
        'label': 'Rau chân vịt',
        'confidence': 0.58,
        'freshness': 'fresh',
        'bbox': {'x': 0.5, 'y': 0.5, 'w': 0.2, 'h': 0.2},
      });
      expect(dto.toEntity().confirmed, isFalse);
    });
  });
}
