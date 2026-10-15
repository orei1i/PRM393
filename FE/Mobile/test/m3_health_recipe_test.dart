// test/m3_health_recipe_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/mock/recipe_mock_data.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_detail.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

UpdateHealthProfileRequestDto _profile(
        {double height = 170,
        double weight = 65,
        List<String> allergies = const ['peanut']}) =>
    UpdateHealthProfileRequestDto(
      heightCm: height,
      weightKg: weight,
      goal: HealthGoal.loseWeight,
      allergies: allergies,
      dietaryRestrictions: const ['low_sodium'],
    );

void main() {
  setUp(MockMealPlannerRepository.reset);

  group('health profile', () {
    test('PUT recomputes BMI (170 cm / 65 kg → 22.5) and is stored', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      final saved = await repo.updateHealthProfile(_profile());
      expect(saved.bmi, 22.5);
      expect(saved.goal, 'lose_weight');
      final again = await repo.getHealthProfile();
      expect(again.weightKg, 65);
      expect(again.dietaryRestrictions, ['low_sodium']);
      expect(again.toEntity().bmiCategory().label, 'Bình thường');
    });

    test('weight exactly 99.9 → 503; out of range → 400', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      await expectLater(
          repo.updateHealthProfile(_profile(weight: 99.9)), _apiError(503));
      await expectLater(
          repo.updateHealthProfile(_profile(height: 90)), _apiError(400));
      expect((await repo.getHealthProfile()).weightKg, 66,
          reason: 'failed saves change nothing');
    });

    test('each account has its own profile', () async {
      await MockMealPlannerRepository(userId: 'u_me')
          .updateHealthProfile(_profile(allergies: ['soy']));
      final tam = await MockMealPlannerRepository(userId: 'u_chef_tam')
          .getHealthProfile();
      expect(tam.heightCm, 168);
      expect(tam.allergies, isEmpty);
    });

    test('a generated plan avoids the new allergies', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      await repo.updateHealthProfile(_profile(allergies: ['peanut', 'soy']));
      final plan =
          await repo.generateMealPlan(startDate: startOfWeek(DateTime.now()));
      for (final day in plan.days) {
        for (final meal in day.meals.values) {
          expect(meal.allergens, isNot(contains('soy')), reason: meal.name);
          expect(meal.allergens, isNot(contains('peanut')), reason: meal.name);
          expect(meal.source, 'ai');
        }
      }
      final swaps = await repo.getSwapSuggestions(
          planId: plan.id, date: plan.days.first.date, slot: MealSlot.lunch);
      expect(swaps.every((r) => !r.allergens.contains('soy')), isTrue);
    });
  });

  group('recipe detail', () {
    test('parses numeric / text quantities and newline steps', () {
      final dto = RecipeDetailDto.fromJson({
        'id': 105,
        'name': 'Bún riêu chay',
        'instructions':
            '1. Phi thơm hành.\nBước 2: Cho cà chua vào.\n\n3) Nêm.',
        'caloriesCache': 520,
        'isVegan': true,
        'ingredients': [
          {'ingredientId': 7, 'name': 'Đậu hũ', 'quantity': 200, 'unit': 'g'},
          {'name': 'Bông cải', 'quantity': '0,5', 'unit': 'bông'},
          {'name': 'Muối', 'quantity': null, 'unit': ''},
        ],
      }).toEntity();
      expect(dto.id, '105');
      expect(dto.steps, ['Phi thơm hành.', 'Cho cà chua vào.', 'Nêm.']);
      expect(dto.ingredients.map((i) => i.amount),
          ['200 g', '0,5 bông', 'vừa ăn']);
      expect(dto.caloriesCache, 520);
      expect(formatQuantity(1.25), '1,25');
    });

    test('the catalogue resolves every planner, scanner and seasonal id', () {
      final ids = [
        ...plannerRecipeIds(),
        'menu_1',
        'menu_2',
        'menu_3',
        'fs_menu_1',
        'ls1',
        'ds1',
        'cs_tam_chao_yen_mach',
      ];
      for (final id in ids) {
        final json = mockRecipeDetail(id);
        expect(json, isNotNull, reason: id);
        final recipe =
            RecipeDetailDto.fromJson(Map<String, dynamic>.from(json!))
                .toEntity();
        expect(recipe.ingredients, isNotEmpty, reason: id);
        expect(recipe.steps, isNotEmpty, reason: id);
        expect(recipe.caloriesCache, greaterThan(0), reason: id);
      }
      // Whole words only: "Salad" has no "sả".
      final salad = RecipeDetailDto.fromJson(
              Map<String, dynamic>.from(mockRecipeDetail('ls2')!))
          .toEntity();
      expect(salad.ingredients.map((i) => i.name), isNot(contains('Sả')));
    });

    test('unknown id → 404, #fail → 503', () async {
      final repo = MockRecipeRepository();
      expect((await repo.getRecipe('l5')).ingredients, isNotEmpty);
      await expectLater(repo.getRecipe('khong_co'), _apiError(404));
      await expectLater(repo.getRecipe('#fail'), _apiError(503));
    });
  });

  group('meal sources', () {
    test('own recipes are saved, reusable and open as a recipe', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      final created = await repo.createMyRecipe(const CreateRecipeRequestDto(
        name: 'Gỏi cuốn đậu phộng',
        calories: 450,
        ingredients: [
          RecipeIngredientInput(name: 'Bánh tráng', quantity: 8, unit: 'lá'),
          RecipeIngredientInput(name: 'Đậu phộng', quantity: 30, unit: 'g'),
        ],
        steps: ['Cuốn rau và bún.', 'Chấm tương.'],
      ));
      expect(created.source, 'user_recipe');
      expect(created.allergens, contains('peanut'));
      expect((await repo.getMyRecipes()).map((r) => r.id), [created.id]);
      expect(
          await MockMealPlannerRepository(userId: 'u_chef_tam').getMyRecipes(),
          isEmpty);

      final plan = (await repo.getCurrentMealPlan())!;
      final day = await repo.swapMeal(
        planId: plan.id,
        request: SwapMealRequestDto(
            date: plan.days.first.date,
            slot: MealSlot.dinner,
            recipeId: created.id,
            source: MealSource.userRecipe),
      );
      expect(
          day.toEntity().meals[MealSlot.dinner]!.source, MealSource.userRecipe);

      final detail = RecipeDetailDto.fromJson(
              Map<String, dynamic>.from(mockRecipeDetail(created.id)!))
          .toEntity();
      expect(detail.steps, ['Cuốn rau và bún.', 'Chấm tương.']);
      expect(detail.ingredients.first.amount, '8 lá');
      expect(detail.createdByName, 'Minh Anh');
      await expectLater(
          MockMealPlannerRepository().createMyRecipe(
              const CreateRecipeRequestDto(
                  name: 'x', calories: 100, ingredients: [], steps: [])),
          _apiError(401));
    });

    test('chef suggestions: Minh Anh has Tâm\'s, others have none', () async {
      final suggestions =
          await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
      expect(suggestions, hasLength(2));
      final first = suggestions.first.toEntity();
      expect(first.chefName, 'Lê Quang Tâm');
      expect(first.recipe.source, MealSource.chef);
      expect(
          await MockMealPlannerRepository(userId: 'u_chef_tam')
              .getChefSuggestions(),
          isEmpty);
    });

    test('a typed-in dish keeps optional kcal and is checked for allergens',
        () async {
      final repo = MockMealPlannerRepository(userId: 'u_me');
      final plan = (await repo.getCurrentMealPlan())!;
      final date = plan.days[2].date;
      final day = (await repo.addMealToCurrentPlan(AddMealRequestDto(
        date: date,
        slot: MealSlot.breakfast,
        name: 'Bánh mì đậu phộng nhà làm',
        source: MealSource.manual.apiValue,
      )))
          .toEntity();
      final meal = day.meals[MealSlot.breakfast]!;
      expect(meal.source, MealSource.manual);
      expect(meal.hasNutrition, isFalse);
      expect(meal.allergens, containsAll(['peanut', 'gluten']));

      final cleared = await repo.removeMeal(
          planId: plan.id, date: date, slot: MealSlot.breakfast);
      expect(cleared.meals.containsKey('breakfast'), isFalse);
    });

    test('an empty week has 7 days and no meals', () async {
      final plan = await MockMealPlannerRepository(userId: 'u_me')
          .createEmptyMealPlan(startDate: startOfWeek(DateTime.now()));
      expect(plan.days, hasLength(7));
      expect(plan.days.every((d) => d.meals.isEmpty), isTrue);
    });
  });

  group('pantry', () {
    test('add many merges names, remove and clear; guests get 401', () async {
      final pantry = MockPantryRepository(userId: 'u_me');
      final seeded = await pantry.getPantry();
      expect(seeded.map((p) => p.ingredient), contains('Đậu hũ'));
      // Names only: nothing about freshness on the wire.
      expect(seeded.first.toJson().containsKey('freshness'), isFalse);
      expect(
          seeded.firstWhere((p) => p.ingredient == 'Gạo lứt').toEntity().source,
          PantrySource.manual);

      final scannedAt = DateTime.utc(2026, 10, 15, 8);
      final after = await pantry.addItems([
        AddPantryItemDto(ingredient: 'dau hu', scannedAt: scannedAt),
        const AddPantryItemDto(ingredient: 'Bông cải xanh'),
      ]);
      expect(after.length, seeded.length + 1, reason: '"dau hu" is Đậu hũ');
      final tofu = after.firstWhere((p) => p.ingredient == 'Đậu hũ');
      expect(tofu.scannedAt, scannedAt, reason: 'the merge refreshes the row');
      expect(tofu.toEntity().source, PantrySource.scan);
      expect(tofu.toEntity().source.label, 'Quét');

      await pantry.removeItem(after.first.id);
      expect(await pantry.getPantry(), hasLength(after.length - 1));
      await pantry.clear();
      expect(await pantry.getPantry(), isEmpty);
      await expectLater(
          MockPantryRepository()
              .addItems(const [AddPantryItemDto(ingredient: 'Cà rốt')]),
          _apiError(401));
    });

    test('the fridge refuses foods that are not vegan', () async {
      final pantry = MockPantryRepository(userId: 'u_me');
      await expectLater(
          pantry.addItems(const [AddPantryItemDto(ingredient: 'Trứng gà')]),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 422)
              .having(
                  (e) => e.message, 'message', contains('không thuần chay'))));
      expect((await pantry.getPantry()).map((p) => p.ingredient),
          isNot(contains('Trứng gà')));
      // An older server that still sends `freshness` is fine.
      final legacy = PantryItemDto.fromJson(
          {'id': 9, 'ingredient': 'Cà chua', 'freshness': 'use_soon'});
      expect(legacy.toEntity().ingredient, 'Cà chua');
    });

    test('"Tạo thực đơn từ tủ lạnh" builds dishes around fridge items',
        () async {
      await MockPantryRepository(userId: 'u_chef_tam').addItems(const [
        AddPantryItemDto(ingredient: 'Đậu hũ'),
      ]);
      final repo = MockMealPlannerRepository(userId: 'u_chef_tam');
      final plan = await repo.generateMealPlan(
          startDate: startOfWeek(DateTime.now()), fromPantry: true);
      final today = plan.days
          .firstWhere((d) => isSameDay(d.date, DateTime.now()))
          .toEntity();
      expect(
          today.meals.values
              .any((r) => r.name.toLowerCase().contains('đậu hũ')),
          isTrue);
    });
  });

  group('session changes', () {
    Future<ProviderContainer> signedInContainer() async {
      SharedPreferences.setMockInitialValues(
          {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      return container;
    }

    test('planner, allergies, pantry and scanner tray follow the account',
        () async {
      final container = await signedInContainer();
      container
        ..listen(mealPlanControllerProvider, (_, __) {})
        ..listen(userAllergiesProvider, (_, __) {})
        ..listen(pantryControllerProvider, (_, __) {})
        ..listen(scannerControllerProvider, (_, __) {});

      final me = await container.read(mealPlanControllerProvider.future);
      expect(me.profile.allergies, ['peanut']);
      expect(await container.read(userAllergiesProvider.future), ['peanut']);
      final saved = await container
          .read(pantryControllerProvider.notifier)
          .addFromScan(const [
        ScannedPantryItem(name: 'Cà rốt'),
        ScannedPantryItem(name: 'Rau chân vịt'),
        // Never saved: not vegan.
        ScannedPantryItem(name: 'Trứng gà', isVegan: false),
      ]);
      expect(saved, 2);
      final pantry = container.read(pantryControllerProvider).requireValue;
      expect(pantry.firstWhere((p) => p.ingredient == 'Cà rốt').source,
          PantrySource.scan);
      expect(pantry.firstWhere((p) => p.ingredient == 'Rau chân vịt').scannedAt,
          isNotNull);
      expect(pantry.map((p) => p.ingredient), isNot(contains('Trứng gà')));

      // Typed in on the Thực đơn tab: non-vegan foods are refused with the
      // reason and vegan swaps, vegan ones are added.
      final pantryNotifier = container.read(pantryControllerProvider.notifier);
      final refused = await pantryNotifier.addManual('Mật ong');
      expect(refused.isVegan, isFalse);
      expect(refused.nonVeganReason, 'Mật ong (từ ong)');
      expect(refused.veganAlternatives, contains('Siro phong'));
      final accepted = await pantryNotifier.addManual('Siro phong');
      expect(accepted.isVegan, isTrue);
      final afterManual = container.read(pantryControllerProvider).requireValue;
      expect(afterManual.map((p) => p.ingredient), contains('Siro phong'));
      expect(afterManual.map((p) => p.ingredient), isNot(contains('Mật ong')));
      expect(afterManual.firstWhere((p) => p.ingredient == 'Siro phong').source,
          PantrySource.manual);
      container.read(scannerControllerProvider.notifier).addManual('Nấm rơm');
      expect(container.read(scannerControllerProvider).items, hasLength(1));

      final session = container.read(sessionControllerProvider.notifier);
      await session.signOut();
      expect(container.read(scannerControllerProvider).items, isEmpty);
      await session.signInWithGoogle(account: tamChefAccount);

      final tam = await container.read(mealPlanControllerProvider.future);
      expect(tam.profile.heightCm, 168);
      expect(tam.profile.allergies, isEmpty);
      expect(await container.read(userAllergiesProvider.future), isEmpty);
      final tamPantry = await container.read(pantryControllerProvider.future);
      expect(tamPantry.map((p) => p.ingredient), isNot(contains('Cà rốt')));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('saving the health profile updates the planner state', () async {
      final container = await signedInContainer();
      container.listen(mealPlanControllerProvider, (_, __) {});
      await container.read(mealPlanControllerProvider.future);
      await container
          .read(mealPlanControllerProvider.notifier)
          .updateHealthProfile(
        heightCm: 170,
        weightKg: 60,
        goal: HealthGoal.maintain,
        allergies: const ['peanut', 'soy'],
        dietaryRestrictions: const [],
      );
      final state = container.read(mealPlanControllerProvider).requireValue;
      expect(state.profile.weightKg, 60);
      expect(state.profile.bmi, 20.8);
      expect(state.selectedDay!.conflictCount(state.profile.allergies),
          greaterThan(0),
          reason: 'today\'s soy dishes are flagged');
      expect(await container.read(userAllergiesProvider.future),
          ['peanut', 'soy']);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
