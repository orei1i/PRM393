// lib/features/meal_planner/domain/entities/meal_plan.dart
import '../../../../core/utils/formatters.dart';
import 'health_profile.dart';

enum MealSlot {
  breakfast('breakfast', 'Bữa sáng'),
  lunch('lunch', 'Bữa trưa'),
  dinner('dinner', 'Bữa tối');

  const MealSlot(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static MealSlot? fromApi(String value) {
    for (final slot in values) {
      if (slot.apiValue == value) return slot;
    }
    return null;
  }
}

class Nutrition {
  const Nutrition({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  static const zero =
      Nutrition(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0);

  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  Nutrition operator +(Nutrition other) => Nutrition(
        calories: calories + other.calories,
        proteinG: proteinG + other.proteinG,
        carbsG: carbsG + other.carbsG,
        fatG: fatG + other.fatG,
        fiberG: fiberG + other.fiberG,
      );
}

class SeasonalSwap {
  const SeasonalSwap({required this.ingredient, required this.recipeId});

  /// Vietnamese ingredient name, e.g. "Bí đỏ".
  final String ingredient;
  final String recipeId;
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.nutrition,
    this.imageUrl,
    this.allergens = const [],
    this.dietTags = const [],
    this.prepMinutes,
    this.seasonalSwap,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final Nutrition nutrition;
  final List<String> allergens;
  final List<String> dietTags;
  final int? prepMinutes;
  final SeasonalSwap? seasonalSwap;

  List<String> allergenConflicts(Iterable<String> userAllergies) {
    final mine = userAllergies.toSet();
    return allergens.where(mine.contains).toList();
  }
}

class MealPlanDay {
  const MealPlanDay({required this.date, required this.meals});

  final DateTime date;
  final Map<MealSlot, Recipe> meals;

  Nutrition get totals => meals.values
      .fold(Nutrition.zero, (sum, recipe) => sum + recipe.nutrition);

  MealPlanDay replaceMeal(MealSlot slot, Recipe recipe) =>
      MealPlanDay(date: date, meals: {...meals, slot: recipe});

  int conflictCount(Iterable<String> userAllergies) => meals.values
      .where((r) => r.allergenConflicts(userAllergies).isNotEmpty)
      .length;
}

class MealPlan {
  const MealPlan({
    required this.id,
    required this.startDate,
    required this.goal,
    required this.dailyTargets,
    required this.days,
  });

  final String id;
  final DateTime startDate;
  final HealthGoal goal;
  final Nutrition dailyTargets;
  final List<MealPlanDay> days;

  MealPlanDay? dayFor(DateTime date) {
    for (final day in days) {
      if (isSameDay(day.date, date)) return day;
    }
    return null;
  }

  MealPlan replaceDay(MealPlanDay updated) => MealPlan(
        id: id,
        startDate: startDate,
        goal: goal,
        dailyTargets: dailyTargets,
        days: [
          for (final d in days) isSameDay(d.date, updated.date) ? updated : d
        ],
      );
}
