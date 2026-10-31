// lib/features/recipe/data/recipe_catalog.dart
//
// The real BE has no GET /recipes/{id} and no recipe list. Its only way to read
// the catalogue is swap-suggestions: a slot no recipe is tagged with (and a
// large limit) returns every recipe that is safe for the member's allergies.
// GET /meal-plans/{id}/swap-suggestions?date=2026-10-31&slot=snack_am&limit=200
// [ { "id": "6ae595c7…", "name": "…", "imageUrl": null, "calories": 520, "proteinG": 26,
//     "carbsG": 75, "fatG": 14, "fiberG": 10, "allergens": ["soy"], "dietTags": ["balanced"],
//     "prepMinutes": 25, "ingredients": ["Gạo lứt", "Đậu hũ"],
//     "instructions": ["Sơ chế nguyên liệu sạch sẽ."], "seasonalSwap": null } ]
//
// That relies on two BE quirks (the plan id isn't checked, an unmatched slot
// falls back to all); `integration_test_be` pins them. When BE ships
// GET /recipes/{id}, `RemoteRecipeApiService` should try it first.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/backend_ids.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json_helpers.dart';
import '../../meal_planner/data/meal_planner_api_service.dart';
import '../../meal_planner/data/models/meal_plan_model.dart';
import '../../meal_planner/domain/allergy_match.dart';
import '../../meal_planner/domain/entities/meal_slot.dart';
import 'models/recipe_detail_model.dart';

/// Whether two food names refer to the same thing, either way round ("Đậu
/// hũ" and "Đậu hũ non"), by whole words and ignoring accents.
bool sameFood(String a, String b) =>
    mentionsAllergy(a, [b]) || mentionsAllergy(b, [a]);

/// The recipes the member can read, kept for the session and dropped on an
/// account change or when their allergies change (see [invalidate]).
class RecipeCatalog {
  RecipeCatalog(
    this._dio, {
    this.userId,
    DateTime Function() clock = DateTime.now,
    String? Function()? planId,
  })  : _clock = clock,
        _planId = planId;

  /// Accepted by the BE for now: it doesn't check the plan id.
  static const _noPlanId = '000000000000000000000000';

  /// Tagged on no recipe, so the BE falls back to all of them.
  static const _unmatchedSlot = 'snack_am';

  /// If that fallback is ever removed, the slots recipes are tagged with.
  static final _taggedSlots = [
    MealSlot.breakfast,
    MealSlot.lunch,
    MealSlot.dinner,
    MealSlot.snackPm,
  ].map((s) => s.apiValue);

  final Dio _dio;
  final String? userId;
  final DateTime Function() _clock;
  final String? Function()? _planId;

  Future<Map<String, RecipeDetailDto>>? _recipes;

  /// Reads the catalogue again next time (a failed load is never kept).
  void invalidate() => _recipes = null;

  Future<List<RecipeDetailDto>> load() async =>
      (await _load()).values.toList(growable: false);

  /// `null` when the recipe isn't readable: unknown, or not safe for the
  /// member's allergies (the BE leaves those out).
  Future<RecipeDetailDto?> find(String id) async => (await _load())[id];

  /// Recipes with [name] among their ingredient rows.
  Future<List<RecipeDetailDto>> usingIngredient(String name,
          {int limit = 6}) async =>
      (await _load())
          .values
          .where((r) => r.ingredients.any((i) => sameFood(i.entity.name, name)))
          .take(limit)
          .toList();

  Future<Map<String, RecipeDetailDto>> _load() {
    final loading = _recipes ??= _fetch();
    // Not `catchError`: the caller still gets the failure.
    loading.then<void>((_) {}, onError: (Object _) {
      if (identical(_recipes, loading)) _recipes = null;
    });
    return loading;
  }

  Future<Map<String, RecipeDetailDto>> _fetch() => guardApi(() async {
        var rows = await _suggestions(_unmatchedSlot);
        if (rows.isEmpty) {
          rows = [for (final slot in _taggedSlots) ...await _suggestions(slot)];
        }
        final mine = await _dio.get<List<dynamic>>(ApiEndpoints.myRecipes);
        return {
          for (final row in rows) _id(row): recipeFromBackend(row),
          for (final row
              in (mine.data ?? const []).whereType<Map<String, dynamic>>())
            _id(row): recipeFromBackend(
                {...row, if (userId != null) 'createdBy': userId}),
        };
      });

  Future<List<Map<String, dynamic>>> _suggestions(String slot) async {
    final res = await _dio.get<List<dynamic>>(
      ApiEndpoints.swapSuggestions(_planId?.call() ?? _noPlanId),
      queryParameters: {
        'date': toApiDate(_clock()),
        'slot': slot,
        'limit': 200,
      },
    );
    return (res.data ?? const []).whereType<Map<String, dynamic>>().toList();
  }

  static String _id(Map<String, dynamic> row) => row['id']?.toString() ?? '';
}

/// A BE `RecipeResponse` as a detail. Everything the BE stores is vegan and it
/// doesn't say so; text rows and step arrays are handled by the parser.
RecipeDetailDto recipeFromBackend(Map<String, dynamic> json) =>
    RecipeDetailDto.fromJson({...json, 'isVegan': true});

/// The dishes of the plans the member has loaded, by the id that opens them.
/// A recipe missing from [RecipeCatalog] and a typed dish still get a page
/// from what the plan knows about them.
class PlanItemSnapshots {
  final _items = <String, Map<String, dynamic>>{};

  /// The latest plan seen: what swap-suggestions gets once it checks the id.
  String? planId;

  /// A `MealPlanResponse` (with `id` and `days`).
  void registerPlan(Map<String, dynamic> plan) {
    planId = plan['id']?.toString() ?? planId;
    final days = plan['days'];
    if (days is List<Object?>) {
      days.whereType<Map<String, dynamic>>().forEach(registerDay);
    }
  }

  /// A `MealPlanDayResponse` (with `meals`).
  void registerDay(Map<String, dynamic> day) {
    for (final meal in readMap(day['meals']).values) {
      if (meal is Map<String, dynamic>) {
        _items[RecipeDto.effectiveMealId(meal)] = meal;
      }
    }
  }

  /// The dish as a page with no ingredients or steps; `null` when unknown.
  RecipeDetailDto? find(String id) {
    final meal = _items[id];
    if (meal == null) return null;
    return RecipeDetailDto.fromJson({
      ...meal,
      'id': id,
      // A dish typed in by hand can be anything; the BE's recipes and a chef
      // plan's dishes are vegan.
      'isVegan': isBackendId(id) || meal['source'] == 'chef',
      'isSnapshot': true,
    });
  }
}

/// New per account; the recipe screen reads it on demand, so that signing in
/// on a recipe page doesn't reload it.
final recipeCatalogProvider = Provider<RecipeCatalog>((ref) {
  final snapshots = ref.watch(planItemSnapshotsProvider);
  return RecipeCatalog(
    ref.watch(dioProvider),
    userId: ref.watch(plannerUserIdProvider),
    clock: ref.watch(plannerClockProvider),
    planId: () => snapshots.planId,
  );
});

final planItemSnapshotsProvider = Provider<PlanItemSnapshots>((ref) {
  ref.watch(plannerUserIdProvider);
  return PlanItemSnapshots();
});
