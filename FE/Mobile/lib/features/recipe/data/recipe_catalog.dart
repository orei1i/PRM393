// lib/features/recipe/data/recipe_catalog.dart
//
// GET /recipes/{id} (members only; 404 for another member's private recipe)
// { "id": "6ae595c7…", "name": "…", "imageUrl": null, "calories": 520, "proteinG": 26,
//   "carbsG": 75, "fatG": 14, "fiberG": 10, "allergens": ["soy"], "dietTags": ["balanced"],
//   "prepMinutes": 25, "ingredients": ["Gạo lứt", "Đậu hũ"],
//   "instructions": ["Sơ chế nguyên liệu sạch sẽ."], "seasonalSwap": null }
//
// GET /recipes now lists the catalogue, but it knows nothing of the member's
// allergies, so this still reads
// swap-suggestions on a plan of the member (404 for any other id): a slot no
// recipe is tagged with, on a day outside the plan, and a large limit return
// every recipe that is safe for the member's allergies.
// GET /meal-plans/{id}/swap-suggestions?date=2000-01-01&slot=snack_am&limit=200
//
// That relies on a BE quirk (an unmatched slot falls back to all), which
// `integration_test_be` checks. A member with no plan this week gets what
// POST /meal-plans/from-ingredients suggests instead: at most 10 recipes, best
// match with the fridge first. Nothing here creates a plan.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/backend_ids.dart';
import '../../../core/utils/json_helpers.dart';
import '../../meal_planner/data/meal_planner_api_service.dart';
import '../../meal_planner/data/models/meal_plan_model.dart';
import '../../meal_planner/domain/allergy_match.dart';
import '../../meal_planner/domain/entities/meal_slot.dart';
import 'backend_recipe_items.dart';
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
    String? Function()? planId,
  }) : _planId = planId;

  /// Tagged on no recipe, so the BE falls back to all of them.
  static const _unmatchedSlot = 'snack_am';

  /// In no plan: the dish in a slot of that day would be left out.
  static const _dayOutsideAnyPlan = '2000-01-01';

  /// If that fallback is ever removed, the slots recipes are tagged with.
  static final _taggedSlots = [
    MealSlot.breakfast,
    MealSlot.lunch,
    MealSlot.dinner,
    MealSlot.snackPm,
  ].map((s) => s.apiValue);

  final Dio _dio;
  final String? userId;
  final String? Function()? _planId;

  Future<Map<String, RecipeDetailDto>>? _recipes;
  Future<List<Map<String, dynamic>>>? _mine;

  /// [_recipes] came from the fridge, because there was no plan to ask with.
  bool _fromFridgeOnly = false;

  /// Reads the catalogue again next time (a failed load is never kept).
  void invalidate() {
    _recipes = null;
    _mine = null;
  }

  Future<List<RecipeDetailDto>> load() async =>
      (await _load()).values.toList(growable: false);

  /// One recipe, whether or not the catalogue would list it (it leaves out what
  /// the member is allergic to; the page flags that instead). `null` when it
  /// doesn't exist or is another member's.
  Future<RecipeDetailDto?> find(String id) => guardApi(() async {
        try {
          final res =
              await _dio.get<Map<String, dynamic>>(ApiEndpoints.recipe(id));
          // A guest reads the seed recipes too, and has no recipes of their own.
          final isMine = userId != null &&
              (await _myRecipes()).any((row) => _id(row) == id);
          return isMine ? _myRecipe(res.data!) : recipeFromBackend(res.data!);
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return null;
          rethrow;
        }
      });

  /// Recipes with [name] among their ingredient rows.
  Future<List<RecipeDetailDto>> usingIngredient(String name,
          {int limit = 6}) async =>
      (await _load())
          .values
          .where((r) => r.ingredients.any((i) => sameFood(i.entity.name, name)))
          .take(limit)
          .toList();

  Future<Map<String, RecipeDetailDto>> _load() {
    if (_fromFridgeOnly && _planId?.call() != null) invalidate();
    final loading = _recipes ??= _fetch();
    // Not `catchError`: the caller still gets the failure.
    loading.then<void>((_) {}, onError: (Object _) {
      if (identical(_recipes, loading)) _recipes = null;
    });
    return loading;
  }

  Future<Map<String, RecipeDetailDto>> _fetch() => guardApi(() async {
        final planId = _planId?.call() ?? await _currentPlanId();
        _fromFridgeOnly = planId == null;
        final rows =
            planId == null ? await _fromFridge() : await _allRecipes(planId);
        final mine = await _myRecipes();
        return {
          for (final row in rows) _id(row): recipeFromBackend(row),
          for (final row in mine) _id(row): _myRecipe(row),
        };
      });

  /// `null` when the member has no plan this week.
  Future<String?> _currentPlanId() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(ApiEndpoints.currentMealPlan);
      return res.data?['id']?.toString();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _allRecipes(String planId) async {
    final rows = await _suggestions(planId, _unmatchedSlot);
    if (rows.isNotEmpty) return rows;
    return [
      for (final slot in _taggedSlots) ...await _suggestions(planId, slot),
    ];
  }

  Future<List<Map<String, dynamic>>> _suggestions(
      String planId, String slot) async {
    final res = await _dio.get<List<dynamic>>(
      ApiEndpoints.swapSuggestions(planId),
      queryParameters: {
        'date': _dayOutsideAnyPlan,
        'slot': slot,
        'limit': 200,
      },
    );
    return _rows(res.data);
  }

  Future<List<Map<String, dynamic>>> _fromFridge() async {
    final res =
        await _dio.post<List<dynamic>>(ApiEndpoints.mealPlanFromIngredients);
    return _rows(res.data);
  }

  /// A failed read is not kept, and only means a recipe isn't marked as theirs.
  Future<List<Map<String, dynamic>>> _myRecipes() {
    final loading = _mine ??= _dio
        .get<List<dynamic>>(ApiEndpoints.myRecipes)
        .then((res) => _rows(res.data));
    loading.then<void>((_) {}, onError: (Object _) {
      if (identical(_mine, loading)) _mine = null;
    });
    return loading;
  }

  /// Never the catalogue's table: a member may name a recipe like a seed one.
  RecipeDetailDto _myRecipe(Map<String, dynamic> row) =>
      RecipeDetailDto.fromJson(withSavedVariantItems({
        ...row,
        'isVegan': true,
        if (userId != null) 'createdBy': userId,
      }));

  static List<Map<String, dynamic>> _rows(List<dynamic>? data) =>
      (data ?? const []).whereType<Map<String, dynamic>>().toList();

  static String _id(Map<String, dynamic> row) => row['id']?.toString() ?? '';
}

/// A catalogue `RecipeResponse` as a detail, with the structured rows of
/// `backend_recipe_items.dart` when it knows the name. Everything the BE stores
/// is vegan and it doesn't say so; text rows and step arrays are handled by the
/// parser.
RecipeDetailDto recipeFromBackend(Map<String, dynamic> json) =>
    RecipeDetailDto.fromJson(
        {...withBackendRecipeItems(json), 'isVegan': true});

/// The dishes of the plans the member has loaded, by the id that opens them.
/// A dish whose recipe can't be read and a typed dish still get a page from what
/// the plan knows about them.
class PlanItemSnapshots {
  final _items = <String, Map<String, dynamic>>{};

  /// The latest plan seen: what swap-suggestions is asked with.
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
    planId: () => snapshots.planId,
  );
});

final planItemSnapshotsProvider = Provider<PlanItemSnapshots>((ref) {
  ref.watch(plannerUserIdProvider);
  return PlanItemSnapshots();
});
