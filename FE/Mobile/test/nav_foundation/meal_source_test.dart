// test/nav_foundation/meal_source_test.dart
// WP0: MealSource.recipe ("Từ công thức") for dishes added from a recipe
// page, on the wire and as a slot badge.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_slot_card.dart';

void main() {
  setUp(MockMealPlannerRepository.reset);

  group('MealSource.recipe', () {
    test('reads and writes "recipe"; unknown values stay AI', () {
      expect(MealSource.fromApi('recipe'), MealSource.recipe);
      expect(MealSource.recipe.apiValue, 'recipe');
      expect(MealSource.recipe.label, 'Từ công thức');
      expect(MealSource.fromApi('user_recipe'), MealSource.userRecipe);
      expect(MealSource.fromApi('something_else'), MealSource.ai);
      expect(MealSource.fromApi(null), MealSource.ai);

      final request = SwapMealRequestDto(
          date: DateTime(2026, 10, 30),
          slot: MealSlot.dinner,
          recipeId: 'l5',
          source: MealSource.recipe);
      expect(request.toJson()['source'], 'recipe');

      final dto = RecipeDto.fromJson(
              {'id': 'l5', 'name': 'Bún riêu chay', 'calories': 580})
          .withSource(MealSource.recipe.apiValue);
      expect(RecipeDto.fromJson(dto.toJson()).toEntity().source,
          MealSource.recipe);
    });

    test('a slot placed with it keeps it (mock PATCH)', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      final plan = (await repo.getCurrentMealPlan())!;
      final day = await repo.swapMeal(
        planId: plan.id,
        request: SwapMealRequestDto(
            date: plan.days[1].date,
            slot: MealSlot.dinner,
            recipeId: 'l5',
            source: MealSource.recipe),
      );
      final meal = day.toEntity().meals[MealSlot.dinner]!;
      expect(meal.id, 'l5');
      expect(meal.source, MealSource.recipe);
      expect(meal.hasDetail, isTrue, reason: 'opens the recipe page');
    });
  });

  for (final (name, buildTheme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('badge "Từ công thức" ($name)', (tester) async {
      final theme = buildTheme();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: MealSourceBadge(
              recipe: Recipe(
                id: 'l5',
                name: 'Bún riêu chay',
                nutrition: Nutrition(calories: 580),
                source: MealSource.recipe,
              ),
            ),
          ),
        ),
      ));
      expect(find.text('Từ công thức'), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_menu_outlined), findsOneWidget);
      final box = tester.widget<Container>(find
          .ancestor(
              of: find.text('Từ công thức'), matching: find.byType(Container))
          .first);
      expect((box.decoration! as BoxDecoration).color,
          theme.colorScheme.surfaceContainer);
      expect(tester.takeException(), isNull);
    });
  }
}
