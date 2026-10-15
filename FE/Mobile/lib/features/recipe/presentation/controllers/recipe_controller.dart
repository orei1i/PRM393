// lib/features/recipe/presentation/controllers/recipe_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/recipe_api_service.dart';
import '../../domain/entities/recipe_detail.dart';

/// One recipe by id; dropped when its screen closes.
final recipeDetailProvider =
    FutureProvider.autoDispose.family<RecipeDetail, String>((ref, id) async {
  return (await ref.watch(recipeApiProvider).getRecipe(id)).toEntity();
});
