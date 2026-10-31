// lib/features/meal_planner/data/models/pantry_model.dart
//
// The member's fridge, mapped to `user_ingredients`: names only. No quantity
// (a scan only says what is there) and no freshness; a `freshness` field
// from older servers is ignored. Only vegan foods are kept: the scanner
// saves items with `isVegan: true` (`ingredients.is_vegan`) and manual adds
// that aren't vegan are refused.
//
// GET /users/me/ingredients
// [ { "id": 31, "ingredient": "Đậu hũ", "scannedAt": "2026-10-15T01:20:00Z",
//     "ingredientId": "ing_dau_hu", "category": "plant_protein", "caloriesPer100g": 76 },
//   { "id": 32, "ingredient": "Gạo lứt", "scannedAt": null } ]
// `scannedAt` set → saved from a scan ("Quét"); null → typed in ("Tự thêm").
// `ingredientId` / `category` / `caloriesPer100g` come from the nutrition DB
// (`ingredients` ⋈ `ingredient_nutrition`) when the name matched a row.
//
// POST /users/me/ingredients   → the whole list after the merge
// { "items": [ { "ingredient": "Cà chua", "scannedAt": "…" } ] }
// Same ingredient name (case/accents ignored) updates the existing row.
//
// The real BE adds to a row (all optional here, the mock has none of them):
// { …, "quantity": 200, "unit": "g", "expiryDate": null, "isVegan": true,
//   "allergyWarning": null }
// Its POST returns only the rows it touched, so the service GETs the list.
// PUT /users/me/ingredients/{id}
// { "quantity": 300, "unit": "g", "expiryDate": "2026-11-05" }
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/meal_plan.dart';

class PantryItemDto {
  const PantryItemDto({
    required this.id,
    required this.ingredient,
    this.scannedAt,
    this.ingredientId,
    this.category,
    this.caloriesPer100g,
    this.quantity,
    this.unit,
    this.expiryDate,
    this.isVegan,
    this.allergyWarning,
  });

  factory PantryItemDto.fromJson(Map<String, dynamic> json) => PantryItemDto(
        id: json['id']?.toString() ?? '',
        // `name` when the server joins the ingredients table.
        ingredient:
            json['ingredient'] as String? ?? json['name'] as String? ?? '',
        scannedAt: readDateTime(json['scannedAt']),
        ingredientId: json['ingredientId']?.toString(),
        category: json['category'] as String?,
        caloriesPer100g: json['caloriesPer100g'] == null
            ? null
            : readInt(json['caloriesPer100g']),
        quantity:
            json['quantity'] == null ? null : readDouble(json['quantity']),
        unit: json['unit'] as String?,
        expiryDate: readDateTime(json['expiryDate']),
        isVegan: json['isVegan'] as bool?,
        allergyWarning: json['allergyWarning'] as String?,
      );

  final String id;
  final String ingredient;
  final DateTime? scannedAt;
  final String? ingredientId;
  final String? category;
  final int? caloriesPer100g;
  final double? quantity;
  final String? unit;
  final DateTime? expiryDate;
  final bool? isVegan;
  final String? allergyWarning;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ingredient': ingredient,
        'scannedAt': scannedAt?.toUtc().toIso8601String(),
        if (ingredientId != null) 'ingredientId': ingredientId,
        if (category != null) 'category': category,
        if (caloriesPer100g != null) 'caloriesPer100g': caloriesPer100g,
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (expiryDate != null)
          'expiryDate': expiryDate!.toUtc().toIso8601String(),
        if (isVegan != null) 'isVegan': isVegan,
        if (allergyWarning != null) 'allergyWarning': allergyWarning,
      };

  PantryItem toEntity() => PantryItem(
        id: id,
        ingredient: ingredient,
        scannedAt: scannedAt,
        ingredientId: ingredientId,
        category: category,
        caloriesPer100g: caloriesPer100g,
        quantity: quantity,
        unit: unit,
        expiryDate: expiryDate,
        allergyWarning: allergyWarning,
      );
}

class AddPantryItemDto {
  const AddPantryItemDto({
    required this.ingredient,
    this.scannedAt,
    this.quantity,
    this.unit,
    this.expiryDate,
  });

  final String ingredient;
  final DateTime? scannedAt;

  /// Kept by "Hoàn tác" on the real BE.
  final double? quantity;
  final String? unit;
  final DateTime? expiryDate;

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        if (scannedAt != null)
          'scannedAt': scannedAt!.toUtc().toIso8601String(),
        if (quantity != null) 'quantity': quantity,
        if (unit != null) 'unit': unit,
        if (expiryDate != null) 'expiryDate': toApiDate(expiryDate!),
      };
}

/// "Sửa số lượng & hạn dùng". The BE keeps the old date when none is sent, so
/// a date can be changed but not removed.
class UpdatePantryItemDto {
  const UpdatePantryItemDto(
      {required this.quantity, required this.unit, this.expiryDate});

  final double quantity;
  final String unit;
  final DateTime? expiryDate;

  Map<String, dynamic> toJson() => {
        'quantity': quantity,
        'unit': unit,
        if (expiryDate != null) 'expiryDate': toApiDate(expiryDate!),
      };
}
