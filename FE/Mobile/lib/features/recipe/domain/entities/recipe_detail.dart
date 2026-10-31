// lib/features/recipe/domain/entities/recipe_detail.dart
import '../../../../core/utils/backend_ids.dart';
import '../../../../core/utils/formatters.dart';
import '../../../meal_planner/domain/allergy_match.dart';

/// The figures an ingredient row can carry.
enum RecipeNutrient { calories, protein, carbs, fat, fiber }

/// kcal and macros an ingredient row (or one of its substitutes) brings to
/// the **whole recipe** at its quantity (base servings). A figure the data
/// doesn't give is `null`: it is never made up.
class IngredientNutrition {
  const IngredientNutrition({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
  });

  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;

  double? of(RecipeNutrient n) => switch (n) {
        RecipeNutrient.calories => calories,
        RecipeNutrient.protein => proteinG,
        RecipeNutrient.carbs => carbsG,
        RecipeNutrient.fat => fatG,
        RecipeNutrient.fiber => fiberG,
      };

  bool get isEmpty => RecipeNutrient.values.every((n) => of(n) == null);
}

/// An alternative the recipe lists for one ingredient row ("Đổi").
class RecipeSubstitute {
  const RecipeSubstitute({
    required this.key,
    required this.name,
    this.quantity,
    this.unit = '',
    this.ingredientId,
    this.note,
    this.allergens,
    this.nutrition,
  });

  /// Unique within its row.
  final String key;
  final String name;
  final double? quantity;
  final String unit;
  final String? ingredientId;

  /// "Nhiều chất xơ hơn".
  final String? note;

  /// `null` = not annotated (≠ none).
  final List<String>? allergens;

  /// For the whole recipe at [quantity].
  final IngredientNutrition? nutrition;

  String get amount => formatAmount(quantity, unit);
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    this.quantity,
    this.unit = '',
    this.ingredientId,
    this.key = '',
    this.role,
    this.isSignature = false,
    this.isOptional = false,
    this.allergens,
    this.nutrition,
    this.substitutes = const [],
    this.isFreeText = false,
  });

  final String name;
  final double? quantity;
  final String unit;
  final String? ingredientId;

  /// Stable within the recipe (swaps and removals refer to it).
  final String key;

  /// The part of the dish this row makes ("Riêu", "Nước dùng"…).
  final String? role;

  /// "Thành phần chính": cannot be removed, only swapped for one of its
  /// [substitutes] (same role).
  final bool isSignature;

  /// "Không bắt buộc": the cook may leave it out.
  final bool isOptional;

  /// `null` = not annotated (≠ none).
  final List<String>? allergens;

  /// For the whole recipe at [quantity].
  final IngredientNutrition? nutrition;
  final List<RecipeSubstitute> substitutes;

  /// A plain-text row from the current API (`"Đậu hũ"`): a name without an
  /// amount.
  final bool isFreeText;

  /// "200 g", "0,5 bông", "vừa ăn"; empty for a name-only row.
  String get amount => isFreeText ? '' : formatAmount(quantity, unit);

  RecipeSubstitute? substitute(String key) {
    for (final s in substitutes) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// One change a saved variant made to its original ("Đã đổi Đậu hũ → Nấm
/// rơm băm nhuyễn", "Đã bỏ Rau muống chẻ").
class RecipeChangeNote {
  const RecipeChangeNote.swap(
      {required String this.from, required String this.to})
      : type = 'swap',
        name = null;

  const RecipeChangeNote.remove(String this.name)
      : type = 'remove',
        from = null,
        to = null;

  /// `swap` | `remove`.
  final String type;
  final String? from;
  final String? to;
  final String? name;

  String get label => type == 'swap' ? 'Đã đổi $from → $to' : 'Đã bỏ $name';
}

/// A recipe with its ingredient rows and method (`recipes` ⋈
/// `recipe_ingredients` ⋈ `ingredients`). Macros and extras are optional.
class RecipeDetail {
  const RecipeDetail({
    required this.id,
    required this.name,
    required this.instructions,
    this.caloriesCache,
    this.isVegan = false,
    this.ingredients = const [],
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.allergens = const [],
    this.prepMinutes,
    this.imageUrl,
    this.servings,
    this.createdBy,
    this.createdByName,
    this.averageRating,
    this.ratingCount = 0,
    this.basedOnRecipeId,
    this.basedOnName,
    this.customizations = const [],
    this.nutritionEstimated = false,
    this.isSnapshot = false,
  });

  final String id;
  final String name;
  final String instructions;

  /// kcal per serving (`recipes.calories_cache`).
  final int? caloriesCache;
  final bool isVegan;
  final List<RecipeIngredient> ingredients;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final List<String> allergens;
  final int? prepMinutes;
  final String? imageUrl;

  /// Servings the quantities are written for; `null` when the recipe
  /// doesn't say (scaled as 1).
  final int? servings;

  /// Author of a member- or chef-written recipe; `null` for the catalogue.
  final String? createdBy;
  final String? createdByName;

  /// Public catalogue recipes only.
  final double? averageRating;
  final int ratingCount;

  /// Set on a saved customization ("Biến thể của «…»").
  final String? basedOnRecipeId;
  final String? basedOnName;
  final List<RecipeChangeNote> customizations;

  /// The server estimated some figures (a change without nutrition data).
  final bool nutritionEstimated;

  /// Only what a meal plan knows about the dish: a typed dish, a chef's dish
  /// with nothing more written, or a recipe the catalogue doesn't return. No
  /// ingredients and no steps.
  final bool isSnapshot;

  /// From the real BE, which has no quantities: the page only reads it, with
  /// no scaling, swaps, reviews or notes (those stay on mock recipes).
  bool get isReadOnly =>
      isSnapshot || isBackendId(id) || isBackendPlanItemId(id);

  List<String> get steps => parseRecipeSteps(instructions);

  bool get hasMacros =>
      proteinG != null || carbsG != null || fatG != null || fiberG != null;

  /// Servings the amounts are for (1 when the recipe doesn't say).
  int get baseServings => (servings ?? 0) > 0 ? servings! : 1;

  /// Catalogue recipe (reviews allowed); member / chef recipes and variants
  /// are private.
  bool get isPublic => createdBy == null;

  bool get isVariant => basedOnRecipeId != null;

  /// Some row can be swapped or left out.
  bool get isCustomizable =>
      ingredients.any((i) => i.substitutes.isNotEmpty || i.isOptional);

  RecipeIngredient? ingredient(String key) {
    for (final i in ingredients) {
      if (i.key == key) return i;
    }
    return null;
  }

  /// The member's allergy keys this recipe conflicts with: tagged allergen
  /// ids, plus free-text allergies ("lá lốt") found in its name or its
  /// ingredient rows.
  List<String> allergenConflicts(Iterable<String> userAllergies) =>
      allergyConflicts(
        tags: allergens,
        texts: [name, for (final i in ingredients) i.name],
        userAllergies: userAllergies,
      );
}

final _stepNumber =
    RegExp(r'^\s*(?:bước\s*)?\d+\s*[.):\-–]\s*', caseSensitive: false);

/// One step per non-empty line, without a leading "1." / "Bước 2:".
List<String> parseRecipeSteps(String instructions) => instructions
    .split(RegExp(r'\r?\n'))
    .map((line) => line.replaceFirst(_stepNumber, '').trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// 200 → "200", 0.5 → "0,5", 1.25 → "1,25".
String formatQuantity(double value) {
  if (value == value.roundToDouble()) return formatInt(value);
  final fixed = value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return fixed.replaceAll('.', ',');
}

/// "200 g", "2", or the [unit] text alone ("vừa ăn") when there is no
/// quantity; "vừa ăn" when there is neither.
String formatAmount(double? quantity, String unit) {
  final q = quantity;
  if (q == null || q <= 0) return unit.isEmpty ? 'vừa ăn' : unit;
  return unit.isEmpty ? formatQuantity(q) : '${formatQuantity(q)} $unit';
}
