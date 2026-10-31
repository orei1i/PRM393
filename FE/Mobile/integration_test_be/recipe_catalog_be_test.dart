// integration_test_be/recipe_catalog_be_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';

import 'be_harness.dart';

const _profile = UpdateHealthProfileRequestDto(
  heightCm: 170,
  weightKg: 66,
  goal: HealthGoal.maintain,
  allergies: [],
  dietaryRestrictions: [],
  gender: Gender.female,
  birthYear: 1997,
  activityLevel: ActivityLevel.light,
  mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
);

Future<void> main() async {
  final be = await BeHarness.start();

  group('recipe catalog', skip: be.skipReason, () {
    late BeUser me;

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Catalog');
    });

    beTest('at least 29 recipes, each one with rows to show', () async {
      final recipes = await RecipeCatalog(me.dio, userId: me.id).load();
      expect(recipes.length, greaterThanOrEqualTo(29));
      for (final r in recipes) {
        expect(r.id, hasLength(24), reason: r.name);
        expect(r.isVegan, isTrue, reason: r.name);
        expect(r.ingredients, isNotEmpty, reason: r.name);
      }
    });

    beTest('it finds every recipe of a generated plan', () async {
      final c = await me.container();
      addTearDown(c.dispose);
      await c.read(mealPlannerApiProvider).updateHealthProfile(_profile);
      await c.read(mealPlanControllerProvider.future);
      final notifier = c.read(mealPlanControllerProvider.notifier);
      expect(await notifier.generatePlan(), isTrue);
      final plan = c.read(mealPlanControllerProvider).requireValue.plan!;

      final catalog = c.read(recipeCatalogProvider);
      for (final day in plan.days) {
        for (final dish in day.meals.values) {
          expect(await catalog.find(dish.id), isNotNull, reason: dish.name);
        }
      }
    });

    beTest('a peanut allergy leaves peanut recipes out of the catalogue',
        () async {
      final allergic = await be.newUser(name: 'FE IT Catalog Allergy');
      await RemoteMealPlannerApiService(allergic.dio).updateHealthProfile(
        const UpdateHealthProfileRequestDto(
          heightCm: 170,
          weightKg: 66,
          goal: HealthGoal.maintain,
          allergies: ['peanut'],
          dietaryRestrictions: [],
          gender: Gender.female,
          birthYear: 1997,
          activityLevel: ActivityLevel.light,
          mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
        ),
      );
      final recipes =
          await RecipeCatalog(allergic.dio, userId: allergic.id).load();
      expect(recipes, isNotEmpty);
      for (final r in recipes) {
        expect(r.allergens, isNot(contains('peanut')), reason: r.name);
      }
    });

    beTest('page routing: 24-hex, unknown, and a mock id', () async {
      final catalog = RecipeCatalog(me.dio, userId: me.id);
      final snapshots = PlanItemSnapshots();
      final pages = RemoteRecipeApiService(
        catalog: () => catalog,
        snapshots: () => snapshots,
      );

      final known = (await catalog.load()).first;
      final page = await pages.getRecipe(known.id);
      expect(page.name, known.name);
      expect(page.instructions, isNotEmpty);

      await expectApiError(
        pages.getRecipe('000000000000000000000000'),
        status: 404,
        code: 'not_found',
      );
      await expectApiError(
        pages.getRecipe('00000000000000000000000000000000'),
        status: 404,
        code: 'not_found',
      );
      expect((await pages.getRecipe('l5')).name, isNotEmpty);
    });

    beTest('a guest reaches mock recipes; a real id reads as an error',
        () async {
      final c = await guestContainer();
      addTearDown(c.dispose);
      final pages = c.read(recipeApiProvider);
      expect((await pages.getRecipe('l5')).name, isNotEmpty);
      await expectApiError(
        pages.getRecipe('000000000000000000000000'),
        status: 401,
      );
    });
  });
}
