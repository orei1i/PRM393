// lib/features/meal_planner/data/mock_meal_planner_repository.dart
import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/mock_delay.dart';
import '../domain/entities/meal_plan.dart';
import 'meal_planner_api_service.dart';
import 'mock/meal_planner_mock_data.dart';
import 'models/health_profile_model.dart';
import 'models/meal_plan_model.dart';

/// In-memory backend with realistic latency. Behaves like the real API:
/// swaps persist for the session, suggestions respect allergies and ±10 % kcal.
class MockMealPlannerRepository implements MealPlannerApiService {
  MockMealPlannerRepository();

  MealPlanDto? _plan;
  HealthProfileDto? _profile;

  HealthProfileDto get _healthProfile => _profile ??= HealthProfileDto.fromJson(
        mockHealthProfileJson(
          syncProvider: defaultTargetPlatform == TargetPlatform.iOS
              ? 'apple_health'
              : 'health_connect',
        ),
      );

  @override
  Future<HealthProfileDto> getHealthProfile() async {
    await mockDelay(500);
    return _healthProfile;
  }

  @override
  Future<MealPlanDto?> getCurrentMealPlan() async {
    await mockDelay(800);
    return _plan ??= _buildWeek(startOfWeek(DateTime.now()));
  }

  @override
  Future<MealPlanDto> generateMealPlan({required DateTime startDate}) async {
    await mockDelay(2200); // generation is slow on the real server too
    return _plan = _buildWeek(startDate);
  }

  @override
  Future<List<RecipeDto>> getSwapSuggestions({
    required String planId,
    required DateTime date,
    required MealSlot slot,
  }) async {
    await mockDelay(1100);
    final plan = _requirePlan(planId);
    final day = plan.days.firstWhere((d) => isSameDay(d.date, date));
    final current = day.meals[slot.apiValue];
    final allergies = _healthProfile.allergies.toSet();
    final targetKcal = current?.nutrition.calories ?? 550;

    final pool = [
      ...?mockSwapPool[slot.apiValue],
      ..._slotRecipes(slot),
    ].map(RecipeDto.fromJson);

    final suggestions = pool
        .where((r) => r.id != current?.id)
        .where((r) => !r.allergens.any(allergies.contains))
        .where((r) =>
            (r.nutrition.calories - targetKcal).abs() <= targetKcal * 0.1)
        .toList()
      ..sort((a, b) => (a.nutrition.calories - targetKcal)
          .abs()
          .compareTo((b.nutrition.calories - targetKcal).abs()));
    return suggestions.take(3).toList();
  }

  @override
  Future<MealPlanDayDto> swapMeal({
    required String planId,
    required SwapMealRequestDto request,
  }) async {
    await mockDelay(600);
    final plan = _requirePlan(planId);
    final recipe = _findRecipe(request.recipeId);
    if (recipe == null) {
      throw const ApiException(
          message: 'Món ăn không còn khả dụng.', statusCode: 404);
    }
    final day = plan.days.firstWhere((d) => isSameDay(d.date, request.date));
    final updated = MealPlanDayDto(
      date: day.date,
      meals: {...day.meals, request.slot.apiValue: recipe},
    );
    _plan = plan.copyWithDay(updated);
    return updated;
  }

  // ---------------------------------------------------------------------------

  MealPlanDto _requirePlan(String planId) {
    final plan = _plan;
    if (plan == null || plan.id != planId) {
      throw const ApiException(
          message: 'Không tìm thấy thực đơn.', statusCode: 404);
    }
    return plan;
  }

  List<Map<String, Object?>> _slotRecipes(MealSlot slot) => switch (slot) {
        MealSlot.breakfast => mockBreakfasts,
        MealSlot.lunch => mockLunches,
        MealSlot.dinner => mockDinners,
      };

  RecipeDto? _findRecipe(String id) {
    final all = [
      ...mockBreakfasts,
      ...mockLunches,
      ...mockDinners,
      for (final list in mockSwapPool.values) ...list,
    ];
    for (final json in all) {
      if (json['id'] == id) return RecipeDto.fromJson(json);
    }
    return null;
  }

  MealPlanDto _buildWeek(DateTime monday) {
    final days = List.generate(7, (i) {
      final date = monday.add(Duration(days: i));
      return {
        'date': toApiDate(date),
        'meals': {
          'breakfast': mockBreakfasts[i],
          'lunch': mockLunches[i],
          'dinner': mockDinners[i],
        },
      };
    });
    return MealPlanDto.fromJson({
      'id': 'mp_${toApiDate(monday)}',
      'startDate': toApiDate(monday),
      'goal': 'lean_muscle',
      'dailyTargets': mockDailyTargets,
      'days': days,
    });
  }
}
