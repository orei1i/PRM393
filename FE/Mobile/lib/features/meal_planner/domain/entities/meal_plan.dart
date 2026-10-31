// lib/features/meal_planner/domain/entities/meal_plan.dart
import '../../../../core/utils/formatters.dart';
import '../allergy_match.dart';
import 'health_profile.dart';
import 'meal_slot.dart';

export 'meal_slot.dart';

/// The macros a dish can carry, with their Vietnamese labels.
enum Macro {
  protein('Đạm', 'Đạm'),
  carbs('Tinh bột', 'Tinh bột'),
  fat('Chất béo', 'Béo'),
  fiber('Chất xơ', 'Chất xơ');

  const Macro(this.label, this.shortLabel);

  /// "Chất béo" on the day's bars.
  final String label;

  /// "Béo" in a dish's one-line summary.
  final String shortLabel;

  double? of(Nutrition n) => switch (this) {
        protein => n.proteinG,
        carbs => n.carbsG,
        fat => n.fatG,
        fiber => n.fiberG,
      };
}

/// kcal and macros of a dish (or a day's totals / targets). A macro nobody
/// provided is `null`: it is never shown as "0 g" and never made up.
class Nutrition {
  const Nutrition({
    required this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
  });

  static const zero =
      Nutrition(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0);

  /// 0 when unknown (a dish typed in without kcal).
  final int calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;

  /// The macros this dish has no figure for.
  Set<Macro> get missingMacros => {
        for (final m in Macro.values)
          if (m.of(this) == null) m
      };

  /// "Đạm 15 g · Tinh bột 58 g · Béo 12 g" from the known values of [macros]
  /// only; `null` when none of them is known.
  String? summary(
      {List<Macro> macros = const [Macro.protein, Macro.carbs, Macro.fat]}) {
    final parts = [
      for (final m in macros)
        if (m.of(this) case final grams?) '${m.shortLabel} ${grams.round()} g',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// For a day's totals only: a missing macro of a dish with kcal is
  /// estimated from those kcal (20 % protein, 55 % carbs, 25 % fat; 1 g of
  /// fibre per 70 kcal). The UI marks such totals "ước tính"; the dish's own
  /// figures are never replaced. A dish without kcal adds nothing.
  Nutrition withEstimates() {
    double estimate(double share, int kcalPerGram) =>
        (calories * share / kcalPerGram).roundToDouble();
    return Nutrition(
      calories: calories,
      proteinG: proteinG ?? estimate(0.20, 4),
      carbsG: carbsG ?? estimate(0.55, 4),
      fatG: fatG ?? estimate(0.25, 9),
      fiberG: fiberG ?? (calories / 70).roundToDouble(),
    );
  }

  /// Unknown + unknown stays unknown; otherwise an unknown side counts as 0
  /// (totals use [withEstimates] first).
  Nutrition operator +(Nutrition other) {
    double? add(double? a, double? b) =>
        a == null && b == null ? null : (a ?? 0) + (b ?? 0);
    return Nutrition(
      calories: calories + other.calories,
      proteinG: add(proteinG, other.proteinG),
      carbsG: add(carbsG, other.carbsG),
      fatG: add(fatG, other.fatG),
      fiberG: add(fiberG, other.fiberG),
    );
  }
}

/// Where a planned meal came from (`meal_plan_recipes.source`). Every slot
/// shows it as a badge; missing on the wire → [ai] (generated plans).
enum MealSource {
  ai('ai', 'AI gợi ý'),
  manual('manual', 'Tự nhập'),
  userRecipe('user_recipe', 'Công thức của tôi'),
  chef('chef', 'Chuyên gia'),
  fridgeScan('fridge_scan', 'Từ tủ lạnh'),

  /// Added from a catalogue recipe's page ("Thêm vào Thực đơn").
  recipe('recipe', 'Từ công thức');

  const MealSource(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static MealSource fromApi(String? value) =>
      values.firstWhere((s) => s.apiValue == value, orElse: () => ai);
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
    this.source = MealSource.ai,
    this.sourceName,
    this.createdBy,
    this.portion = 1,
    this.serverConflicts = const [],
  });

  final String id;
  final String name;
  final String? imageUrl;

  /// For [portion] servings (what this slot holds), not per serving.
  final Nutrition nutrition;
  final List<String> allergens;
  final List<String> dietTags;
  final int? prepMinutes;
  final SeasonalSwap? seasonalSwap;

  /// How this dish got into the slot.
  final MealSource source;

  /// Who suggested it, e.g. the chef's name for [MealSource.chef].
  final String? sourceName;

  /// Owner of a member-written recipe (`recipes.created_by`); `null` for
  /// the catalogue.
  final String? createdBy;

  /// Servings in the slot (`meal_plan_recipes.portion`): an AI plan sizes
  /// portions so the day meets its kcal target. 1 = one serving.
  final double portion;

  /// The member's allergy keys the server found in this dish, including in
  /// ingredients the app can't see.
  final List<String> serverConflicts;

  /// "1,5 phần" when the slot holds more or less than one serving.
  String? get portionLabel {
    if (portion == 1) return null;
    final text = portion
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.?0+$'), '')
        .replaceAll('.', ',');
    return '$text phần';
  }

  /// `false` for dishes typed in without a kcal estimate.
  bool get hasNutrition => nutrition.calories > 0;

  /// Typed-in dishes have no recipe page.
  bool get hasDetail => source != MealSource.manual;

  /// The member's allergy keys this dish conflicts with: tagged allergen ids,
  /// plus free-text allergies ("lá lốt") found in its name. Nobody tagged a
  /// typed-in dish, so its name is read for allergens too, whatever the server
  /// kept of them.
  List<String> allergenConflicts(Iterable<String> userAllergies) {
    final local = allergyConflicts(
        tags: source == MealSource.manual
            ? {...allergens, ...detectDishAllergens(name)}
            : allergens,
        texts: [name],
        userAllergies: userAllergies);
    if (serverConflicts.isEmpty) return local;
    return [
      ...local,
      for (final key in serverConflicts)
        if (!local.contains(key)) key,
    ];
  }

  Recipe withSource(MealSource source, {String? sourceName}) => Recipe(
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
        serverConflicts: serverConflicts,
      );
}

/// A dish a chef suggested to this member ("Từ chuyên gia"), e.g. a day of a
/// plan the member booked a chef for.
class ChefSuggestion {
  const ChefSuggestion({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.recipe,
    this.note,
    this.slot,
    this.targetDate,
    this.createdAt,
  });

  final String id;
  final String chefId;
  final String chefName;
  final Recipe recipe;
  final String? note;

  /// Meal the chef had in mind, if any.
  final MealSlot? slot;

  /// Day the chef had in mind (date only), if any.
  final DateTime? targetDate;
  final DateTime? createdAt;

  /// "Cho bữa tối · Thứ Sáu, 17/10" when the chef picked a day ("Cho Thứ
  /// Sáu, 17/10" without a meal); `null` otherwise.
  String? get scheduleLabel {
    final day = targetDate;
    if (day == null) return null;
    final meal = slot;
    return meal == null
        ? 'Cho ${formatLongDate(day)}'
        : 'Cho ${meal.label.toLowerCase()} · ${formatLongDate(day)}';
  }
}

/// Where a fridge item came from.
enum PantrySource {
  scan('Quét'),
  manual('Tự thêm');

  const PantrySource(this.label);
  final String label;
}

/// One `user_ingredients` row: a vegan food in the member's fridge. Just a
/// name: no quantity (the scan only says what is there) and no freshness.
class PantryItem {
  const PantryItem({
    required this.id,
    required this.ingredient,
    this.scannedAt,
    this.ingredientId,
    this.category,
    this.caloriesPer100g,
    this.quantity,
    this.unit,
    this.expiryDate,
    this.allergyWarning,
  });

  final String id;
  final String ingredient;

  /// `null` for items typed in by hand.
  final DateTime? scannedAt;

  /// The nutrition-DB row (`ingredients.id`) the name matched, if any.
  final String? ingredientId;

  /// `ingredients.category` api value (`leafy`, `mushroom`…), if known.
  final String? category;

  /// kcal per 100 g, if the ingredient is in the nutrition DB.
  final int? caloriesPer100g;

  /// What the real BE keeps (default 1 "phần"); `null` from the mock.
  final double? quantity;
  final String? unit;
  final DateTime? expiryDate;

  /// Set by the real BE when the item conflicts with the member's allergies.
  final String? allergyWarning;

  /// Expired, or expires within 3 days of [now] ("Sắp hết hạn").
  bool expiresSoon(DateTime now) {
    final expiry = expiryDate;
    if (expiry == null) return false;
    final local = expiry.toLocal();
    final days = DateTime(local.year, local.month, local.day)
        .difference(dateOnly(now))
        .inDays;
    return days <= 3;
  }

  /// "Quét" when saved from a fridge scan, "Tự thêm" when typed in.
  PantrySource get source =>
      scannedAt == null ? PantrySource.manual : PantrySource.scan;
}

/// Input to `PantryController.addFromScan`: what the scanner confirmed. Only
/// vegan items are saved; [isVegan] is the scanner's verdict (the server's
/// when it sent one). [source] is [PantrySource.scan] only for foods the
/// camera or a photo detected; names typed in the tray ("Nhập tay") and
/// vegan swaps picked there are [PantrySource.manual] ("Tự thêm").
class ScannedPantryItem {
  const ScannedPantryItem({
    required this.name,
    this.isVegan = true,
    this.source = PantrySource.scan,
  });

  final String name;
  final bool isVegan;
  final PantrySource source;
}

class MealPlanDay {
  const MealPlanDay({required this.date, required this.meals});

  final DateTime date;
  final Map<MealSlot, Recipe> meals;

  /// The day's kcal and macros. Macros a dish was saved without are
  /// estimated from its kcal ([Nutrition.withEstimates]); [estimatedMacros]
  /// says which totals include such an estimate.
  Nutrition get totals => meals.values.fold(
      Nutrition.zero, (sum, recipe) => sum + recipe.nutrition.withEstimates());

  /// Totals that include an estimate (shown "≈ … ước tính").
  Set<Macro> get estimatedMacros => {
        for (final r in mealsWithEstimates) ...r.nutrition.missingMacros,
      };

  /// Dishes with kcal but without some macros: their share of [totals] is
  /// estimated.
  List<Recipe> get mealsWithEstimates => [
        for (final r in meals.values)
          if (r.hasNutrition && r.nutrition.missingMacros.isNotEmpty) r,
      ];

  MealPlanDay replaceMeal(MealSlot slot, Recipe recipe) =>
      MealPlanDay(date: date, meals: {...meals, slot: recipe});

  int conflictCount(Iterable<String> userAllergies) => meals.values
      .where((r) => r.allergenConflicts(userAllergies).isNotEmpty)
      .length;

  /// Slots shown for this day: the member's [pattern] plus any other slot
  /// that holds a dish (an extra meal added to this day only), in day order.
  List<MealSlot> slotsFor(Iterable<MealSlot> pattern) {
    final mine = pattern.toSet();
    return [
      for (final s in MealSlot.values)
        if (mine.contains(s) || meals.containsKey(s)) s
    ];
  }

  /// Slots "＋ Thêm bữa" can still add to this day.
  List<MealSlot> missingSlots(Iterable<MealSlot> pattern) {
    final shown = slotsFor(pattern).toSet();
    return [
      for (final s in MealSlot.values)
        if (!shown.contains(s)) s
    ];
  }
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
