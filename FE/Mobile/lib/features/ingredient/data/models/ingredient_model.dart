// lib/features/ingredient/data/models/ingredient_model.dart
//
// Nutrition DB (`ingredients` ⋈ `ingredient_nutrition` ⋈
// `ingredient_incompatibilities`), values per 100 g.
//
// GET /ingredients?q=&veganOnly=true → [IngredientSummaryDto]
// { "id": "ing_ca_chua", "name": "Cà chua", "category": "veg", "isVegan": true,
//   "aliases": ["cà chua bi"], "caloriesPer100g": 18,
//   "serving": { "label": "100 g", "grams": 100 }, "altServing": { "label": "1 quả", "grams": 123 } }
//
// GET /ingredients/{id} → IngredientDetailDto
// { …summary,
//   "per100g": { "calories": 18, "proteinG": 0.9, "fatG": 0.2, "carbsG": 3.9, "fiberG": 1.2, "sugarG": 2.6 },
//   "micronutrients": [ { "name": "Vitamin C", "amount": 13.7, "unit": "mg", "dvPercent": 15 } ],
//   "goodFor": ["…"], "cautionFor": ["…"],
//   "avoidCombining": [ { "name": "Dưa leo", "reason": "…" } ],
//   "suggestedDishes": ["Canh cà chua đậu hũ"],
//   "recipes": [ { "id": "l5", "name": "Bún riêu chay", "calories": 580 } ],
//   "allergens": [], "source": "Tham khảo: …" }
// A macro the source doesn't give is null (never 0).
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/ingredient.dart';

double? _grams(Object? v) => v == null ? null : readDouble(v);

class IngredientSummaryDto {
  const IngredientSummaryDto({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    this.category,
    this.aliases = const [],
    this.altServingLabel,
    this.altServingGrams,
    this.isVegan = true,
  });

  factory IngredientSummaryDto.fromJson(Map<String, dynamic> json) {
    final per100g = readMap(json['per100g']);
    final alt = readMap(json['altServing']);
    return IngredientSummaryDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String?,
      aliases: readStringList(json['aliases']),
      caloriesPer100g: readInt(json['caloriesPer100g'] ?? per100g['calories']),
      altServingLabel: alt['label'] as String?,
      altServingGrams: _grams(alt['grams']),
      isVegan: json['isVegan'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final String? category;
  final List<String> aliases;
  final int caloriesPer100g;
  final String? altServingLabel;
  final double? altServingGrams;
  final bool isVegan;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'isVegan': isVegan,
        'aliases': aliases,
        'caloriesPer100g': caloriesPer100g,
        'serving': {'label': '100 g', 'grams': 100},
        if (altServingLabel != null)
          'altServing': {'label': altServingLabel, 'grams': altServingGrams},
      };

  IngredientSummary toEntity() => IngredientSummary(
        id: id,
        name: name,
        category: IngredientCategory.fromApi(category),
        aliases: aliases,
        caloriesPer100g: caloriesPer100g,
        altServingLabel: altServingLabel,
        altServingGrams: altServingGrams,
        isVegan: isVegan,
      );
}

class IngredientDetailDto {
  const IngredientDetailDto({
    required this.summary,
    this.proteinG,
    this.fatG,
    this.carbsG,
    this.fiberG,
    this.sugarG,
    this.micronutrients = const [],
    this.goodFor = const [],
    this.cautionFor = const [],
    this.avoidCombining = const [],
    this.suggestedDishes = const [],
    this.recipes = const [],
    this.allergens = const [],
    this.source,
  });

  factory IngredientDetailDto.fromJson(Map<String, dynamic> json) {
    final per100g = readMap(json['per100g']);
    List<Map<String, dynamic>> maps(Object? v) => v is List<Object?>
        ? v.whereType<Map<String, dynamic>>().toList()
        : const [];
    return IngredientDetailDto(
      summary: IngredientSummaryDto.fromJson(json),
      proteinG: _grams(per100g['proteinG']),
      fatG: _grams(per100g['fatG']),
      carbsG: _grams(per100g['carbsG']),
      fiberG: _grams(per100g['fiberG']),
      sugarG: _grams(per100g['sugarG']),
      micronutrients: [
        for (final m in maps(json['micronutrients']))
          Micronutrient(
            name: m['name'] as String? ?? '',
            amount: readDouble(m['amount']),
            unit: m['unit'] as String? ?? '',
            dvPercent: m['dvPercent'] == null ? null : readInt(m['dvPercent']),
          ),
      ],
      goodFor: readStringList(json['goodFor']),
      cautionFor: readStringList(json['cautionFor']),
      avoidCombining: [
        for (final m in maps(json['avoidCombining']))
          IngredientPairing(
            name: m['name'] as String? ?? '',
            reason: m['reason'] as String? ?? '',
          ),
      ],
      suggestedDishes: readStringList(json['suggestedDishes']),
      recipes: [
        for (final m in maps(json['recipes']))
          IngredientRecipe(
            id: m['id']?.toString() ?? '',
            name: m['name'] as String? ?? '',
            calories: m['calories'] == null ? null : readInt(m['calories']),
          ),
      ],
      allergens: readStringList(json['allergens']),
      source: json['source'] as String?,
    );
  }

  final IngredientSummaryDto summary;
  final double? proteinG;
  final double? fatG;
  final double? carbsG;
  final double? fiberG;
  final double? sugarG;
  final List<Micronutrient> micronutrients;
  final List<String> goodFor;
  final List<String> cautionFor;
  final List<IngredientPairing> avoidCombining;
  final List<String> suggestedDishes;
  final List<IngredientRecipe> recipes;
  final List<String> allergens;
  final String? source;

  IngredientDetail toEntity() => IngredientDetail(
        summary: summary.toEntity(),
        proteinG: proteinG,
        fatG: fatG,
        carbsG: carbsG,
        fiberG: fiberG,
        sugarG: sugarG,
        micronutrients: micronutrients,
        goodFor: goodFor,
        cautionFor: cautionFor,
        avoidCombining: avoidCombining,
        suggestedDishes: suggestedDishes,
        recipes: recipes,
        allergenIds: allergens,
        source: source,
      );
}
