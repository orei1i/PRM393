// lib/features/scanner/data/models/scan_result_model.dart
//
// POST /vision/scan  (multipart: image)
// {
//   "scan_id": "scn_7f3c",
//   "items": [
//     { "id": "det_1", "label": "Bông cải xanh", "confidence": 0.96, "freshness": "fresh",
//       "bbox": { "x": 0.06, "y": 0.18, "w": 0.30, "h": 0.22 },
//       "quantity": 1, "unit": "bông",
//       "alternatives": [ { "label": "Súp lơ", "confidence": 0.03 } ] }
//   ]
// }

import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/detected_ingredient.dart';

class BoundingBoxDto {
  const BoundingBoxDto({required this.x, required this.y, required this.w, required this.h});

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

  NormalizedBox toEntity() => NormalizedBox(left: x, top: y, width: w, height: h);
}

class DetectedIngredientDto {
  const DetectedIngredientDto({
    required this.id,
    required this.label,
    required this.confidence,
    required this.freshness,
    this.bbox,
    this.quantity = 1,
    this.unit = 'phần',
    this.alternatives = const [],
  });

  factory DetectedIngredientDto.fromJson(Map<String, dynamic> json) => DetectedIngredientDto(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        confidence: readDouble(json['confidence']),
        freshness: json['freshness'] as String? ?? 'unknown',
        bbox: json['bbox'] is Map<String, dynamic>
            ? BoundingBoxDto.fromJson(json['bbox'] as Map<String, dynamic>)
            : null,
        quantity: json['quantity'] == null ? 1 : readDouble(json['quantity']),
        unit: json['unit'] as String? ?? 'phần',
        alternatives: (json['alternatives'] is List<Object?>)
            ? (json['alternatives'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map((a) => (label: a['label'] as String? ?? '', confidence: readDouble(a['confidence'])))
                .toList()
            : const [],
      );

  final String id;
  final String label;
  final double confidence;
  final String freshness;
  final BoundingBoxDto? bbox;
  final double quantity;
  final String unit;
  final List<({String label, double confidence})> alternatives;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'confidence': confidence,
        'freshness': freshness,
        if (bbox != null) 'bbox': bbox!.toJson(),
        'quantity': quantity,
        'unit': unit,
        'alternatives': [
          for (final a in alternatives) {'label': a.label, 'confidence': a.confidence},
        ],
      };

  DetectedIngredient toEntity() => DetectedIngredient(
        id: id,
        name: label,
        confidence: confidence,
        freshness: Freshness.fromApi(freshness),
        box: bbox?.toEntity(),
        quantity: quantity,
        unit: unit,
        alternatives: [
          for (final a in alternatives) IngredientAlternative(name: a.label, confidence: a.confidence),
        ],
        confirmed: confidence >= DetectedIngredient.confirmThreshold,
      );
}

class ScanResultDto {
  const ScanResultDto({required this.scanId, required this.items});

  factory ScanResultDto.fromJson(Map<String, dynamic> json) => ScanResultDto(
        scanId: json['scan_id'] as String? ?? '',
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
        'scan_id': scanId,
        'items': items.map((i) => i.toJson()).toList(),
      };
}

/// POST /meal-plans/from-ingredients
class GenerateMenuRequestDto {
  const GenerateMenuRequestDto({required this.ingredients, required this.excludeAllergens});

  final List<DetectedIngredient> ingredients;
  final List<String> excludeAllergens;

  Map<String, dynamic> toJson() => {
        'ingredients': [
          for (final i in ingredients)
            {'name': i.name, 'quantity': i.quantity, 'unit': i.unit, 'freshness': i.freshness.apiValue},
        ],
        'exclude_allergens': excludeAllergens,
        'prefer_use_soon': true,
      };
}

class MenuSuggestionDto {
  const MenuSuggestionDto({
    required this.id,
    required this.name,
    required this.calories,
    required this.prepMinutes,
    required this.usedIngredients,
    required this.missingIngredients,
  });

  factory MenuSuggestionDto.fromJson(Map<String, dynamic> json) => MenuSuggestionDto(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        calories: readInt(json['calories']),
        prepMinutes: readInt(json['prep_minutes']),
        usedIngredients: readStringList(json['used_ingredients']),
        missingIngredients: readStringList(json['missing_ingredients']),
      );

  final String id;
  final String name;
  final int calories;
  final int prepMinutes;
  final List<String> usedIngredients;
  final List<String> missingIngredients;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'calories': calories,
        'prep_minutes': prepMinutes,
        'used_ingredients': usedIngredients,
        'missing_ingredients': missingIngredients,
      };

  MenuSuggestion toEntity() => MenuSuggestion(
        id: id,
        name: name,
        calories: calories,
        prepMinutes: prepMinutes,
        usedIngredients: usedIngredients,
        missingIngredients: missingIngredients,
      );
}
