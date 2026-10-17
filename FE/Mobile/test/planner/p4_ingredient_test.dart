// test/planner/p4_ingredient_test.dart
//
// P4 (TestPRM p16–p17): "Nguyên liệu trong tủ" as its own screen (rows with
// an illustration and energy per unit, swipe to delete with undo, category
// filter) and the ingredient detail (nutrition, who it suits, foods not to
// combine, dishes, recipes). The fridge still refuses non-vegan foods.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/ingredient/data/mock/ingredient_nutrition_data.dart';
import 'package:veganlife_mobile/features/ingredient/data/models/ingredient_model.dart';
import 'package:veganlife_mobile/features/ingredient/domain/entities/ingredient.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/widgets/ingredient_avatar.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/scanner/domain/vegan_check.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

List<IngredientSummary> get _index => [
      for (final row in mockIngredientRows)
        IngredientSummaryDto.fromJson(row).toEntity(),
    ];

Future<void> _pump(WidgetTester tester, Widget home,
    {Size size = const Size(411, 1400)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(_minhAnh);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  setUp(MockMealPlannerRepository.reset);

  group('nutrition DB', () {
    test('35 vegan ingredients, every one with kcal and a standard unit', () {
      final rows = _index;
      expect(rows, hasLength(35));
      expect(rows.map((r) => r.id).toSet(), hasLength(35));
      for (final r in rows) {
        expect(classifyVegan(r.name).isVegan, isTrue, reason: r.name);
        expect(r.caloriesPer100g, greaterThan(0), reason: r.name);
        expect(r.altServingLabel, isNotNull, reason: r.name);
        expect(r.category, isNotNull, reason: r.name);
      }
      for (final name in [
        'Đậu hũ',
        'Đậu hũ non',
        'Tempeh',
        'Mì căn',
        'Nấm rơm',
        'Nấm đùi gà',
        'Nấm hương',
        'Cà chua',
        'Rau muống',
        'Rau chân vịt',
        'Cải thìa',
        'Bông cải xanh',
        'Cà rốt',
        'Bí đỏ',
        'Khoai lang',
        'Gạo lứt',
        'Yến mạch',
        'Đậu xanh',
        'Đậu đen',
        'Đậu gà',
        'Đậu phộng',
        'Hạt điều',
        'Mè',
        'Sữa đậu nành',
        'Rong biển',
        'Chuối',
        'Bơ',
        'Chanh',
        'Gừng',
        'Tỏi',
        'Hành tây',
        'Ớt chuông',
        'Đậu bắp',
        'Bắp',
        'Khoai tây',
      ]) {
        expect(rows.any((r) => r.name == name), isTrue, reason: name);
      }
    });

    test('energy per standard unit: "18 kcal / 100 g · 1 quả ≈ 22 kcal"', () {
      final tomato = _index.firstWhere((r) => r.id == 'ing_ca_chua');
      expect(tomato.energyLine, '18 kcal / 100 g · 1 quả ≈ 22 kcal');
      expect(energyLineOf(caloriesPer100g: 76), '76 kcal / 100 g');
    });

    test('free-text names find their row (accents, aliases, whole words)', () {
      String? id(String name, {String? withId}) =>
          findIngredient(_index, id: withId, name: name)?.id;
      expect(id('dau hu'), 'ing_dau_hu');
      expect(id('Đậu hũ non'), 'ing_dau_hu_non');
      expect(id('Rau muống chẻ'), 'ing_rau_muong');
      expect(id('Cải bó xôi'), 'ing_rau_chan_vit');
      expect(id('Nấm đông cô'), 'ing_nam_huong');
      expect(id('Bắp ngô'), 'ing_bap');
      expect(id('Đậu bắp'), 'ing_dau_bap');
      expect(id('Yến mạch cán'), 'ing_yen_mach');
      expect(id('Mè đen'), 'ing_me');
      expect(id('Bơ đậu phộng'), 'ing_dau_phong', reason: 'longest match');
      expect(id('Bò lúc lắc'), isNull, reason: '"bơ" needs its accent');
      expect(id('Nấm mỡ'), isNull);
      expect(id('anything', withId: 'ing_chuoi'), 'ing_chuoi');
    });

    test('detail: sections, recipes from the catalogue; 404 and 503', () async {
      final repo = MockIngredientRepository();
      final tofu = (await repo.detail('ing_dau_hu')).toEntity();
      expect(tofu.name, 'Đậu hũ');
      expect(tofu.proteinG, 8.1);
      expect(tofu.micronutrients.first.name, 'Canxi');
      expect(tofu.micronutrients.first.dvPercent, 27);
      expect(tofu.goodFor, isNotEmpty);
      expect(tofu.cautionFor, contains('Người dị ứng đậu nành'));
      expect(tofu.avoidCombining.single.name, 'Rau chân vịt');
      expect(tofu.suggestedDishes, isNotEmpty);
      expect(tofu.allergenIds, ['soy']);
      expect(tofu.recipes.map((r) => r.id), contains('menu_1'));
      expect(tofu.source, contains('USDA'));
      // A figure the source doesn't give stays unknown.
      final tempeh = (await repo.detail('ing_tempeh')).toEntity();
      expect(tempeh.fiberG, isNull);
      // "Bơ" recipes are avocado ones, not "bò".
      final avocado = (await repo.detail('ing_qua_bo')).toEntity();
      expect(avocado.recipes.map((r) => r.name).join(),
          isNot(contains('Bò lúc lắc')));

      await expectLater(repo.detail('ing_khong_co'), _apiError(404));
      await expectLater(repo.detail('#fail'), _apiError(503));
      final search = await repo.search('dau');
      expect(search.map((r) => r.name), containsAll(['Đậu hũ', 'Đậu gà']));
      expect((await repo.search('lac')).map((r) => r.name), ['Đậu phộng']);
    });

    test('fridge rows carry the matched DB row; unknown names none', () async {
      final pantry = MockPantryRepository(userId: 'u_me');
      final seeded = await pantry.getPantry();
      final tofu = seeded.firstWhere((p) => p.ingredient == 'Đậu hũ');
      expect(tofu.ingredientId, 'ing_dau_hu');
      expect(tofu.category, 'plant_protein');
      expect(tofu.caloriesPer100g, 76);
      final after = await pantry.addItems([
        const AddPantryItemDto(ingredient: 'Nấm mỡ'),
      ]);
      final mo = after.firstWhere((p) => p.ingredient == 'Nấm mỡ');
      expect(mo.ingredientId, isNull);
      expect(mo.caloriesPer100g, isNull);
      expect(mo.toEntity().category, isNull);
    });
  });

  group('IngredientAvatar', () {
    testWidgets('emoji on the category colour; first letter otherwise',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            IngredientAvatar(
                name: 'Cà chua',
                ingredientId: 'ing_ca_chua',
                category: IngredientCategory.veg),
            IngredientAvatar(
                name: 'đậu hũ',
                ingredientId: 'ing_dau_hu',
                category: IngredientCategory.plantProtein),
            IngredientAvatar(name: 'Nấm mỡ'),
          ]),
        ),
      ));
      expect(find.text('🍅'), findsOneWidget);
      expect(find.text('Đ'), findsOneWidget);
      expect(find.text('N'), findsOneWidget);
      expect(const IngredientAvatar(name: '  ').initial, '?');
    });
  });

  group('PantryScreen', () {
    testWidgets('rows with illustration, energy and source; filter by category',
        (tester) async {
      await _pump(tester, const PantryScreen());
      await _wait(tester);
      expect(find.text('Nguyên liệu trong tủ'), findsOneWidget);
      expect(find.text('76 kcal / 100 g · 1 bìa ≈ 114 kcal'), findsOneWidget);
      expect(find.text('18 kcal / 100 g · 1 quả ≈ 22 kcal'), findsOneWidget);
      expect(find.text('123 kcal / 100 g · 1 chén cơm ≈ 185 kcal'),
          findsOneWidget);
      expect(find.text('🍅'), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Icon && w.semanticLabel == 'Tự thêm'),
          findsOneWidget,
          reason: 'Gạo lứt');
      for (final label in ['Tất cả', 'Rau lá', 'Nấm', 'Đạm thực vật']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget,
            reason: label);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Nấm'));
      await tester.pump();
      expect(find.text('Nấm rơm'), findsOneWidget);
      expect(find.text('Đậu hũ'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Rau lá'));
      await tester.pump();
      expect(find.text('Chưa có nguyên liệu nào thuộc nhóm "Rau lá".'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả'));
      await tester.pump();
      expect(find.text('Đậu hũ'), findsOneWidget);
      await _wait(tester, 1000);
    });

    testWidgets('swipe deletes with "Hoàn tác"; the source is kept',
        (tester) async {
      await _pump(tester, const PantryScreen());
      await _wait(tester);
      await tester.drag(find.text('Cà chua'), const Offset(-500, 0));
      await tester.pump();
      await _wait(tester, 1500);
      expect(find.text('Cà chua'), findsNothing);
      expect(find.text('Đã xoá Cà chua'), findsOneWidget);
      expect(MockPantryRepository.itemsOf('u_me').map((p) => p.ingredient),
          isNot(contains('Cà chua')));
      await tester.tap(find.text('Hoàn tác'));
      await _wait(tester, 1000);
      expect(find.text('Cà chua'), findsOneWidget);
      final restored = MockPantryRepository.itemsOf('u_me')
          .firstWhere((p) => p.ingredient == 'Cà chua')
          .toEntity();
      expect(restored.source, PantrySource.scan);
      await _wait(tester, 4000); // snackbar
    });

    testWidgets('"Xoá hết" asks first; the empty fridge says what to do',
        (tester) async {
      await _pump(tester, const PantryScreen());
      await _wait(tester);
      await tester.tap(find.byTooltip('Tuỳ chọn'));
      await _wait(tester, 500);
      await tester.tap(find.text('Xoá hết'));
      await _wait(tester, 500);
      expect(find.text('Xoá hết nguyên liệu?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá hết'));
      await _wait(tester, 1000);
      expect(find.text('Tủ lạnh trống. Quét tủ lạnh hoặc thêm nguyên liệu.'),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.ancestor(
                  of: find.text('Tạo thực đơn từ tủ lạnh'),
                  matching: find.byWidgetPredicate((w) => w is FilledButton)))
              .onPressed,
          isNull);
      expect(find.text('Quét tủ lạnh'), findsOneWidget);
    });

    testWidgets('a row opens the ingredient detail', (tester) async {
      await _pump(tester, const PantryScreen());
      await _wait(tester);
      await tester.tap(find.text('Nấm rơm'));
      await _wait(tester, 2000);
      expect(find.byType(IngredientDetailScreen), findsOneWidget);
      expect(find.text('32 kcal / 100 g · 1 chén ≈ 22 kcal'), findsOneWidget);
      expect(find.text('Đã có trong tủ'), findsOneWidget);
      await _wait(tester, 1000);
    });
  });

  group('IngredientDetailScreen', () {
    testWidgets(
        'nutrition, suits / caution with a personal allergy warning, not to '
        'combine, dishes, recipes', (tester) async {
      await _pump(tester, const IngredientDetailScreen(name: 'Đậu phộng'),
          size: const Size(411, 3000));
      // DB index, then the detail, then the member's allergies.
      await _wait(tester, 3500);
      expect(find.text('567 kcal / 100 g · 1 nắm ≈ 170 kcal'), findsOneWidget);
      // Minh Anh is allergic to peanuts.
      expect(find.textContaining('Bạn đã khai báo dị ứng với đậu phộng'),
          findsOneWidget);
      for (final title in [
        'Thành phần dinh dưỡng',
        'Vitamin & khoáng chất',
        'Phù hợp với',
        'Cần lưu ý / Không phù hợp với',
        'Món gợi ý',
        'Công thức có nguyên liệu này',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Đạm'), findsOneWidget);
      expect(find.text('25,8 g'), findsOneWidget);
      expect(find.text('Thêm vào tủ'), findsOneWidget);
      expect(find.textContaining('USDA'), findsOneWidget);
      expect(find.textContaining('không thay thế tư vấn y tế'), findsOneWidget);
      await tester.tap(find.text('Thêm vào tủ'));
      await _wait(tester, 1000);
      expect(find.text('Đã có trong tủ'), findsOneWidget);
      // Recipes open the recipe screen.
      final recipe = find.descendant(
          of: find.byType(ListTile),
          matching: find.textContaining('đậu phộng'));
      await tester.ensureVisible(recipe.first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(recipe.first);
      await _wait(tester, 1000);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await _wait(tester, 1500);
    });

    testWidgets('"Không nên dùng chung" is labelled "tham khảo"',
        (tester) async {
      await _pump(
          tester,
          const IngredientDetailScreen(
              ingredientId: 'ing_dau_hu', name: 'Đậu hũ'),
          size: const Size(411, 3000));
      await _wait(tester, 3000);
      expect(find.text('Không nên dùng chung'), findsOneWidget);
      expect(find.text('tham khảo'), findsOneWidget);
      expect(find.textContaining('Rau chân vịt:'), findsOneWidget);
      expect(find.textContaining('Bạn đã khai báo dị ứng'), findsNothing);
      await _wait(tester, 1000);
    });

    testWidgets('an ingredient without data says so', (tester) async {
      await _pump(tester, const IngredientDetailScreen(name: 'Nấm mỡ'));
      await _wait(tester, 2500);
      expect(find.text('Chưa có dữ liệu dinh dưỡng cho nguyên liệu này'),
          findsOneWidget);
      await _wait(tester, 1000);
    });
  });
}
