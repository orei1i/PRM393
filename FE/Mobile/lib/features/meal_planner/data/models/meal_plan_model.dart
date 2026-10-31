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
//         "lunch": { … }, "snack_pm": { …, "portion": 1.5 }, "dinner": { … } } }
//   ]
// }
//
// Slots: breakfast | snack_am | lunch | snack_pm | dinner | snack_late
// (meal_plan_recipes.meal_type). A slot may be missing (a plan the member
// builds by hand starts empty; the member's pattern decides which show).
// Each meal may carry "source": "ai" | "manual" | "user_recipe" | "chef" |
// "fridge_scan" | "recipe" (added from a catalogue recipe's page)
// (meal_plan_recipes.source), "sourceName" (the chef) and "portion"
// (servings in the slot, default 1; kcal/macros are already for that
// portion).
//
// A real BE slot item also has "recipeId" ("id" is then the slot's own 32-hex
// uuid, not a recipe) and "allergyConflicts". PATCH always stores
// "source": "manual", even for a recipe, so that reads as "recipe" here.
//
// POST /meal-plans/current/meals   → 200 MealPlanDayDto (the updated day)
// { "date": "2026-10-15", "slot": "lunch", "source": "fridge_scan", "sourceId": "menu_1",
//   "name": "Đậu hũ xào bông cải cà rốt", "calories": 420, "prepMinutes": 20,
//   "ingredients": ["Đậu hũ", "Bông cải xanh", "Cà rốt", "Tỏi", "Nước tương"],
//   "allergens": ["soy"] }
//
// POST /meal-plans/current/meals/batch   (many dishes in one request, e.g. a
// delivered chef plan: "Áp dụng kế hoạch vào Thực đơn")
// { "meals": [ { same body as /meal-plans/current/meals }, … ] }
// → 200 { "placed": 26, "skipped": 2, "days": [ MealPlanDayDto, … ] }
// Each dish replaces its slot; dishes dated outside the current week are
// skipped (counted in "skipped"), not errors; "days" holds only the days that
// changed. Any other failure applies nothing.

import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/health_profile.dart';
import '../../domain/entities/meal_plan.dart';
import '../../domain/entities/plan_adjustment.dart';

/// kcal + macros. A macro missing (or `null`) on the wire stays `null`: a
/// dish typed in, written by the member or suggested by a chef without
/// macros has none, and the app never shows them as 0 g.
class NutritionDto {
  const NutritionDto({
    required this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
  });

  factory NutritionDto.fromJson(Map<String, dynamic> json) {
    double? grams(String key) =>
        json[key] == null ? null : readDouble(json[key]);
    return NutritionDto(
      calories: readInt(json['calories']),
      proteinG: grams('proteinG'),
      carbsG: grams('carbsG'),
      fatG: grams('fatG'),
      fiberG: grams('fiberG'),
    );
  }

  final int calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;

  Map<String, dynamic> toJson() => {
        'calories': calories,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (fiberG != null) 'fiberG': fiberG,
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
/// `source` / `sourceName` describe the slot (`meal_plan_recipes.source`);
/// `createdBy` is set on member-written recipes. All three are optional.
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
    this.source,
    this.sourceName,
    this.createdBy,
    this.portion = 1,
    this.allergyConflicts = const [],
  });

  factory RecipeDto.fromJson(Map<String, dynamic> json) => RecipeDto(
        id: effectiveMealId(json),
        name: json['name'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        nutrition: NutritionDto.fromJson({
          ...json,
          // Catalogue rows carry the recipes.calories_cache column name.
          if (json['calories'] == null) 'calories': json['caloriesCache'],
        }),
        allergens: readStringList(json['allergens']),
        dietTags: readStringList(json['dietTags']),
        prepMinutes:
            json['prepMinutes'] == null ? null : readInt(json['prepMinutes']),
        seasonalSwap: json['seasonalSwap'] is Map<String, dynamic>
            ? SeasonalSwapDto.fromJson(
                json['seasonalSwap'] as Map<String, dynamic>)
            : null,
        source: _hasRecipeId(json) && json['source'] == 'manual'
            ? MealSource.recipe.apiValue
            : json['source'] as String?,
        sourceName: json['sourceName'] as String?,
        createdBy: json['createdBy']?.toString(),
        portion: json['portion'] == null || readDouble(json['portion']) <= 0
            ? 1
            : readDouble(json['portion']),
        allergyConflicts: readStringList(json['allergyConflicts']),
      );

  static bool _hasRecipeId(Map<String, dynamic> json) =>
      json['recipeId']?.toString().isNotEmpty ?? false;

  /// The id that opens the dish: its `recipeId` when it has one, else `id`.
  static String effectiveMealId(Map<String, dynamic> json) => _hasRecipeId(json)
      ? json['recipeId'].toString()
      : json['id']?.toString() ?? '';

  final String id;
  final String name;
  final String? imageUrl;
  final NutritionDto nutrition;
  final List<String> allergens;
  final List<String> dietTags;
  final int? prepMinutes;
  final SeasonalSwapDto? seasonalSwap;

  /// `ai` | `manual` | `user_recipe` | `chef` | `fridge_scan` | `recipe`.
  final String? source;
  final String? sourceName;
  final String? createdBy;

  /// Servings in the slot; nutrition is for this portion.
  final double portion;

  /// The member's allergies the server found in this dish.
  final List<String> allergyConflicts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        ...nutrition.toJson(),
        'allergens': allergens,
        'dietTags': dietTags,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        if (seasonalSwap != null) 'seasonalSwap': seasonalSwap!.toJson(),
        if (source != null) 'source': source,
        if (sourceName != null) 'sourceName': sourceName,
        if (createdBy != null) 'createdBy': createdBy,
        if (portion != 1) 'portion': portion,
        if (allergyConflicts.isNotEmpty) 'allergyConflicts': allergyConflicts,
      };

  RecipeDto withSource(String source, {String? sourceName}) => RecipeDto(
        id: id,
        name: name,
        nutrition: nutrition,
        imageUrl: imageUrl,
        allergens: allergens,
        dietTags: dietTags,
        prepMinutes: prepMinutes,
        seasonalSwap: seasonalSwap,
        source: source,
        sourceName: sourceName ?? this.sourceName,
        createdBy: createdBy,
        portion: portion,
        allergyConflicts: allergyConflicts,
      );

  /// [portion] servings of this dish (kcal and the macros it has scaled;
  /// unknown macros stay unknown).
  RecipeDto scaled(double portion) {
    if (portion == this.portion) return this;
    final f = portion / this.portion;
    double? g(double? v) => v == null ? null : (v * f).roundToDouble();
    return RecipeDto(
      id: id,
      name: name,
      nutrition: NutritionDto(
        calories: (nutrition.calories * f).round(),
        proteinG: g(nutrition.proteinG),
        carbsG: g(nutrition.carbsG),
        fatG: g(nutrition.fatG),
        fiberG: g(nutrition.fiberG),
      ),
      imageUrl: imageUrl,
      allergens: allergens,
      dietTags: dietTags,
      prepMinutes: prepMinutes,
      seasonalSwap: seasonalSwap,
      source: source,
      sourceName: sourceName,
      createdBy: createdBy,
      portion: portion,
      allergyConflicts: allergyConflicts,
    );
  }

  Recipe toEntity() => Recipe(
        id: id,
        name: name,
        imageUrl: imageUrl,
        nutrition: nutrition.toEntity(),
        allergens: allergens,
        dietTags: dietTags,
        prepMinutes: prepMinutes,
        seasonalSwap: seasonalSwap?.toEntity(),
        source: MealSource.fromApi(source),
        sourceName: sourceName,
        createdBy: createdBy,
        portion: portion,
        serverConflicts: allergyConflicts,
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

  /// Keyed by slot api value (`breakfast`, `snack_pm`, …).
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

  /// The same week aimed at a new goal and daily targets (the server
  /// recomputes them when the health profile changes).
  MealPlanDto withTargets(
          {required String goal, required NutritionDto dailyTargets}) =>
      MealPlanDto(
        id: id,
        startDate: startDate,
        goal: goal,
        dailyTargets: dailyTargets,
        days: days,
      );

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

/// PATCH /meal-plans/{id}/meals — puts a recipe by id (AI suggestion,
/// the member's own recipe, a chef suggestion) into a slot.
class SwapMealRequestDto {
  const SwapMealRequestDto({
    required this.date,
    required this.slot,
    required this.recipeId,
    this.source,
    this.portion = 1,
  });

  final DateTime date;
  final MealSlot slot;
  final String recipeId;

  /// Omitted for plain AI swaps (the server's default).
  final MealSource? source;

  /// Servings to place (an AI suggestion sized for the slot); default 1.
  final double portion;

  Map<String, dynamic> toJson() => {
        'date': toApiDate(date),
        'slot': slot.apiValue,
        'recipeId': recipeId,
        if (source != null) 'source': source!.apiValue,
        if (portion != 1) 'portion': portion,
      };
}

/// POST /meal-plans/current/meals: puts a dish that is not in the recipe
/// catalogue (a fridge-scan suggestion, or a dish the member typed in) into
/// [slot] of [date], replacing that slot's meal. The server resolves
/// nutrition and allergens from the name and [ingredients]; [allergens] is
/// what the client already knows. [calories] and macros are optional for
/// typed-in dishes.
class AddMealRequestDto {
  const AddMealRequestDto({
    required this.date,
    required this.slot,
    required this.name,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.prepMinutes,
    this.ingredients = const [],
    this.allergens = const [],
    this.source = 'fridge_scan',
    this.sourceId,
    this.sourceName,
    this.instructions,
  });

  final DateTime date;

  /// Any of the 6 meals; a slot outside the member's pattern becomes an
  /// extra meal of that day.
  final MealSlot slot;
  final String name;
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final int? prepMinutes;
  final List<String> ingredients;
  final List<String> allergens;

  /// `fridge_scan` | `manual` | `chef` (a delivered chef plan: [sourceId]
  /// is the chef's recipe id when there is one, [sourceName] the chef).
  final String source;
  final String? sourceId;
  final String? sourceName;

  /// A chef's steps, for the dish's page. Not sent: the BE keeps no steps on a
  /// placed dish, so the mock is the only one that reads this.
  final String? instructions;

  Map<String, dynamic> toJson() => {
        'date': toApiDate(date),
        'slot': slot.apiValue,
        'source': source,
        if (sourceId != null) 'sourceId': sourceId,
        if (sourceName != null) 'sourceName': sourceName,
        'name': name,
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        'ingredients': ingredients,
        'allergens': allergens,
      };
}

/// Result of POST /meal-plans/current/meals/batch: how many dishes were
/// placed, how many fell outside the current week, and the changed days.
class AddMealsResultDto {
  const AddMealsResultDto({
    required this.placed,
    required this.skipped,
    required this.days,
  });

  factory AddMealsResultDto.fromJson(Map<String, dynamic> json) =>
      AddMealsResultDto(
        placed: readInt(json['placed']),
        skipped: readInt(json['skipped']),
        days: (json['days'] is List<Object?>)
            ? (json['days'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(MealPlanDayDto.fromJson)
                .toList()
            : const [],
      );

  final int placed;
  final int skipped;
  final List<MealPlanDayDto> days;

  Map<String, dynamic> toJson() => {
        'placed': placed,
        'skipped': skipped,
        'days': days.map((d) => d.toJson()).toList(),
      };
}

/// GET /meal-plans/chef-suggestions
/// `[{ "id", "chefId", "chefName", "note", "slot", "targetDate": "2026-10-17" | null,
///     "createdAt", "recipe": RecipeDto }]`
class ChefSuggestionDto {
  const ChefSuggestionDto({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.recipe,
    this.note,
    this.slot,
    this.targetDate,
    this.createdAt,
  });

  factory ChefSuggestionDto.fromJson(Map<String, dynamic> json) =>
      ChefSuggestionDto(
        id: json['id']?.toString() ?? '',
        chefId: json['chefId']?.toString() ?? '',
        chefName: json['chefName'] as String? ?? 'Chuyên gia',
        recipe: RecipeDto.fromJson(readMap(json['recipe'])),
        note: json['note'] as String?,
        slot: json['slot'] as String?,
        targetDate: json['targetDate'] is String &&
                DateTime.tryParse(json['targetDate'] as String) != null
            ? readDate(json['targetDate'])
            : null,
        createdAt: readDateTime(json['createdAt']),
      );

  final String id;
  final String chefId;
  final String chefName;
  final RecipeDto recipe;
  final String? note;
  final String? slot;

  /// Day the chef had in mind (`chef_meal_suggestions.target_date`), date only.
  final DateTime? targetDate;
  final DateTime? createdAt;

  ChefSuggestion toEntity() => ChefSuggestion(
        id: id,
        chefId: chefId,
        chefName: chefName,
        recipe: recipe
            .withSource(MealSource.chef.apiValue, sourceName: chefName)
            .toEntity(),
        note: note,
        slot: slot == null ? null : MealSlot.fromApi(slot!),
        targetDate: targetDate,
        createdAt: createdAt,
      );
}

/// One row of a member-written recipe (`recipe_ingredients`).
class RecipeIngredientInput {
  const RecipeIngredientInput(
      {required this.name, required this.quantity, required this.unit});

  final String name;
  final double quantity;
  final String unit;

  Map<String, dynamic> toJson() =>
      {'name': name, 'quantity': quantity, 'unit': unit};
}

/// POST /recipes — "Công thức của tôi". Saved to `recipes` with
/// `created_by` = the member; steps are newline-separated `instructions`.
class CreateRecipeRequestDto {
  const CreateRecipeRequestDto({
    required this.name,
    required this.calories,
    required this.ingredients,
    required this.steps,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.prepMinutes,
    this.servings,
  });

  final String name;
  final int calories;
  final List<RecipeIngredientInput> ingredients;
  final List<String> steps;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final int? prepMinutes;
  final int? servings;

  String get instructions => [
        for (final (i, s) in steps.indexed) '${i + 1}. ${s.trim()}',
      ].join('\n');

  Map<String, dynamic> toJson() => {
        'name': name,
        'caloriesCache': calories,
        'ingredients': ingredients.map((i) => i.toJson()).toList(),
        'instructions': instructions,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        if (servings != null) 'servings': servings,
      };

  /// What POST /recipes takes on the real BE: plain text rows and steps, no
  /// structured quantities and no servings.
  Map<String, dynamic> toBackendJson() => {
        'name': name,
        'calories': calories,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        'ingredients': [
          for (final i in ingredients)
            i.quantity > 0
                ? [i.name, _plainNumber(i.quantity), i.unit]
                    .where((part) => part.isNotEmpty)
                    .join(' ')
                : i.name,
        ],
        'instructions': [for (final s in steps) s.trim()],
      };

  static String _plainNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

/// POST /meal-plans/current/adjust ("Chỉnh thực đơn với AI")
/// `{ "message": "Ít tinh bột hơn cho bữa tối", "scope": "day" | "week", "date": "2026-10-17" }`
class AdjustPlanRequestDto {
  const AdjustPlanRequestDto(
      {required this.message, required this.scope, required this.date});

  final String message;
  final AdjustScope scope;

  /// The day the member is looking at (the whole week for [AdjustScope.week]).
  final DateTime date;

  Map<String, dynamic> toJson() => {
        'message': message,
        'scope': scope.apiValue,
        'date': toApiDate(date),
      };
}

/// One proposed change (`meal_plan_adjustments.changes[]`):
/// `{ "id": "c1", "date": "2026-10-17", "slot": "dinner", "action": "replace" | "add" | "remove",
///    "from": RecipeDto | null, "to": RecipeDto | null, "kcalDelta": -180 }`
class PlanChangeDto {
  const PlanChangeDto({
    required this.id,
    required this.date,
    required this.slot,
    required this.action,
    this.from,
    this.to,
    this.kcalDelta = 0,
  });

  factory PlanChangeDto.fromJson(Map<String, dynamic> json) => PlanChangeDto(
        id: json['id']?.toString() ?? '',
        date: readDate(json['date']),
        slot: json['slot'] as String? ?? MealSlot.lunch.apiValue,
        action: json['action'] as String? ?? 'replace',
        from: json['from'] is Map<String, dynamic>
            ? RecipeDto.fromJson(json['from'] as Map<String, dynamic>)
            : null,
        to: json['to'] is Map<String, dynamic>
            ? RecipeDto.fromJson(json['to'] as Map<String, dynamic>)
            : null,
        kcalDelta: readInt(json['kcalDelta']),
      );

  final String id;
  final DateTime date;
  final String slot;
  final String action;
  final RecipeDto? from;
  final RecipeDto? to;
  final int kcalDelta;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': toApiDate(date),
        'slot': slot,
        'action': action,
        'from': from?.toJson(),
        'to': to?.toJson(),
        'kcalDelta': kcalDelta,
      };

  /// `null` for an unknown slot (newer server).
  PlanChange? toEntity() {
    final s = MealSlot.fromApi(slot);
    if (s == null) return null;
    return PlanChange(
      id: id,
      date: date,
      slot: s,
      action: PlanChangeAction.fromApi(action),
      from: from?.toEntity(),
      to: to?.toEntity(),
      kcalDelta: kcalDelta,
    );
  }
}

/// `{ "proposalId": "adj_1", "reply": "Mình đề xuất 3 thay đổi…", "changes": [PlanChangeDto] }`.
/// Apply with POST /meal-plans/current/adjust/{proposalId}/apply
/// `{ "changeIds": ["c1", "c3"] }` → the updated [MealPlanDto].
class PlanAdjustmentDto {
  const PlanAdjustmentDto(
      {required this.proposalId, required this.reply, this.changes = const []});

  factory PlanAdjustmentDto.fromJson(Map<String, dynamic> json) =>
      PlanAdjustmentDto(
        proposalId: json['proposalId']?.toString() ?? '',
        reply: json['reply'] as String? ?? '',
        changes: json['changes'] is List<Object?>
            ? (json['changes'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(PlanChangeDto.fromJson)
                .toList()
            : const [],
      );

  final String proposalId;
  final String reply;
  final List<PlanChangeDto> changes;

  Map<String, dynamic> toJson() => {
        'proposalId': proposalId,
        'reply': reply,
        'changes': changes.map((c) => c.toJson()).toList(),
      };

  PlanAdjustment toEntity() => PlanAdjustment(
        proposalId: proposalId,
        reply: reply,
        changes: changes.map((c) => c.toEntity()).nonNulls.toList(),
      );
}
