// lib/features/recipe/data/recipe_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'mock_recipe_repository.dart';
import 'models/recipe_detail_model.dart';

abstract interface class RecipeApiService {
  /// 404 when the recipe doesn't exist (or was removed).
  Future<RecipeDetailDto> getRecipe(String id);
}

class RemoteRecipeApiService implements RecipeApiService {
  RemoteRecipeApiService(this._dio);

  final Dio _dio;

  @override
  Future<RecipeDetailDto> getRecipe(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.recipe(id));
        return RecipeDetailDto.fromJson(res.data!);
      });
}

final recipeApiProvider = Provider<RecipeApiService>((ref) {
  if (Env.useMockData) return MockRecipeRepository();
  return RemoteRecipeApiService(ref.watch(dioProvider));
});
