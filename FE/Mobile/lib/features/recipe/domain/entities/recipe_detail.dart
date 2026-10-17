// lib/features/recipe/domain/entities/recipe_detail.dart
import '../../../../core/utils/formatters.dart';
import '../../../meal_planner/domain/allergy_match.dart';

class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    this.quantity,
    this.unit = '',
    this.ingredientId,
  });

  final String name;
  final double? quantity;
  final String unit;
  final String? ingredientId;

  /// "200 g", "0,5 bông", "vừa ăn".
  String get amount {
    final q = quantity;
    if (q == null || q <= 0) return unit.isEmpty ? 'vừa ăn' : unit;
    return unit.isEmpty ? formatQuantity(q) : '${formatQuantity(q)} $unit';
  }
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
  final int? servings;

  /// Author of a member- or chef-written recipe; `null` for the catalogue.
  final String? createdBy;
  final String? createdByName;

  List<String> get steps => parseRecipeSteps(instructions);

  bool get hasMacros =>
      proteinG != null || carbsG != null || fatG != null || fiberG != null;

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
