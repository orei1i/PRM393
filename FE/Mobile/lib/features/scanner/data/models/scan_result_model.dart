// lib/features/scanner/data/models/scan_result_model.dart
//
// POST /vision/scan  (multipart: image)
// {
//   "scanId": "scn_7f3c",
//   "items": [
//     { "id": "det_1", "label": "Bông cải xanh", "confidence": 0.96, "isVegan": true,
//       "bbox": { "x": 0.06, "y": 0.18, "w": 0.30, "h": 0.22 },
//       "alternatives": [ { "label": "Súp lơ", "confidence": 0.03, "isVegan": true } ] },
//     { "id": "det_6", "label": "Trứng gà", "confidence": 0.94, "isVegan": false,
//       "nonVeganReason": "Có nguồn gốc động vật: trứng",
//       "veganAlternatives": [ "Đậu hũ non" ],
//       "bbox": { "x": 0.05, "y": 0.43, "w": 0.36, "h": 0.12 } }
//   ]
// }
//
// The scan says what each food is and whether it is vegan (thuần chay).
// `isVegan` mirrors `ingredients.is_vegan` (camelCase, like `recipes.is_vegan`
// → `isVegan`); `nonVeganReason` and `veganAlternatives` are optional and
// only used when `isVegan` is false. Without `isVegan` the app falls back to
// its local check (`classifyVegan`); when present, the server wins.
//
// Confirm-only: a `quantity` / `unit` the model may still send is ignored
// (the fridge, `user_ingredients`, keeps no amounts), and so is the
// `freshness` field of older servers.

import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../../domain/vegan_check.dart';

/// `true` / `false`, also `1` / `0` (SQL `BIT`); `null` when absent.
bool? _readBool(Object? value) => switch (value) {
      final bool b => b,
      final num n => n != 0,
      'true' || 'True' || '1' => true,
      'false' || 'False' || '0' => false,
      _ => null,
    };

class BoundingBoxDto {
  const BoundingBoxDto(
      {required this.x, required this.y, required this.w, required this.h});

  factory BoundingBoxDto.fromJson(Map<String, dynamic> json) => BoundingBoxDto(
        x: readDouble(json['x']),
        y: readDouble(json['y']),
        w: readDouble(json['w']),
        h: readDouble(json['h']),
      );

  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  NormalizedBox toEntity() =>
      NormalizedBox(left: x, top: y, width: w, height: h);
}

class DetectedIngredientDto {
  const DetectedIngredientDto({
    required this.id,
    required this.label,
    required this.confidence,
    this.isVegan,
    this.nonVeganReason,
    this.veganAlternatives = const [],
    this.bbox,
    this.alternatives = const [],
  });

  factory DetectedIngredientDto.fromJson(Map<String, dynamic> json) =>
      DetectedIngredientDto(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        confidence: readDouble(json['confidence']),
        isVegan: _readBool(json['isVegan']),
        nonVeganReason: json['nonVeganReason'] as String?,
        veganAlternatives: readStringList(json['veganAlternatives']),
        bbox: json['bbox'] is Map<String, dynamic>
            ? BoundingBoxDto.fromJson(json['bbox'] as Map<String, dynamic>)
            : null,
        alternatives: (json['alternatives'] is List<Object?>)
            ? (json['alternatives'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map((a) => (
                      label: a['label'] as String? ?? '',
                      confidence: readDouble(a['confidence']),
                      isVegan: _readBool(a['isVegan']),
                    ))
                .toList()
            : const [],
      );

  final String id;
  final String label;
  final double confidence;

  /// `null` when the server didn't say (the app then checks locally).
  final bool? isVegan;
  final String? nonVeganReason;
  final List<String> veganAlternatives;
  final BoundingBoxDto? bbox;
  final List<({String label, double confidence, bool? isVegan})> alternatives;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'confidence': confidence,
        if (isVegan != null) 'isVegan': isVegan,
        if (nonVeganReason != null) 'nonVeganReason': nonVeganReason,
        if (veganAlternatives.isNotEmpty)
          'veganAlternatives': veganAlternatives,
        if (bbox != null) 'bbox': bbox!.toJson(),
        'alternatives': [
          for (final a in alternatives)
            {
              'label': a.label,
              'confidence': a.confidence,
              if (a.isVegan != null) 'isVegan': a.isVegan,
            },
        ],
      };

  DetectedIngredient toEntity() {
    final vegan = resolveVegan(label,
        serverIsVegan: isVegan,
        serverReason: nonVeganReason,
        serverAlternatives: veganAlternatives);
    return DetectedIngredient(
      id: id,
      name: label,
      confidence: confidence,
      isVegan: vegan.isVegan,
      nonVeganReason: vegan.nonVeganReason,
      veganAlternatives: vegan.veganAlternatives,
      box: bbox?.toEntity(),
      alternatives: [
        for (final a in alternatives)
          IngredientAlternative(
              name: a.label, confidence: a.confidence, isVegan: a.isVegan),
      ],
      confirmed: confidence >= DetectedIngredient.confirmThreshold,
    );
  }
}

class ScanResultDto {
  const ScanResultDto({required this.scanId, required this.items});

  factory ScanResultDto.fromJson(Map<String, dynamic> json) => ScanResultDto(
        scanId: json['scanId'] as String? ?? '',
        items: (json['items'] is List<Object?>)
            ? (json['items'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(DetectedIngredientDto.fromJson)
                .toList()
            : const [],
      );

  final String scanId;
  final List<DetectedIngredientDto> items;

  Map<String, dynamic> toJson() => {
        'scanId': scanId,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// POST /meal-plans/from-ingredients
/// `{ "ingredients": [ { "name": "Đậu hũ" } ], "excludeAllergens": ["peanut"] }`
/// Vegan items only: anything not vegan is left out of the request.
class GenerateMenuRequestDto {
  GenerateMenuRequestDto(
      {required List<DetectedIngredient> ingredients,
      required this.excludeAllergens})
      : ingredients = ingredients.where((i) => i.isVegan).toList();

  final List<DetectedIngredient> ingredients;
  final List<String> excludeAllergens;

  Map<String, dynamic> toJson() => {
        'ingredients': [
          for (final i in ingredients) {'name': i.name},
        ],
        'excludeAllergens': excludeAllergens,
      };
}

/// Item of the `POST /meal-plans/from-ingredients` response:
/// `{ "id", "name", "calories", "prepMinutes", "usedIngredients": [],
///    "missingIngredients": [], "allergens": ["soy"] }`
class MenuSuggestionDto {
  const MenuSuggestionDto({
    required this.id,
    required this.name,
    required this.calories,
    required this.prepMinutes,
    required this.usedIngredients,
    required this.missingIngredients,
    this.allergens = const [],
  });

  factory MenuSuggestionDto.fromJson(Map<String, dynamic> json) =>
      MenuSuggestionDto(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        calories: readInt(json['calories']),
        prepMinutes: readInt(json['prepMinutes']),
        usedIngredients: readStringList(json['usedIngredients']),
        missingIngredients: readStringList(json['missingIngredients']),
        allergens: readStringList(json['allergens']),
      );

  final String id;
  final String name;
  final int calories;
  final int prepMinutes;
  final List<String> usedIngredients;
  final List<String> missingIngredients;
  final List<String> allergens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'prepMinutes': prepMinutes,
        'usedIngredients': usedIngredients,
        'missingIngredients': missingIngredients,
        'allergens': allergens,
      };

  MenuSuggestion toEntity() => MenuSuggestion(
        id: id,
        name: name,
        calories: calories,
        prepMinutes: prepMinutes,
        usedIngredients: usedIngredients,
        missingIngredients: missingIngredients,
        allergens: allergens,
      );
}
