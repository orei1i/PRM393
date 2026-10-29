// test/recipe_customization/recipe_variant_test.dart
// POST /recipes/{id}/variants in mock mode: the server recomputes the
// figures like the preview, stores a private recipe in "Công thức của tôi"
// and refuses invalid changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/recipe/data/mock/recipe_mock_data.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';

Matcher _apiError(int status, [String? code]) => throwsA(isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => code == null || e.code == code, 'code $code', isTrue));

const _e2 = CreateVariantRequestDto(
  name: 'Bún riêu chay (tuỳ chỉnh)',
  swaps: {'rieu': 'rieu_nam'},
  removed: ['rau_muong', 'mam_ruoc'],
);

void main() {
  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
  });

  test('a saved variant matches the preview and lands in "Công thức của tôi"',
      () async {
    final repo = MockRecipeCommunityRepository(userId: 'u_me');
    final saved = (await repo.createVariant('l5', _e2)).toEntity();

    final l5 = RecipeDetailDto.fromJson(
            Map<String, dynamic>.from(mockRecipeDetail('l5')!))
        .toEntity();
    final preview = CustomizedRecipe(l5, _e2.choices);
    expect(saved.id, startsWith('ur_'));
    expect(saved.caloriesCache, preview.energy.shown);
    expect(saved.caloriesCache, 488);
    expect(saved.proteinG, preview.energy.proteinG!.roundToDouble());
    expect(saved.allergens, isEmpty);
    expect(saved.servings, 2);
    expect(saved.createdBy, 'u_me');
    expect(saved.createdByName, 'Minh Anh');
    expect(saved.isPublic, isFalse);
    expect(saved.basedOnRecipeId, 'l5');
    expect(saved.basedOnName, 'Bún riêu chay');
    expect(saved.nutritionEstimated, isFalse);
    expect(saved.customizations.map((c) => c.label), [
      'Đã đổi Đậu hũ → Nấm rơm băm nhuyễn',
      'Đã bỏ Mắm ruốc chay',
      'Đã bỏ Rau muống chẻ',
    ]);
    expect(
        saved.ingredients.map((i) => i.name), isNot(contains('Rau muống chẻ')));
    final rieu = saved.ingredient('rieu')!;
    expect(rieu.name, 'Nấm rơm băm nhuyễn');
    expect(rieu.isSignature, isTrue);
    expect(rieu.substitutes.first.name, 'Đậu hũ');
    expect(MockRecipeCommunityStore.variantCount, 1);

    // "Công thức của tôi" (planner) has it, with the server's kcal.
    final planner = MockMealPlannerRepository(userId: 'u_me');
    final mine = await planner.getMyRecipes();
    expect(mine.map((r) => r.id), [saved.id]);
    expect(mine.single.nutrition.calories, 488);
    expect(mine.single.source, 'user_recipe');
    expect(await MockMealPlannerRepository(userId: 'u_chef_tam').getMyRecipes(),
        isEmpty);

    // The recipe page opens it with its origin.
    final opened =
        (await MockRecipeRepository().getRecipe(saved.id)).toEntity();
    expect(opened.basedOnName, 'Bún riêu chay');
    expect(opened.customizations, hasLength(3));
    expect(opened.caloriesCache, 488);

    // Placed in the plan, the card shows the same energy (AC2.5).
    final plan = (await planner.getCurrentMealPlan())!;
    final day = (await planner.swapMeal(
      planId: plan.id,
      request: SwapMealRequestDto(
        date: plan.days[4].date,
        slot: MealSlot.dinner,
        recipeId: saved.id,
        source: MealSource.userRecipe,
      ),
    ))
        .toEntity();
    final meal = day.meals[MealSlot.dinner]!;
    expect(meal.nutrition.calories, 488);
    expect(meal.source, MealSource.userRecipe);
  });

  test('a swap without nutrition data is saved as an estimate', () async {
    final saved = (await MockRecipeCommunityRepository(userId: 'u_me')
            .createVariant(
                'l5',
                const CreateVariantRequestDto(
                    name: 'Bún riêu phở', swaps: {'bun': 'pho_tuoi'})))
        .toEntity();
    expect(saved.caloriesCache, 580);
    expect(saved.nutritionEstimated, isTrue);
  });

  test('a catalogue recipe placed from its page reads "Từ công thức"',
      () async {
    final planner = MockMealPlannerRepository(userId: 'u_me');
    final plan = (await planner.getCurrentMealPlan())!;
    final day = (await planner.swapMeal(
      planId: plan.id,
      request: SwapMealRequestDto(
        date: plan.days.first.date,
        slot: MealSlot.lunch,
        recipeId: 'l5',
        source: MealSource.recipe,
      ),
    ))
        .toEntity();
    expect(day.meals[MealSlot.lunch]!.source, MealSource.recipe);
    expect(day.meals[MealSlot.lunch]!.nutrition.calories, 580);
  });

  group('errors', () {
    final repo = MockRecipeCommunityRepository(userId: 'u_me');

    test('signature row removed → 400 signature_required', () async {
      await expectLater(
          repo.createVariant(
              'l5',
              const CreateVariantRequestDto(
                  name: 'Không riêu', removed: ['rieu'])),
          _apiError(400, 'signature_required'));
    });

    test('substitute not listed for that row → 400 invalid_substitute',
        () async {
      await expectLater(
          repo.createVariant(
              'l5',
              const CreateVariantRequestDto(
                  name: 'Lạ', swaps: {'rieu': 'bun_gao_lut'})),
          _apiError(400, 'invalid_substitute'));
    });

    test('name < 2 or > 80 chars → 400', () async {
      await expectLater(
          repo.createVariant('l5',
              const CreateVariantRequestDto(name: 'x', removed: ['rau_muong'])),
          _apiError(400));
      await expectLater(
          repo.createVariant(
              'l5',
              CreateVariantRequestDto(
                  name: 'x' * 81, removed: const ['rau_muong'])),
          _apiError(400));
    });

    test('guest → 401; unknown recipe → 404; #fail → 503', () async {
      await expectLater(
          MockRecipeCommunityRepository().createVariant('l5', _e2),
          _apiError(401));
      await expectLater(repo.createVariant('khong_co', _e2), _apiError(404));
      await expectLater(
          repo.createVariant(
              'l5',
              const CreateVariantRequestDto(
                  name: 'Thử #fail', removed: ['rau_muong'])),
          _apiError(503));
      expect(MockRecipeCommunityStore.variantCount, 0);
    });
  });
}
