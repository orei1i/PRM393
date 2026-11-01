// lib/features/meal_planner/presentation/controllers/my_recipes_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/meal_planner_api_service.dart';
import '../../domain/entities/meal_plan.dart';

/// "Công thức của tôi" in Tôi: recipes the member wrote or saved from a recipe
/// page. Invalidate it after a change.
final myRecipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) async {
  final rows = await ref.watch(mealPlannerApiProvider).getMyRecipes();
  return [for (final r in rows) r.toEntity()];
});
