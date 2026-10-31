// test/qa_fixes/planner_test.dart
// Q2 (a chef's dish has a page), Q5 (the AI banner speaks for AI only), Q6
// (typed dishes: allergies and the vegan rule), Q15 (picker kcal explained),
// Q17 (the seed doesn't blame AI), Q21 (the fridge spells names like the
// nutrition DB) and the own-recipe "Số phần ăn".
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/allergy_match.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/pantry_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/user_recipe_form_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/allergy_guard_banner.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_picker_sheet.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';

import '../hybrid/planner_test_support.dart';
import 'qa_support.dart';

Recipe _dish(MealSource source, {String name = 'Cơm gạo lứt'}) => Recipe(
      id: 'x',
      name: name,
      nutrition: const Nutrition(calories: 500),
      source: source,
    );

MealPlanDay _day(Iterable<MealSource> sources) => MealPlanDay(
      date: DateTime(2026, 10, 31),
      meals: {
        for (final (i, s) in sources.indexed) MealSlot.values[i]: _dish(s),
      },
    );

AddMealRequestDto _chefDish({
  String? sourceId = 'rc_banh_mi_nam',
  List<String> ingredients = const [],
  String? instructions,
}) =>
    AddMealRequestDto(
      date: DateTime.now(),
      slot: MealSlot.lunch,
      name: 'Bánh mì chay pate nấm',
      calories: 420,
      proteinG: 18,
      source: 'chef',
      sourceId: sourceId,
      sourceName: 'ThS. Thu Hà',
      ingredients: ingredients,
      instructions: instructions,
    );

void main() {
  setUp(MockMealPlannerRepository.reset);

  group('Q2 a chef plan dish opens a page', () {
    final repo = MockMealPlannerRepository(userId: 'u_me');

    test('without ingredients or steps: its name and figures', () async {
      final result = await repo.addMealsToCurrentPlan([_chefDish()]);
      final meal = result.days.single.meals[MealSlot.lunch.apiValue]!;
      expect(meal.id, 'ch_rc_banh_mi_nam');

      final page = await MockRecipeRepository().getRecipe(meal.id);
      expect(page.name, 'Bánh mì chay pate nấm');
      expect(page.toEntity().isSnapshot, isTrue);
      expect(page.toEntity().isReadOnly, isTrue);
      expect(page.caloriesCache, 420);
    });

    test('with what the chef wrote', () async {
      final result = await repo.addMealsToCurrentPlan([
        _chefDish(
          ingredients: ['Bánh mì', 'Nấm mỡ'],
          instructions: '1. Xào nấm.\n2. Phết pate lên bánh.',
        ),
      ]);
      final meal = result.days.single.meals[MealSlot.lunch.apiValue]!;
      final page = (await MockRecipeRepository().getRecipe(meal.id)).toEntity();
      expect(page.isSnapshot, isFalse);
      expect(page.ingredients.map((i) => i.name), ['Bánh mì', 'Nấm mỡ']);
      expect(page.steps, hasLength(2));
      expect(page.allergens, contains('gluten'));
    });

    test('a dish without a recipe id too', () async {
      final result =
          await repo.addMealsToCurrentPlan([_chefDish(sourceId: null)]);
      final meal = result.days.single.meals[MealSlot.lunch.apiValue]!;
      expect((await MockRecipeRepository().getRecipe(meal.id)).name, meal.name);
    });

    testWidgets('the page shows, not "Không tìm thấy công thức"',
        (tester) async {
      await tester.runAsync(() => repo.addMealsToCurrentPlan([_chefDish()]));
      await pumpScreen(
          tester,
          const RecipeDetailScreen(
              recipeId: 'ch_rc_banh_mi_nam', name: 'Bánh mì chay pate nấm'));
      await wait(tester);
      expect(find.text('Không tìm thấy công thức'), findsNothing);
      expect(find.text('Bánh mì chay pate nấm'), findsWidgets);
      expect(find.text(RecipeDetailScreen.snapshotNote), findsOneWidget);
      await disposeScreen(tester);
    });

    test('real planner: the plan item gives the page', () async {
      const itemId = '0123456789abcdef0123456789abcdef';
      final snapshots = PlanItemSnapshots()
        ..registerDay({
          'date': '2026-10-31',
          'meals': {
            'lunch': {
              'id': itemId,
              'name': 'Bánh mì chay pate nấm',
              'calories': 420,
              'source': 'chef',
            },
          },
        });
      final page = await RemoteRecipeApiService(
        catalog: () => throw StateError('not a catalogue id'),
        snapshots: () => snapshots,
      ).getRecipe(itemId);
      expect(page.name, 'Bánh mì chay pate nấm');
      expect(page.toEntity().isSnapshot, isTrue);
    });

    test('the steps are not sent to the BE', () {
      expect(_chefDish(instructions: '1. Xào nấm.').toJson(),
          isNot(contains('instructions')));
    });
  });

  group('Q5 the AI banner speaks for AI only', () {
    test('shown only with an AI dish or a conflict', () {
      expect(AllergyGuardBanner.shownFor(_day(const []), ['peanut']), isFalse);
      expect(
          AllergyGuardBanner.shownFor(
              _day(const [MealSource.chef, MealSource.manual]), ['peanut']),
          isFalse);
      expect(AllergyGuardBanner.shownFor(_day(const [MealSource.ai]), const []),
          isTrue);
      final conflict = MealPlanDay(
        date: DateTime(2026, 10, 31),
        meals: {
          MealSlot.lunch: _dish(MealSource.chef, name: 'Gỏi lá lốt'),
        },
      );
      expect(AllergyGuardBanner.shownFor(conflict, ['lá lốt']), isTrue);
    });

    testWidgets('a mixed day claims nothing for the other dishes',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AllergyGuardBanner(
              allergies: ['peanut'], conflictCount: 0, allAi: false),
        ),
      ));
      expect(find.textContaining('Thực đơn do AI tạo'), findsNothing);
      expect(find.textContaining('Món do AI gợi ý đã loại trừ: Đậu phộng'),
          findsOneWidget);
    });

    testWidgets('a blank week has no banner, an AI week has', (tester) async {
      const screen = MealPlannerScreen();
      final c = await pumpScreen(tester, screen);
      await wait(tester);
      final notifier = c.read(mealPlanControllerProvider.notifier);

      final blank = notifier.createEmptyPlan();
      await wait(tester);
      await blank;
      expect(find.byType(AllergyGuardBanner), findsNothing);

      final generated = notifier.generatePlan();
      await wait(tester, 3000);
      await generated;
      expect(find.textContaining('Thực đơn do AI tạo, đã loại trừ: Đậu phộng'),
          findsOneWidget);
      await disposeScreen(tester);
    });
  });

  group('Q6 typed dishes', () {
    test('allergens are found with or without accents and punctuation', () {
      for (final name in [
        'Pho thit bo dau phong',
        'Phở đậu phộng, rau thơm',
        'Xôi ĐẬU PHỘNG',
        'đậu phộng.',
      ]) {
        expect(detectDishAllergens(name), contains('peanut'), reason: name);
      }
      expect(detectDishAllergens('Banh mi nuong'), contains('gluten'));
      expect(detectDishAllergens('Muối mè'), contains('sesame'));
    });

    test('whole words, and short names keep their accents', () {
      expect(detectDishAllergens('Gỏi nấm mèo'), isNot(contains('sesame')));
      expect(detectDishAllergens('Canh me chua'), isNot(contains('sesame')));
      expect(detectDishAllergens('Cơm trắng'), isEmpty);
    });

    test('a typed dish conflicts by its name, on any server', () {
      expect(
          _dish(MealSource.manual, name: 'Pho dau phong')
              .allergenConflicts(['peanut']),
          ['peanut']);
      // The BE's answer for a typed dish: no tags at all.
      final fromBackend = RecipeDto.fromJson({
        'id': '0123456789abcdef0123456789abcdef',
        'name': 'Phở đậu phộng,',
        'calories': 500,
        'source': 'manual',
        'allergens': <String>[],
      }).toEntity();
      expect(fromBackend.allergenConflicts(['peanut']), ['peanut']);
      expect(
          _dish(MealSource.ai, name: 'Pho dau phong')
              .allergenConflicts(['peanut']),
          isEmpty,
          reason: 'a catalogue dish goes by its tags');
    });

    test('a dish with the allergen is added, with the warning', () async {
      final c = await qaContainer();
      addTearDown(c.listen(mealPlanControllerProvider, (_, __) {}).close);
      await c.read(mealPlanControllerProvider.future);
      final added = await c
          .read(mealPlanControllerProvider.notifier)
          .addManualMeal(slot: MealSlot.lunch, name: 'Xôi dau phong');
      expect(added.allergenConflicts, ['peanut']);
    });

    test('a dish that is not vegan is refused, nothing changes', () async {
      final c = await qaContainer();
      addTearDown(c.listen(mealPlanControllerProvider, (_, __) {}).close);
      final before = await c.read(mealPlanControllerProvider.future);
      final held = before.selectedDay!.meals[MealSlot.lunch];
      for (final name in ['Phở thịt bò', 'Pho thit bo dau phong']) {
        await expectLater(
            c
                .read(mealPlanControllerProvider.notifier)
                .addManualMeal(slot: MealSlot.lunch, name: name),
            throwsA(isA<ApiException>()
                .having((e) => e.code, 'code', 'not_vegan')
                .having((e) => e.statusCode, 'statusCode', 422)),
            reason: name);
      }
      final after = c.read(mealPlanControllerProvider).requireValue;
      expect(after.selectedDay!.meals[MealSlot.lunch]?.id, held?.id);
      expect(after.swappingSlot, isNull);
    });

    testWidgets('the sheet refuses it with the reason and vegan swaps',
        (tester) async {
      await pumpScreen(
          tester,
          const Scaffold(
              body: MealPickerSheet(slot: MealSlot.lunch, allergies: [])));
      await wait(tester, 1500);
      await tester.ensureVisible(find.text('Tự nhập món'));
      await tester.pump();
      await tester.tap(find.text('Tự nhập món'));
      await wait(tester, 500);
      final name = find.widgetWithText(TextFormField, 'Tên món');
      await tester.enterText(name, 'Phở thịt bò');
      final submit = find.widgetWithText(FilledButton, 'Thêm vào bữa trưa');
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(submit);
      await tester.pump();

      expect(
          find.text(
              'Phở thịt bò không thuần chay nên không thêm vào thực đơn.'),
          findsOneWidget);
      expect(find.text('Đậu hũ'), findsOneWidget, reason: 'a vegan swap');

      await tester.enterText(name, 'Phở nấm');
      await tester.pump();
      expect(find.textContaining('không thuần chay'), findsNothing);
      await disposeScreen(tester);
    });
  });

  testWidgets('Q15 the picker says which size its kcal are for',
      (tester) async {
    await tester.runAsync(() => MockMealPlannerRepository(userId: 'u_me')
        .createEmptyMealPlan(startDate: startOfWeek(DateTime.now())));
    final c = await pumpScreen(tester, const Scaffold(body: SizedBox()));
    final loading = c.read(mealPlanControllerProvider.future);
    await wait(tester);
    await loading;
    MealPickerSheet.show(tester.element(find.byType(SizedBox).first),
        slot: MealSlot.breakfast, date: DateTime.now(), allergies: const []);
    await wait(tester, 3000);
    expect(
        find.textContaining(RegExp(r'kcal cho \d+(,\d+)? phần')), findsWidgets);
    await disposeScreen(tester);
  });

  test('Q17 the seed labels no dish with an allergen as chosen by AI',
      () async {
    final repo = MockMealPlannerRepository(userId: 'u_me');
    final profile = (await repo.getHealthProfile())!.toEntity();
    final plan = (await repo.getCurrentMealPlan())!.toEntity();
    final meals = plan.days.expand((d) => d.meals.values).toList();
    final conflicting =
        meals.where((r) => r.allergenConflicts(profile.allergies).isNotEmpty);
    expect(conflicting, isNotEmpty, reason: 'the warning demo stays');
    expect(conflicting.where((r) => r.source == MealSource.ai), isEmpty);
    expect(meals.where((r) => r.source == MealSource.ai), isNotEmpty);
  });

  group('Q21 the fridge spells names like the nutrition DB', () {
    Future<List<String>> names(ProviderContainer c) async => [
          for (final item in await c.read(pantryControllerProvider.future))
            item.ingredient
        ];

    test('typed without accents, in "Nguyên liệu trong tủ"', () async {
      final c = await qaContainer();
      addTearDown(c.listen(pantryControllerProvider, (_, __) {}).close);
      await c.read(pantryControllerProvider.notifier).addManual('ca rot');
      expect(await names(c), contains('Cà rốt'));
      expect(await names(c), isNot(contains('ca rot')));
    });

    test('typed in the scanner', () async {
      final c = await qaContainer();
      addTearDown(c.listen(pantryControllerProvider, (_, __) {}).close);
      await c.read(pantryControllerProvider.future);
      final item =
          c.read(scannerControllerProvider.notifier).addManual('ca rot')!;
      await c.read(pantryControllerProvider.notifier).addFromScan([
        ScannedPantryItem(name: item.name, source: PantrySource.manual),
      ]);
      expect(await names(c), contains('Cà rốt'));
    });

    test('an unknown food stays as typed', () async {
      final c = await qaContainer();
      addTearDown(c.listen(pantryControllerProvider, (_, __) {}).close);
      await c.read(pantryControllerProvider.notifier).addManual('banh tet la');
      expect(await names(c), contains('banh tet la'));
    });

    group('real BE', () {
      setUp(() =>
          BackendModules.debugOverride(BackendModules.supportedByBackend));
      tearDown(() => BackendModules.debugOverride(null));

      test('the POST carries the catalogue name', () async {
        final backend = FakeBackend()
          ..on('GET /users/me/ingredients', 200, envelope(<Object>[]))
          ..on('POST /users/me/ingredients', 200, envelope(<Object>[]))
          ..on(
              'GET /ingredients',
              200,
              envelope([
                {'id': 'a', 'name': 'Cà chua bi', 'isVegan': true},
                {'id': 'b', 'name': 'Cà chua', 'isVegan': true},
              ]));
        final c = await backendContainer(backend);
        addTearDown(c.listen(pantryControllerProvider, (_, __) {}).close);
        await c.read(pantryControllerProvider.notifier).addManual('ca chua');
        final body = backend.bodyOf('POST /users/me/ingredients');
        expect(body.toString(), contains('Cà chua'));
        expect(body.toString(), isNot(contains('ca chua')));
      });

      test('a failed lookup still saves what was typed', () async {
        final backend = FakeBackend()
          ..on('GET /users/me/ingredients', 200, envelope(<Object>[]))
          ..on('POST /users/me/ingredients', 200, envelope(<Object>[]));
        final c = await backendContainer(backend);
        addTearDown(c.listen(pantryControllerProvider, (_, __) {}).close);
        await c.read(pantryControllerProvider.notifier).addManual('ca chua');
        expect(backend.bodyOf('POST /users/me/ingredients').toString(),
            contains('ca chua'));
      });
    });
  });

  group('own recipe: "Số phần ăn"', () {
    tearDown(() => BackendModules.debugOverride(null));

    testWidgets('mock: the field stays', (tester) async {
      await pumpScreen(tester, const UserRecipeFormScreen());
      await tester.pump();
      expect(find.widgetWithText(TextFormField, 'Số phần ăn'), findsOneWidget);
      expect(find.textContaining('Máy chủ chưa lưu số phần'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('real recipes: no field, and the form says why',
        (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await pumpScreen(tester, const UserRecipeFormScreen());
      await tester.pump();
      expect(find.widgetWithText(TextFormField, 'Số phần ăn'), findsNothing);
      expect(
          find.textContaining('Máy chủ chưa lưu số phần ăn'), findsOneWidget);
      await disposeScreen(tester);
    });
  });
}
