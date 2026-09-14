import '../entities/meal_entities.dart';

abstract interface class MealPlanRepository {
  WeeklyMealPlan generate({
    required DateTime weekStart,
    required int generation,
    required List<String> ingredients,
  });
}
