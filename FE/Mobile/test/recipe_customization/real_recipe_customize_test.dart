// test/recipe_customization/real_recipe_customize_test.dart
// Tester feedback on real BE recipes: customizing one (scaling, swaps within
// role, saving with POST /recipes), the layout of the ingredient rows, and the
// two shortcuts in the app bar and at the top of Thực đơn.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/core/widgets/sign_in_sheet.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/planner_shortcuts.dart';
import 'package:veganlife_mobile/features/recipe/data/backend_recipe_items.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_detail.dart';
import 'package:veganlife_mobile/features/recipe/domain/recipe_customization.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_customization_controller.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_ingredient_row.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/servings_stepper.dart';

import '../hybrid/planner_test_support.dart' as backend;

const _rieuId = '6ae595c796695f5c139fa99b';
const _snackId = '6ae595c796695f5c139fa99c';
const _unknownId = '6ae595c796695f5c139fa99d';

const _rieu = {
  'id': _rieuId,
  'name': 'Bún riêu chay đậu hũ cà chua',
  'calories': 430,
  'proteinG': 19,
  'carbsG': 64,
  'fatG': 11,
  'fiberG': 7,
  'allergens': ['soy'],
  'prepMinutes': 25,
  'ingredients': [
    'Bún tươi',
    'Đậu hũ',
    'Cà chua',
    'Nấm rơm',
    'Sữa đậu nành',
    'Rau muống'
  ],
  'instructions': ['Sơ chế nguyên liệu sạch sẽ.', 'Thưởng thức khi còn nóng.'],
};

const _snack = {
  'id': _snackId,
  'name': 'Sữa hạt điều mè đen ấm',
  'calories': 180,
  'allergens': ['tree_nut', 'sesame'],
  'ingredients': ['Hạt điều', 'Mè đen', 'Nước ấm'],
  'instructions': ['Xay.'],
};

class _Recipes implements RecipeApiService {
  @override
  Future<RecipeDetailDto> getRecipe(String id) async => switch (id) {
        _rieuId => recipeFromBackend(_rieu),
        _snackId => recipeFromBackend(_snack),
        _ => recipeFromBackend({
            'id': id,
            'name': 'Món một thành viên tự viết',
            'calories': 300,
            'ingredients': ['Đậu hũ 200 g'],
            'instructions': ['Nấu.'],
          }),
      };
}

Future<void> _pump(WidgetTester tester, Widget home,
    {Size size = const Size(411, 2600),
    double textScale = 1,
    ThemeData? theme,
    bool signedIn = true,
    List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh',
      'vl.user_id': 'u_me',
      'vl.role': 'User',
    },
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      recipeApiProvider.overrideWithValue(_Recipes()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  ));
  await _wait(tester);
}

Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  // Real Roboto metrics, so the layout checks match a phone.
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
  tearDown(() => BackendModules.debugOverride(null));

  group('the page of a real seed recipe', () {
    testWidgets(
        'servings and swaps are in sight; the BE kcal stands until a swap, '
        'then "≈"; no reviews, notes or sample banner', (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await _pump(tester, const RecipeDetailScreen(recipeId: _rieuId));

      expect(find.byType(ServingsStepper), findsOneWidget);
      expect(find.text(RecipeDetailScreen.readOnlyNote), findsNothing);
      expect(find.text(RecipeDetailScreen.customizeHint), findsOneWidget);
      expect(find.text(RecipeIngredientRow.swapLabel), findsNWidgets(6));
      expect(find.text('430 kcal / phần'), findsOneWidget);
      expect(find.text('Mỗi phần: 430 kcal'), findsOneWidget);
      expect(find.text('Tổng 2 phần: 860 kcal'), findsOneWidget);
      expect(find.text('Đánh giá'), findsNothing);
      expect(find.byType(DemoDataBanner), findsNothing);

      // Family of 4: amounts double, energy per serving doesn't.
      await tester.tap(find.byTooltip('Tăng số người'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tăng số người'));
      await tester.pump();
      expect(find.text('840 g'), findsOneWidget);
      expect(find.text('430 kcal / phần'), findsOneWidget);

      // The riêu is a signature: swapped within its role, never removed.
      expect(find.byTooltip('Bỏ Đậu hũ'), findsNothing);
      expect(find.byTooltip('Bỏ Rau muống'), findsOneWidget);
      final tofu = find.ancestor(
          of: find.text('Đậu hũ'), matching: find.byType(RecipeIngredientRow));
      await tester.tap(find.descendant(
          of: tofu, matching: find.text(RecipeIngredientRow.swapLabel)));
      await _wait(tester, 750);
      expect(find.text('Đổi riêu — giữ đúng món'), findsOneWidget);
      await tester.tap(find.textContaining('Nấm rơm băm nhuyễn'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
      await _wait(tester, 750);

      expect(find.text('Thay cho Đậu hũ'), findsOneWidget);
      expect(find.text('≈ 394 kcal / phần'), findsOneWidget);
      expect(find.text('Năng lượng (ước tính)'), findsOneWidget);
      expect(find.text('Hoàn tác'), findsOneWidget);
      expect(find.text('Lưu thành công thức của tôi'), findsOneWidget);

      await tester.tap(find.text('Cách làm'));
      await tester.pumpAndSettle();
      expect(find.text('Sơ chế nguyên liệu sạch sẽ.'), findsOneWidget);
      expect(find.textContaining('Ghi chú'), findsNothing);
      await _drain(tester);
    });

    testWidgets('"Tổng 1 phần" is not shown next to "Mỗi phần"',
        (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await _pump(tester, const RecipeDetailScreen(recipeId: _snackId));
      expect(find.text('Mỗi phần: 180 kcal'), findsOneWidget);
      expect(find.textContaining('Tổng 1 phần'), findsNothing);
      await tester.tap(find.byTooltip('Tăng số người'));
      await tester.pump();
      expect(find.text('Tổng 2 phần: 360 kcal'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets(
        'a member\'s recipe or an unknown name only reads, and says why',
        (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await _pump(tester, const RecipeDetailScreen(recipeId: _unknownId));
      expect(find.text(RecipeDetailScreen.readOnlyNote), findsOneWidget);
      expect(find.byType(ServingsStepper), findsNothing);
      expect(find.text(RecipeIngredientRow.swapLabel), findsNothing);
      expect(find.text('Lưu thành công thức của tôi'), findsNothing);
      expect(find.text('Thêm vào Thực đơn'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('360 dp, text scale 1,3, dark, a long title: everything fits',
        (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await _pump(tester, const RecipeDetailScreen(recipeId: _rieuId),
          size: const Size(360, 3000), textScale: 1.3, theme: AppTheme.dark());
      expect(tester.takeException(), isNull);
      expect(find.byType(PantryShortcutButton), findsOneWidget);
      expect(find.byType(ChefPlanShortcutButton), findsOneWidget);
      await _drain(tester);
    });
  });

  group('an ingredient row', () {
    Future<double> chevronGap(WidgetTester tester, RecipeIngredient row) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RecipeIngredientRow(
            row: CustomizedRow(original: row, factor: 1),
            onOpen: () {},
          ),
        ),
      ));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      return tester.getRect(find.byType(RecipeIngredientRow)).right -
          chevron.right;
    }

    testWidgets('the chevron sits at the end, with or without an amount',
        (tester) async {
      expect(
          await chevronGap(
              tester, const RecipeIngredient(name: 'Đậu hũ', isFreeText: true)),
          lessThan(10));
      expect(
          await chevronGap(tester,
              const RecipeIngredient(name: 'Đậu hũ', quantity: 200, unit: 'g')),
          lessThan(10));
    });

    testWidgets('the swap button is labelled and reads the ingredient\'s name',
        (tester) async {
      var swapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RecipeIngredientRow(
            row: const CustomizedRow(
              original: RecipeIngredient(
                  name: 'Đậu hũ',
                  quantity: 200,
                  unit: 'g',
                  substitutes: [RecipeSubstitute(key: 'a', name: 'Tempeh')]),
              factor: 1,
            ),
            onSwap: () => swapped = true,
          ),
        ),
      ));
      expect(find.bySemanticsLabel('Đổi Đậu hũ'), findsOneWidget);
      await tester.tap(find.text('Đổi nguyên liệu'));
      expect(swapped, isTrue);
    });
  });

  group('saving a change on the real BE', () {
    const savedId = '6ae5962596695f5c139fa9b6';

    backend.FakeBackend server() => backend.FakeBackend({
          'POST /recipes': (r) {
            final body = r.data as Map<String, dynamic>;
            return (201, backend.envelope({...body, 'id': savedId}));
          },
        });

    Future<ProviderContainer> container(backend.FakeBackend server) async {
      BackendModules.debugOverride(BackendModules.supportedByBackend);
      final c = await backend.backendContainer(server);
      c.listen(recipeCustomizationProvider(_rieuId), (_, __) {});
      return c;
    }

    RecipeDetail page() => recipeFromBackend(_rieu).toEntity();

    test('POST /recipes: name, recalculated figures, rows with amounts',
        () async {
      final fake = server();
      final c = await container(fake);
      final recipe = page();
      final notifier = c.read(recipeCustomizationProvider(_rieuId).notifier);
      notifier.swap(recipe.ingredient('dau_hu')!, 'dau_hu_nam_rom_bam_nhuyen');
      notifier.remove(recipe.ingredient('rau_muong')!);

      final saved = await notifier.saveVariant(recipe, 'Bún riêu của tôi');

      final body = fake.bodyOf('POST /recipes');
      expect(body['name'], 'Bún riêu của tôi');
      expect(body['calories'], saved.caloriesCache);
      expect(body['calories'], lessThan(430));
      expect(body['proteinG'], isNotNull);
      expect(body['fiberG'], isNotNull);
      expect(body['prepMinutes'], 25);
      expect(body['ingredients'], [
        'Bún tươi 420 g',
        'Nấm rơm băm nhuyễn 250 g',
        'Cà chua 200 g',
        'Nấm rơm 100 g',
        'Sữa đậu nành 300 ml',
      ]);
      expect(body['allergens'], ['soy'], reason: 'the soy milk is still there');
      expect(body['instructions'].first,
          savedVariantNote(_rieu['name']! as String, 2));
      expect(fake.calls, ['POST /recipes'],
          reason: 'the BE has no /recipes/{id}/variants');
      expect(saved.id, savedId);
      expect(saved.createdBy, backend.testUserId);
    });

    test('reopened: read back with its origin, signature and options',
        () async {
      final fake = server();
      final c = await container(fake);
      final recipe = page();
      final notifier = c.read(recipeCustomizationProvider(_rieuId).notifier);
      notifier.swap(recipe.ingredient('dau_hu')!, 'dau_hu_nam_rom_bam_nhuyen');
      await notifier.saveVariant(recipe, 'Bún riêu của tôi');
      final stored = fake.bodyOf('POST /recipes');
      fake
        ..on(
            'GET /users/me/recipes',
            200,
            backend.envelope([
              {...stored, 'id': savedId}
            ]))
        ..on('GET /recipes/$savedId', 200,
            backend.envelope({...stored, 'id': savedId}));

      final reopened =
          (await c.read(recipeApiProvider).getRecipe(savedId)).toEntity();
      expect(reopened.createdBy, backend.testUserId);
      expect(reopened.isPublic, isFalse);
      expect(reopened.basedOnName, _rieu['name']);
      expect(reopened.nutritionEstimated, isTrue);
      expect(reopened.servings, 2);
      expect(reopened.steps, _rieu['instructions'],
          reason: 'the note is not a cooking step');
      expect(reopened.isReadOnly, isFalse);
      final swapped = reopened.ingredient('dau_hu')!;
      expect(swapped.name, 'Nấm rơm băm nhuyễn');
      expect(swapped.isSignature, isTrue);
      expect(swapped.substitutes.map((s) => s.name), contains('Đậu hũ'));
      expect(swapped.amount, '250 g');
    });

    test('own recipe named like a seed one is not given the table', () async {
      final fake = server()
        ..on(
            'GET /users/me/recipes',
            200,
            backend.envelope([
              {..._rieu, 'id': savedId},
            ]))
        ..on('GET /recipes/$savedId', 200,
            backend.envelope({..._rieu, 'id': savedId}));
      final c = await container(fake);
      final mine =
          (await c.read(recipeApiProvider).getRecipe(savedId)).toEntity();
      expect(mine.createdBy, backend.testUserId);
      expect(mine.isReadOnly, isTrue);
    });

    test('a failure reaches the caller and saves nothing', () async {
      final fake = backend.FakeBackend()
        ..on('POST /recipes', 500, {'success': false, 'statusCode': 500});
      final c = await container(fake);
      final recipe = page();
      final notifier = c.read(recipeCustomizationProvider(_rieuId).notifier);
      notifier.swap(recipe.ingredient('dau_hu')!, 'dau_hu_nam_rom_bam_nhuyen');
      await expectLater(
          notifier.saveVariant(recipe, 'Bún riêu'), throwsException);
      expect(
          c.read(recipeCustomizationProvider(_rieuId)).savedVariants, isEmpty);
    });
  });

  group('the two shortcuts', () {
    testWidgets('top of Thực đơn: labelled, with tooltips; fits at 360 dp',
        (tester) async {
      await _pump(tester, const Scaffold(body: PlannerShortcutsRow()),
          size: const Size(360, 400), textScale: 1.3, theme: AppTheme.dark());
      expect(find.text('Tủ lạnh của tôi'), findsOneWidget);
      expect(find.text('Nhờ chuyên gia'), findsOneWidget);
      expect(find.byTooltip('Xem nguyên liệu đang có trong tủ lạnh'),
          findsOneWidget);
      expect(find.byTooltip('Nhờ chuyên gia lên thực đơn'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Nhờ chuyên gia lên thực đơn'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });

    testWidgets('the fridge opens the fridge screen', (tester) async {
      await _pump(tester, const Scaffold(body: PlannerShortcutsRow()));
      await tester.tap(find.text('Tủ lạnh của tôi'));
      await _wait(tester);
      expect(find.byType(PantryScreen), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('"Nhờ chuyên gia": guests sign in first', (tester) async {
      await _pump(tester, const Scaffold(body: PlannerShortcutsRow()),
          signedIn: false);
      await tester.tap(find.text('Nhờ chuyên gia'));
      await _wait(tester, 750);
      expect(find.byType(SignInSheet), findsOneWidget);
      expect(find.byType(ChefDirectoryScreen), findsNothing);
      await _drain(tester);
    });

    testWidgets('"Nhờ chuyên gia": members pick a chef, from the recipe page',
        (tester) async {
      await _pump(tester, const RecipeDetailScreen(recipeId: 'l5'));
      await tester.tap(find.byType(ChefPlanShortcutButton));
      await _wait(tester);
      expect(find.text('Chọn chuyên gia'), findsOneWidget);
      await _drain(tester);
    });
  });
}
