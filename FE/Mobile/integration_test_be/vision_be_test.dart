// integration_test_be/vision_be_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';
import 'package:veganlife_mobile/features/scanner/domain/entities/detected_ingredient.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('vision', skip: be.skipReason, () {
    late ProviderContainer c;
    late ScannerApiService scanner;

    DetectedIngredient food(String name) =>
        DetectedIngredient(id: name, name: name, confidence: 1, isVegan: true);

    setUpAll(() async {
      final me = await be.newUser(name: 'FE IT Vision');
      c = await me.container();
      scanner = c.read(scannerApiProvider);
    });

    tearDownAll(() => c.dispose());

    beTest('scan through the host-root route (B1 workaround)', () async {
      final result = await scanner.scanImage(pngBytes());
      expect(result.items, isNotEmpty);
      for (final item in result.items) {
        expect(item.label, isNotEmpty);
        expect(item.bbox, isNotNull, reason: item.label);
      }
    });

    beTest('no image is refused before any request', () async {
      await expectApiError(scanner.scanImage(Uint8List(0)),
          status: 400, code: 'no_image');
    });

    beTest('suggestions use the ingredients and avoid the allergens', () async {
      final menu = await scanner.generateMenu(GenerateMenuRequestDto(
        ingredients: [food('Đậu hũ'), food('Cà chua'), food('Đậu phộng')],
        excludeAllergens: const ['peanut', 'lá lốt'],
      ));
      expect(menu, isNotEmpty);
      expect(menu.length, lessThanOrEqualTo(5));
      for (final dish in menu) {
        expect(dish.usedIngredients, isNotEmpty, reason: dish.name);
        expect(dish.allergens, isNot(contains('peanut')), reason: dish.name);
      }
    });

    beTest('nothing in the catalogue uses it: an empty list', () async {
      final menu = await scanner.generateMenu(GenerateMenuRequestDto(
        ingredients: [food('Không có nguyên liệu này')],
        excludeAllergens: const [],
      ));
      expect(menu, isEmpty);
    });

    beTest('suggestions leave the plan alone; adding one brings its macros',
        () async {
      final planner = c.read(mealPlannerApiProvider);
      await planner.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 170,
        weightKg: 66,
        goal: HealthGoal.maintain,
        allergies: ['peanut'],
        dietaryRestrictions: [],
        gender: Gender.female,
        birthYear: 1997,
        activityLevel: ActivityLevel.light,
        mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      ));
      final notifier = c.read(mealPlanControllerProvider.notifier);
      await c.read(mealPlanControllerProvider.future);
      expect(await notifier.generatePlan(), isTrue);
      // The profile changed the allergies: read the catalogue again.
      c.read(recipeCatalogProvider).invalidate();

      final before = jsonEncode((await planner.getCurrentMealPlan())!.toJson());
      final menu = await scanner.generateMenu(GenerateMenuRequestDto(
        ingredients: [food('Đậu hũ'), food('Cà chua')],
        excludeAllergens: const ['peanut'],
      ));
      expect(menu, isNotEmpty);
      final after = jsonEncode((await planner.getCurrentMealPlan())!.toJson());
      expect(after, before);

      final added = await notifier.addMealToToday(
        slot: MealSlot.dinner,
        name: menu.first.name,
        calories: menu.first.calories,
        sourceId: menu.first.id,
      );
      expect(added.recipe.id, menu.first.id);
      expect(added.recipe.nutrition.proteinG, isNotNull);
    });
  });
}
