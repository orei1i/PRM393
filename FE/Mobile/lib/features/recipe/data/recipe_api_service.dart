// lib/features/recipe/data/recipe_api_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/backend_ids.dart';
import 'mock_recipe_repository.dart';
import 'models/recipe_detail_model.dart';
import 'recipe_catalog.dart';

abstract interface class RecipeApiService {
  /// 404 when the recipe doesn't exist (or was removed).
  Future<RecipeDetailDto> getRecipe(String id);
}

/// The BE has no GET /recipes/{id}, so the id decides where a recipe comes
/// from: a mock id (`l5`, `cs_…`, `menu_1`) from the mock store, a 24-hex id
/// from the catalogue then the plan, a 32-hex id (a typed dish) from the plan.
/// A mock id the mock store doesn't know (`rc_…`, a dish of a sample chef plan
/// applied to the real planner) still gets a page from the plan.
class RemoteRecipeApiService implements RecipeApiService {
  RemoteRecipeApiService({
    required RecipeCatalog Function() catalog,
    required PlanItemSnapshots Function() snapshots,
    RecipeApiService? mock,
  })  : _catalog = catalog,
        _snapshots = snapshots,
        _mock = mock ?? MockRecipeRepository();

  final RecipeCatalog Function() _catalog;
  final PlanItemSnapshots Function() _snapshots;
  final RecipeApiService _mock;

  @override
  Future<RecipeDetailDto> getRecipe(String id) async {
    final fromCatalog = isBackendId(id);
    if (!fromCatalog && !isBackendPlanItemId(id)) {
      try {
        return await _mock.getRecipe(id);
      } on ApiException catch (e) {
        final snapshot = e.statusCode == 404 ? _snapshots().find(id) : null;
        if (snapshot != null) return snapshot;
        rethrow;
      }
    }
    final recipe = (fromCatalog ? await _catalog().find(id) : null) ??
        _snapshots().find(id);
    if (recipe != null) return recipe;
    throw const ApiException(
        message: 'Không tìm thấy công thức.',
        statusCode: 404,
        code: 'not_found');
  }
}

/// Doesn't watch the session, so signing in on a recipe page keeps the page.
final recipeApiProvider = Provider<RecipeApiService>((ref) {
  if (BackendModules.isMock(BackendModule.recipes)) {
    return MockRecipeRepository();
  }
  return RemoteRecipeApiService(
    catalog: () => ref.read(recipeCatalogProvider),
    snapshots: () => ref.read(planItemSnapshotsProvider),
  );
});
