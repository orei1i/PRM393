// lib/features/recipe/data/models/recipe_detail_model.dart
//
// GET /recipes/{id}   (recipes ⋈ recipe_ingredients ⋈ ingredients; extras optional)
// { "id": 105, "name": "Bún riêu chay", "instructions": "Phi thơm hành…\nCho cà chua vào…\n…",
//   "caloriesCache": 520, "isVegan": true,
//   "ingredients": [ { "ingredientId": 7, "name": "Đậu hũ", "quantity": 200, "unit": "g", "nutritionInfo": null } ],
//   "proteinG": 24, "carbsG": 70, "fatG": 14, "fiberG": 8, "allergens": ["soy"], "prepMinutes": 35,
//   "imageUrl": null, "servings": 2, "createdBy": null, "createdByName": null }
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/recipe_detail.dart';

class RecipeIngredientDto {
  const RecipeIngredientDto({
    required this.name,
    this.quantity,
    this.unit = '',
    this.ingredientId,
  });

  factory RecipeIngredientDto.fromJson(Map<String, dynamic> json) {
    final q = json['quantity'];
    return RecipeIngredientDto(
      ingredientId: json['ingredientId']?.toString(),
      name: json['name'] as String? ?? '',
      quantity: q is num
          ? q.toDouble()
          : (q is String ? double.tryParse(q.replaceAll(',', '.')) : null),
      unit: json['unit'] as String? ?? '',
    );
  }

  final String? ingredientId;
  final String name;
  final double? quantity;
  final String unit;

  RecipeIngredient toEntity() => RecipeIngredient(
      ingredientId: ingredientId, name: name, quantity: quantity, unit: unit);
}

class RecipeDetailDto {
  const RecipeDetailDto({
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

  factory RecipeDetailDto.fromJson(Map<String, dynamic> json) {
    double? optDouble(String key) =>
        json[key] == null ? null : readDouble(json[key]);
    int? optInt(String key) => json[key] == null ? null : readInt(json[key]);
    final rawSteps = json['instructions'] ?? json['steps'];
    return RecipeDetailDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      instructions: rawSteps is List<Object?>
          ? rawSteps.map((s) => s.toString()).join('\n')
          : rawSteps?.toString() ?? '',
      caloriesCache: optInt('caloriesCache') ?? optInt('calories'),
      isVegan: json['isVegan'] == true,
      ingredients: json['ingredients'] is List<Object?>
          ? (json['ingredients'] as List<Object?>)
              .whereType<Map<String, dynamic>>()
              .map(RecipeIngredientDto.fromJson)
              .toList()
          : const [],
      proteinG: optDouble('proteinG'),
      carbsG: optDouble('carbsG'),
      fatG: optDouble('fatG'),
      fiberG: optDouble('fiberG'),
      allergens: readStringList(json['allergens']),
      prepMinutes: optInt('prepMinutes'),
      imageUrl: json['imageUrl'] as String?,
      servings: optInt('servings'),
      createdBy: json['createdBy']?.toString(),
      createdByName: json['createdByName'] as String?,
    );
  }

  final String id;
  final String name;
  final String instructions;
  final int? caloriesCache;
  final bool isVegan;
  final List<RecipeIngredientDto> ingredients;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final List<String> allergens;
  final int? prepMinutes;
  final String? imageUrl;
  final int? servings;
  final String? createdBy;
  final String? createdByName;

  RecipeDetail toEntity() => RecipeDetail(
        id: id,
        name: name,
        instructions: instructions,
        caloriesCache: caloriesCache,
        isVegan: isVegan,
        ingredients: ingredients.map((i) => i.toEntity()).toList(),
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        fiberG: fiberG,
        allergens: allergens,
        prepMinutes: prepMinutes,
        imageUrl: imageUrl,
        servings: servings,
        createdBy: createdBy,
        createdByName: createdByName,
      );
}
