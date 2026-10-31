// lib/features/recipe/data/models/recipe_variant_model.dart
//
// POST /recipes/{id}/variants (Member, Chef) — "Lưu thành công thức của tôi".
// { "name": "Bún riêu chay (tuỳ chỉnh)",
//   "swaps": [ { "ingredientKey": "rieu", "substituteKey": "rieu_nam" } ],
//   "removed": ["rau_muong"] }
// 201 → the saved private recipe in the GET /recipes/{id} format, with
// `basedOnRecipeId`, `basedOnName`, `customizations`, recomputed
// `caloriesCache` / macros / `allergens` and `nutritionEstimated`.
// 400 `signature_required` | `invalid_substitute` | name < 2 or > 80 chars;
// 401 guest; 404 recipe; 503.
import '../../domain/recipe_customization.dart';

/// Bounds of a saved recipe's name.
const variantNameMin = 2;
const variantNameMax = 80;

/// The name check shared by the save dialog and the mock server; `null`
/// when valid.
String? validateVariantName(String name) {
  final n = name.trim().length;
  if (n < variantNameMin) return 'Nhập tên công thức (ít nhất 2 ký tự).';
  if (n > variantNameMax) return 'Tên tối đa 80 ký tự.';
  return null;
}

/// "Bún riêu chay (tuỳ chỉnh)".
String defaultVariantName(String recipeName) => '$recipeName (tuỳ chỉnh)';

class CreateVariantRequestDto {
  const CreateVariantRequestDto({
    required this.name,
    this.swaps = const {},
    this.removed = const [],
  });

  factory CreateVariantRequestDto.fromChoices(
          String name, RecipeCustomization choices) =>
      CreateVariantRequestDto(
        name: name.trim(),
        swaps: choices.swaps,
        removed: choices.removed.toList(),
      );

  factory CreateVariantRequestDto.fromJson(Map<String, dynamic> json) {
    final swaps = <String, String>{};
    final rawSwaps = json['swaps'];
    if (rawSwaps is List<Object?>) {
      for (final s in rawSwaps.whereType<Map<String, dynamic>>()) {
        swaps['${s['ingredientKey']}'] = '${s['substituteKey']}';
      }
    }
    final rawRemoved = json['removed'];
    return CreateVariantRequestDto(
      name: json['name']?.toString() ?? '',
      swaps: swaps,
      removed: rawRemoved is List<Object?>
          ? rawRemoved.map((e) => '$e').toList()
          : const [],
    );
  }

  final String name;

  /// Row key → substitute key.
  final Map<String, String> swaps;
  final List<String> removed;

  RecipeCustomization get choices =>
      RecipeCustomization(swaps: swaps, removed: removed.toSet());

  Map<String, dynamic> toJson() => {
        'name': name,
        'swaps': [
          for (final MapEntry(:key, :value) in swaps.entries)
            {'ingredientKey': key, 'substituteKey': value},
        ],
        'removed': removed,
      };
}
