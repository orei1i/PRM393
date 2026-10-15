// lib/features/meal_planner/data/models/pantry_model.dart
//
// The member's fridge, mapped to `user_ingredients`: names only. No quantity
// (a scan only says what is there) and no freshness; a `freshness` field
// from older servers is ignored. Only vegan foods are kept: the scanner
// saves items with `isVegan: true` (`ingredients.is_vegan`) and manual adds
// that aren't vegan are refused.
//
// GET /users/me/ingredients
// [ { "id": 31, "ingredient": "Đậu hũ", "scannedAt": "2026-10-15T01:20:00Z" },
//   { "id": 32, "ingredient": "Gạo lứt", "scannedAt": null } ]
// `scannedAt` set → saved from a scan ("Quét"); null → typed in ("Tự thêm").
//
// POST /users/me/ingredients   → the whole list after the merge
// { "items": [ { "ingredient": "Cà chua", "scannedAt": "…" } ] }
// Same ingredient name (case/accents ignored) updates the existing row.
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/meal_plan.dart';

class PantryItemDto {
  const PantryItemDto({
    required this.id,
    required this.ingredient,
    this.scannedAt,
  });

  factory PantryItemDto.fromJson(Map<String, dynamic> json) => PantryItemDto(
        id: json['id']?.toString() ?? '',
        // `name` when the server joins the ingredients table.
        ingredient:
            json['ingredient'] as String? ?? json['name'] as String? ?? '',
        scannedAt: readDateTime(json['scannedAt']),
      );

  final String id;
  final String ingredient;
  final DateTime? scannedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ingredient': ingredient,
        'scannedAt': scannedAt?.toUtc().toIso8601String(),
      };

  PantryItem toEntity() => PantryItem(
        id: id,
        ingredient: ingredient,
        scannedAt: scannedAt,
      );
}

class AddPantryItemDto {
  const AddPantryItemDto({required this.ingredient, this.scannedAt});

  final String ingredient;
  final DateTime? scannedAt;

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        if (scannedAt != null)
          'scannedAt': scannedAt!.toUtc().toIso8601String(),
      };
}
