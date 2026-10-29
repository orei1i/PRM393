// lib/features/recipe/data/models/recipe_detail_model.dart
//
// GET /recipes/{id} (AllowAnonymous). Every field past the basics is optional,
// so older payloads still parse:
// { "id": "l5", "name": "Bún riêu chay", "caloriesCache": 580, "isVegan": true,
//   "proteinG": 24, "carbsG": 86, "fatG": 12, "fiberG": 8, "allergens": ["soy"],
//   "prepMinutes": 60, "servings": 2, "imageUrl": null,
//   "createdBy": null, "createdByName": null,
//   "averageRating": 4.6, "ratingCount": 5,
//   "basedOnRecipeId": null, "basedOnName": null, "customizations": [],
//   "nutritionEstimated": false,
//   "ingredients": [
//     { "key": "rieu", "ingredientId": "ing_dau_hu", "name": "Đậu hũ",
//       "quantity": 300, "unit": "g", "role": "Riêu", "isSignature": true,
//       "isOptional": false, "allergens": ["soy"],
//       "nutrition": { "calories": 228, "proteinG": 24.3, "carbsG": 5.7, "fatG": 14.4, "fiberG": 0.9 },
//       "substitutes": [ { "key": "rieu_nam", "name": "Nấm rơm băm nhuyễn", "quantity": 300,
//                          "unit": "g", "note": "…", "allergens": [], "nutrition": { … } } ] },
//     "Hành lá 2 nhánh",          // the current BE sends plain strings
//     "Muối" ],
//   "instructions": "1. …\n2. …" }
//
// Row `nutrition` is the contribution to the whole recipe at that quantity.
// Row `allergens` absent/null = not annotated (≠ []).
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/recipe_detail.dart';

double? _optDouble(Object? value) => value == null ? null : readDouble(value);

double? _quantity(Object? q) => q is num
    ? q.toDouble()
    : (q is String ? double.tryParse(q.replaceAll(',', '.')) : null);

List<String>? _optStringList(Object? value) =>
    value is List<Object?> ? value.map((e) => '$e').toList() : null;

String? _optString(Object? value) {
  final s = value?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

IngredientNutrition? parseIngredientNutrition(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final n = IngredientNutrition(
    calories: _optDouble(raw['calories'] ?? raw['kcal']),
    proteinG: _optDouble(raw['proteinG']),
    carbsG: _optDouble(raw['carbsG']),
    fatG: _optDouble(raw['fatG']),
    fiberG: _optDouble(raw['fiberG']),
  );
  return n.isEmpty ? null : n;
}

Map<String, Object?>? nutritionToJson(IngredientNutrition? n) => n == null
    ? null
    : {
        if (n.calories != null) 'calories': n.calories,
        if (n.proteinG != null) 'proteinG': n.proteinG,
        if (n.carbsG != null) 'carbsG': n.carbsG,
        if (n.fatG != null) 'fatG': n.fatG,
        if (n.fiberG != null) 'fiberG': n.fiberG,
      };

class RecipeSubstituteDto {
  const RecipeSubstituteDto(this.entity);

  factory RecipeSubstituteDto.fromJson(Map<String, dynamic> json,
          {required String fallbackKey}) =>
      RecipeSubstituteDto(RecipeSubstitute(
        key: _optString(json['key']) ??
            _optString(json['ingredientId']) ??
            fallbackKey,
        name: json['name']?.toString() ?? '',
        quantity: _quantity(json['quantity']),
        unit: json['unit']?.toString() ?? '',
        ingredientId: _optString(json['ingredientId']),
        note: _optString(json['note']),
        allergens: _optStringList(json['allergens']),
        nutrition: parseIngredientNutrition(json['nutrition']),
      ));

  final RecipeSubstitute entity;

  RecipeSubstitute toEntity() => entity;
}

Map<String, Object?> recipeSubstituteToJson(RecipeSubstitute s) => {
      'key': s.key,
      if (s.ingredientId != null) 'ingredientId': s.ingredientId,
      'name': s.name,
      'quantity': s.quantity,
      'unit': s.unit,
      if (s.note != null) 'note': s.note,
      if (s.allergens != null) 'allergens': s.allergens,
      if (s.nutrition != null) 'nutrition': nutritionToJson(s.nutrition),
    };

/// "Đậu hũ 200 g", "Đậu hũ: 200 g", "Nước 1,5 lít": a trailing number and a
/// short unit.
final _textAmount = RegExp(
    r'^(.+?)(?:\s*[:\-–]\s*|\s+)(\d+(?:[.,]\d+)?)\s*([^\d:]{0,20})$',
    unicode: true);

class RecipeIngredientDto {
  const RecipeIngredientDto(this.entity);

  factory RecipeIngredientDto.fromJson(Map<String, dynamic> json,
      {String fallbackKey = 'row0'}) {
    final rawSubs = json['substitutes'];
    final subs = <RecipeSubstitute>[];
    if (rawSubs is List<Object?>) {
      final used = <String>{};
      for (final (j, raw) in rawSubs.indexed) {
        if (raw is! Map<String, dynamic>) continue;
        var sub =
            RecipeSubstituteDto.fromJson(raw, fallbackKey: 'sub$j').entity;
        if (!used.add(sub.key)) {
          sub = RecipeSubstitute(
            key: '${sub.key}_$j',
            name: sub.name,
            quantity: sub.quantity,
            unit: sub.unit,
            ingredientId: sub.ingredientId,
            note: sub.note,
            allergens: sub.allergens,
            nutrition: sub.nutrition,
          );
          used.add(sub.key);
        }
        subs.add(sub);
      }
    }
    return RecipeIngredientDto(RecipeIngredient(
      key: _optString(json['key']) ??
          _optString(json['ingredientId']) ??
          fallbackKey,
      ingredientId: _optString(json['ingredientId']),
      name: json['name'] as String? ?? '',
      quantity: _quantity(json['quantity']),
      unit: json['unit'] as String? ?? '',
      role: _optString(json['role']),
      isSignature: json['isSignature'] == true,
      isOptional: json['isOptional'] == true,
      allergens: _optStringList(json['allergens']),
      nutrition: parseIngredientNutrition(json['nutrition']),
      substitutes: subs,
    ));
  }

  /// A plain-text row (`"Đậu hũ"`, `"Đậu hũ 200 g"`), as the current BE
  /// sends them: a trailing amount is parsed, else the row is name-only.
  factory RecipeIngredientDto.fromText(String text, {required String key}) {
    final trimmed = text.trim();
    final m = _textAmount.firstMatch(trimmed);
    if (m != null) {
      final name = m.group(1)!.trim();
      final unit = m.group(3)!.trim();
      if (name.isNotEmpty) {
        return RecipeIngredientDto(RecipeIngredient(
          key: key,
          name: name,
          quantity: _quantity(m.group(2)),
          unit: unit,
        ));
      }
    }
    return RecipeIngredientDto(
        RecipeIngredient(key: key, name: trimmed, isFreeText: true));
  }

  final RecipeIngredient entity;

  RecipeIngredient toEntity() => entity;

  /// Rows of an `ingredients` array (maps or strings), keys made unique.
  static List<RecipeIngredientDto> listFromJson(Object? raw) {
    if (raw is! List<Object?>) return const [];
    final rows = <RecipeIngredientDto>[];
    final used = <String>{};
    for (final (i, item) in raw.indexed) {
      final RecipeIngredientDto dto;
      if (item is Map<String, dynamic>) {
        dto = RecipeIngredientDto.fromJson(item, fallbackKey: 'row$i');
      } else if (item is String && item.trim().isNotEmpty) {
        dto = RecipeIngredientDto.fromText(item, key: 'row$i');
      } else {
        continue;
      }
      var row = dto.entity;
      if (!used.add(row.key)) {
        row = _withKey(row, '${row.key}_$i');
        used.add(row.key);
      }
      rows.add(RecipeIngredientDto(row));
    }
    return rows;
  }

  static RecipeIngredient _withKey(RecipeIngredient r, String key) =>
      RecipeIngredient(
        key: key,
        name: r.name,
        quantity: r.quantity,
        unit: r.unit,
        ingredientId: r.ingredientId,
        role: r.role,
        isSignature: r.isSignature,
        isOptional: r.isOptional,
        allergens: r.allergens,
        nutrition: r.nutrition,
        substitutes: r.substitutes,
        isFreeText: r.isFreeText,
      );
}

/// A row in the wire format (variants are stored this way in mock mode).
Map<String, Object?> recipeIngredientToJson(RecipeIngredient i) => {
      'key': i.key,
      if (i.ingredientId != null) 'ingredientId': i.ingredientId,
      'name': i.name,
      'quantity': i.quantity,
      'unit': i.unit,
      if (i.role != null) 'role': i.role,
      if (i.isSignature) 'isSignature': true,
      if (i.isOptional) 'isOptional': true,
      if (i.allergens != null) 'allergens': i.allergens,
      if (i.nutrition != null) 'nutrition': nutritionToJson(i.nutrition),
      if (i.substitutes.isNotEmpty)
        'substitutes': [
          for (final s in i.substitutes) recipeSubstituteToJson(s)
        ],
    };

RecipeChangeNote? _changeNote(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  return switch (raw['type']) {
    'swap' => RecipeChangeNote.swap(
        from: raw['from']?.toString() ?? '', to: raw['to']?.toString() ?? ''),
    'remove' => RecipeChangeNote.remove(raw['name']?.toString() ?? ''),
    _ => null,
  };
}

Map<String, Object?> recipeChangeNoteToJson(RecipeChangeNote c) =>
    c.type == 'swap'
        ? {'type': 'swap', 'from': c.from, 'to': c.to}
        : {'type': 'remove', 'name': c.name};

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
    this.averageRating,
    this.ratingCount = 0,
    this.basedOnRecipeId,
    this.basedOnName,
    this.customizations = const [],
    this.nutritionEstimated = false,
  });

  factory RecipeDetailDto.fromJson(Map<String, dynamic> json) {
    double? optDouble(String key) =>
        json[key] == null ? null : readDouble(json[key]);
    int? optInt(String key) => json[key] == null ? null : readInt(json[key]);
    final rawSteps = json['instructions'] ?? json['steps'];
    final rawChanges = json['customizations'];
    return RecipeDetailDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      instructions: rawSteps is List<Object?>
          ? rawSteps.map((s) => s.toString()).join('\n')
          : rawSteps?.toString() ?? '',
      caloriesCache: optInt('caloriesCache') ?? optInt('calories'),
      isVegan: json['isVegan'] == true,
      ingredients: RecipeIngredientDto.listFromJson(json['ingredients']),
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
      averageRating: optDouble('averageRating'),
      ratingCount: optInt('ratingCount') ?? 0,
      basedOnRecipeId: _optString(json['basedOnRecipeId']),
      basedOnName: _optString(json['basedOnName']),
      customizations: rawChanges is List<Object?>
          ? rawChanges.map(_changeNote).nonNulls.toList()
          : const [],
      nutritionEstimated: json['nutritionEstimated'] == true,
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
  final double? averageRating;
  final int ratingCount;
  final String? basedOnRecipeId;
  final String? basedOnName;
  final List<RecipeChangeNote> customizations;
  final bool nutritionEstimated;

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
        averageRating: averageRating,
        ratingCount: ratingCount,
        basedOnRecipeId: basedOnRecipeId,
        basedOnName: basedOnName,
        customizations: customizations,
        nutritionEstimated: nutritionEstimated,
      );
}
