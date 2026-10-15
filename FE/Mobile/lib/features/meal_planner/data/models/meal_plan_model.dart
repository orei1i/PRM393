// lib/features/meal_planner/data/models/meal_plan_model.dart
//
// Wire format (camelCase, ASP.NET default) for the meal planner. DTOs are dumb data + JSON;
// `toEntity()` maps them into the domain layer used by the UI.
//
// GET /meal-plans/current
// {
//   "id": "mp_2026_w42",
//   "startDate": "2026-10-12",
//   "goal": "lean_muscle",
//   "dailyTargets": { "calories": 1850, "proteinG": 90, "carbsG": 240, "fatG": 60, "fiberG": 32 },
//   "days": [
//     { "date": "2026-10-12",
//       "meals": {
//         "breakfast": { "id": "b1", "name": "…", "calories": 420, "proteinG": 18, "carbsG": 62,
//                        "fatG": 12, "fiberG": 11, "allergens": [], "dietTags": ["whole_food"],
//                        "prepMinutes": 5, "imageUrl": null,
//                        "seasonalSwap": { "ingredient": "Bí đỏ", "recipeId": "ls_pumpkin" } },
//         "lunch": { … }, "dinner": { … } } }
//   ]
// }

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/health_profile.dart';
import '../../domain/entities/meal_plan.dart';

class NutritionDto {
  const NutritionDto({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  factory NutritionDto.fromJson(Map<String, dynamic> json) => NutritionDto(
        calories: readInt(json['calories']),
        proteinG: readDouble(json['proteinG']),
        carbsG: readDouble(json['carbsG']),
        fatG: readDouble(json['fatG']),
        fiberG: readDouble(json['fiberG']),
      );

  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'fiberG': fiberG,
      };

  Nutrition toEntity() => Nutrition(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
      );
}

class SeasonalSwapDto {
  const SeasonalSwapDto({required this.ingredient, required this.recipeId});

  factory SeasonalSwapDto.fromJson(Map<String, dynamic> json) =>
      SeasonalSwapDto(
        ingredient: json['ingredient'] as String? ?? '',
        recipeId: json['recipeId'] as String? ?? '',
      );

  final String ingredient;
  final String recipeId;

  Map<String, dynamic> toJson() =>
      {'ingredient': ingredient, 'recipeId': recipeId};

  SeasonalSwap toEntity() =>
      SeasonalSwap(ingredient: ingredient, recipeId: recipeId);
}

/// A recipe as placed in a meal slot. Nutrition is flattened on the wire.
class RecipeDto {
  const RecipeDto({
    required this.id,
    required this.name,
    required this.nutrition,
    this.imageUrl,
    this.allergens = const [],
    this.dietTags = const [],
    this.prepMinutes,
    this.seasonalSwap,
  });

  factory RecipeDto.fromJson(Map<String, dynamic> json) => RecipeDto(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        nutrition: NutritionDto.fromJson(json),
        allergens: readStringList(json['allergens']),
        dietTags: readStringList(json['dietTags']),
        prepMinutes:
            json['prepMinutes'] == null ? null : readInt(json['prepMinutes']),
        seasonalSwap: json['seasonalSwap'] is Map<String, dynamic>
            ? SeasonalSwapDto.fromJson(
                json['seasonalSwap'] as Map<String, dynamic>)
            : null,
      );

  final String id;
  final String name;
  final String? imageUrl;
  final NutritionDto nutrition;
  final List<String> allergens;
  final List<String> dietTags;
  final int? prepMinutes;
  final SeasonalSwapDto? seasonalSwap;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        ...nutrition.toJson(),
        'allergens': allergens,
        'dietTags': dietTags,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        if (seasonalSwap != null) 'seasonalSwap': seasonalSwap!.toJson(),
      };

  Recipe toEntity() => Recipe(
        id: id,
        name: name,
        imageUrl: imageUrl,
        nutrition: nutrition.toEntity(),
        allergens: allergens,
        dietTags: dietTags,
        prepMinutes: prepMinutes,
        seasonalSwap: seasonalSwap?.toEntity(),
      );
}

class MealPlanDayDto {
  const MealPlanDayDto({required this.date, required this.meals});

  factory MealPlanDayDto.fromJson(Map<String, dynamic> json) {
    final mealsJson = readMap(json['meals']);
    return MealPlanDayDto(
      date: readDate(json['date']),
      meals: {
        for (final entry in mealsJson.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: RecipeDto.fromJson(entry.value as Map<String, dynamic>),
      },
    );
  }

  final DateTime date;

  /// Keyed by slot api value: `breakfast` | `lunch` | `dinner`.
  final Map<String, RecipeDto> meals;

  Map<String, dynamic> toJson() => {
        'date': toApiDate(date),
        'meals': {for (final e in meals.entries) e.key: e.value.toJson()},
      };

  MealPlanDay toEntity() {
    final mapped = <MealSlot, Recipe>{};
    for (final entry in meals.entries) {
      final slot = MealSlot.fromApi(entry.key);
      if (slot != null) mapped[slot] = entry.value.toEntity();
    }
    return MealPlanDay(date: date, meals: mapped);
  }
}

class MealPlanDto {
  const MealPlanDto({
    required this.id,
    required this.startDate,
    required this.goal,
    required this.dailyTargets,
    required this.days,
  });

  factory MealPlanDto.fromJson(Map<String, dynamic> json) => MealPlanDto(
        id: json['id'] as String,
        startDate: readDate(json['startDate']),
        goal: json['goal'] as String? ?? HealthGoal.maintain.apiValue,
        dailyTargets: NutritionDto.fromJson(readMap(json['dailyTargets'])),
        days: (json['days'] is List<Object?>)
            ? (json['days'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(MealPlanDayDto.fromJson)
                .toList()
            : const [],
      );

  final String id;
  final DateTime startDate;
  final String goal;
  final NutritionDto dailyTargets;
  final List<MealPlanDayDto> days;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startDate': toApiDate(startDate),
        'goal': goal,
        'dailyTargets': dailyTargets.toJson(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  MealPlanDto copyWithDay(MealPlanDayDto day) => MealPlanDto(
        id: id,
        startDate: startDate,
        goal: goal,
        dailyTargets: dailyTargets,
        days: [for (final d in days) isSameDay(d.date, day.date) ? day : d],
      );

  MealPlan toEntity() {
    final mapped = days.map((d) => d.toEntity()).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return MealPlan(
      id: id,
      startDate: startDate,
      goal: HealthGoal.fromApi(goal),
      dailyTargets: dailyTargets.toEntity(),
      days: mapped,
    );
  }
}

/// PATCH /meal-plans/{id}/meals
class SwapMealRequestDto {
  const SwapMealRequestDto(
      {required this.date, required this.slot, required this.recipeId});

  final DateTime date;
  final MealSlot slot;
  final String recipeId;

  Map<String, dynamic> toJson() => {
        'date': toApiDate(date),
        'slot': slot.apiValue,
        'recipeId': recipeId,
      };
}
