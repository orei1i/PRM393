// test/recipe_customization/my_recipes_test.dart
// Tôi › "Công thức của tôi": list, empty and error states, create, open. Mock:
// edit in place (with swaps under the signature rule), delete. Real BE: no PUT or
// DELETE, so an edit is an honest new copy through POST /recipes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/core/widgets/guest_gate.dart';
import 'package:veganlife_mobile/core/widgets/state_views.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/mock_recipe_book.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/user_recipe_form_screen.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_recipes_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:veganlife_mobile/features/recipe/data/backend_recipe_items.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/core/network/dio_client.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_ingredient_row.dart';

import '../hybrid/planner_test_support.dart' as backend;

Future<void> _pumpMock(WidgetTester tester, Widget home,
    {Size size = const Size(411, 2400),
    double textScale = 1,
    ThemeData? theme,
    Map<String, Object>? session}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session ??
      {
        'vl.access_token': 'mock.jwt',
        'vl.display_name': 'Minh Anh',
        'vl.user_id': 'u_me',
        'vl.role': 'User',
      });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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

Finder _field(String label) => find.widgetWithText(TextFormField, label);

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

  setUp(() {
    MockMealPlannerRepository.reset();
    MockRecipeCommunityStore.reset();
    MockProfileRepository.reset();
  });
  tearDown(() => BackendModules.debugOverride(null));

  group('with the mock store', () {
    testWidgets('Tôi opens it', (tester) async {
      await _pumpMock(tester, const ProfileScreen());
      await _wait(tester, 3000);
      await tester.tap(find.text('Công thức của tôi'));
      await _wait(tester);
      expect(find.byType(MyRecipesScreen), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('guests see the sign-in gate, no "Tạo công thức"',
        (tester) async {
      await _pumpMock(tester, const MyRecipesScreen(), session: const {});
      await _wait(tester, 500);
      expect(find.byType(GuestGate), findsOneWidget);
      expect(find.byTooltip('Tạo công thức'), findsNothing);
      await _drain(tester);
    });

    testWidgets('empty, create, open, edit in place, delete', (tester) async {
      await _pumpMock(tester, const MyRecipesScreen());
      await _wait(tester);
      expect(find.text('Chưa có công thức nào'), findsOneWidget);
      expect(find.text(MyRecipesScreen.copyNote), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Tạo công thức'));
      await _wait(tester, 750);
      await tester.enterText(_field('Tên món'), 'Canh nấm của tôi');
      await tester.enterText(_field('Năng lượng mỗi phần (kcal)'), '300');
      await tester.enterText(_field('Nguyên liệu 1'), 'Nấm rơm');
      await tester.enterText(_field('Số lượng'), '200');
      await tester.enterText(_field('Đơn vị'), 'g');
      await tester.enterText(_field('Bước 1'), 'Nấu');
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.text('Canh nấm của tôi'), findsOneWidget);
      expect(find.text('300 kcal / phần'), findsOneWidget);

      // Edit in place: same id, one row.
      await tester.tap(find.byTooltip('Tuỳ chọn cho Canh nấm của tôi'));
      await _wait(tester, 500);
      await tester.tap(find.text('Sửa'));
      await _wait(tester);
      expect(find.text('Sửa công thức'), findsOneWidget);
      expect(find.text(UserRecipeFormScreen.copyNote), findsNothing);
      expect(_field('Canh nấm của tôi'), findsOneWidget);
      await tester.enterText(_field('Canh nấm của tôi'), 'Canh nấm mới');
      await tester.enterText(_field('300'), '320');
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.text('Đã lưu thay đổi'), findsOneWidget);
      expect(find.text('Canh nấm mới'), findsOneWidget);
      expect(find.text('320 kcal / phần'), findsOneWidget);
      final rows = MockRecipeBook.userRecipes('u_me');
      expect(rows, hasLength(1));
      expect(rows.single['caloriesCache'], 320);

      // Open.
      await tester.tap(find.text('Canh nấm mới'));
      await _wait(tester, 2500);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      expect(find.text('Sửa công thức'), findsOneWidget);
      await tester.pageBack();
      await _wait(tester, 750);

      // Delete asks first.
      await tester.tap(find.byTooltip('Tuỳ chọn cho Canh nấm mới'));
      await _wait(tester, 500);
      await tester.tap(find.text('Xoá'));
      await _wait(tester, 500);
      expect(find.text('Xoá công thức?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await _wait(tester);
      expect(find.text('Chưa có công thức nào'), findsOneWidget);
      expect(MockRecipeBook.userRecipes('u_me'), isEmpty);
      await _drain(tester);
    });

    testWidgets(
        'a saved variant: swap and save back, the energy follows; a signature '
        'row cannot be removed or typed over', (tester) async {
      final saving = MockRecipeCommunityRepository(userId: 'u_me')
          .createVariant(
              'l5',
              const CreateVariantRequestDto(
                  name: 'Bún riêu của tôi', removed: ['rau_muong']));
      await tester.pump(const Duration(seconds: 2));
      final variant = await saving;
      await _pumpMock(tester, const MyRecipesScreen());
      await _wait(tester);
      await tester.tap(find.byTooltip('Tuỳ chọn cho Bún riêu của tôi'));
      await _wait(tester, 500);
      await tester.tap(find.text('Sửa'));
      await _wait(tester, 2000);

      // "Đậu hũ", the riêu, is text with no field and no ✕.
      expect(find.text('Đậu hũ'), findsOneWidget);
      expect(_field('Đậu hũ'), findsNothing);
      expect(find.textContaining('Thành phần chính'), findsWidgets);
      final tofu = find.ancestor(
          of: find.text('Đậu hũ'),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_IngredientFields'));
      expect(
          find.descendant(of: tofu, matching: find.byIcon(Icons.close_rounded)),
          findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsWidgets,
          reason: 'other rows can go');

      // Swap within the role.
      final tofuSwap = find.descendant(
          of: tofu, matching: find.text(RecipeIngredientRow.swapLabel));
      await tester.ensureVisible(tofuSwap);
      await tester.pump();
      await tester.tap(tofuSwap);
      await _wait(tester, 750);
      expect(find.text('Đổi riêu — giữ đúng món'), findsOneWidget);
      await tester.tap(find.textContaining('Nấm rơm băm nhuyễn'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
      await _wait(tester, 750);
      expect(find.text('Nấm rơm băm nhuyễn'), findsOneWidget);
      expect(find.text(UserRecipeFormScreen.reestimatedNote), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      final row = MockRecipeBook.userRecipes('u_me').single;
      expect(row['id'], variant.id, reason: 'saved back, not a copy');
      expect(row['caloriesCache'], lessThan(variant.caloriesCache!));
      expect(row['basedOnRecipeId'], 'l5');
      final rows =
          (row['ingredients']! as List<Object?>).cast<Map<String, Object?>>();
      final rieu = rows.firstWhere((r) => r['key'] == 'rieu');
      expect(rieu['name'], 'Nấm rơm băm nhuyễn');
      expect(rieu['isSignature'], isTrue);
      expect((rieu['substitutes']! as List<Object?>), isNotEmpty);
      expect(
          (row['customizations']! as List<Object?>)
              .map((c) => (c! as Map<String, Object?>)['to']),
          contains('Nấm rơm băm nhuyễn'));
      await _drain(tester);
    });

    testWidgets('360 dp, text scale 1,3, dark: list and form fit',
        (tester) async {
      MockRecipeBook.addUserRecipe(
          userId: 'u_me',
          userName: 'Minh Anh',
          recipe: {
            'name': 'Một công thức có cái tên thật là dài để thử xuống dòng',
            'caloriesCache': 450,
            'prepMinutes': 25,
          });
      await _pumpMock(tester, const MyRecipesScreen(),
          size: const Size(360, 2000), textScale: 1.3, theme: AppTheme.dark());
      await _wait(tester);
      expect(tester.takeException(), isNull, reason: 'list');
      await tester.tap(find.byTooltip('Tạo công thức'));
      await _wait(tester, 750);
      expect(tester.takeException(), isNull, reason: 'form');
      await _drain(tester);
    });
  });

  group('on the real BE (no PUT or DELETE)', () {
    const savedId = '6ae5962596695f5c139fa9b6';
    const copyId = '6ae5962596695f5c139fa9b7';
    const dish = 'Đậu hũ sốt cà chua & cơm lứt';
    final saved = {
      'id': savedId,
      'name': 'Đậu hũ sốt của tôi',
      'calories': 400,
      'allergens': ['soy'],
      'prepMinutes': 20,
      'ingredients': [
        'Nấm đùi gà 400 g',
        'Cà chua 250 g',
        'Gạo lứt 480 g cơm chín',
      ],
      'instructions': [savedVariantNote(dish, 2), 'Nấu'],
    };

    Future<void> pumpReal(WidgetTester tester, backend.FakeBackend server,
        {Widget home = const MyRecipesScreen()}) async {
      BackendModules.debugOverride(BackendModules.supportedByBackend);
      tester.view
        ..physicalSize = const Size(411, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        SessionController.accessTokenKey: 'test-token',
        'vl.user_id': backend.testUserId,
        'vl.display_name': 'FE Test',
        'vl.role': 'User',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        plannerClockProvider.overrideWithValue(() => backend.testNow),
      ]);
      addTearDown(container.dispose);
      container.read(dioProvider).httpClientAdapter = server;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: MaterialApp(home: home)));
      await _wait(tester);
    }

    backend.FakeBackend server() => backend.FakeBackend({
          'POST /recipes': (r) => (
                201,
                backend
                    .envelope({...r.data as Map<String, dynamic>, 'id': copyId})
              ),
        })
          ..on('GET /users/me/recipes', 200, backend.envelope([saved]))
          ..on('GET /recipes/$savedId', 200, backend.envelope(saved))
          ..on('GET /meal-plans/current', 404, backend.notFound('Chưa có.'))
          ..on('GET /health-profile/me', 404, backend.notFound('Chưa có.'));

    testWidgets('a failed list offers a retry, which works', (tester) async {
      final fake = backend.FakeBackend()
        ..on('GET /users/me/recipes', 500,
            {'success': false, 'statusCode': 500});
      await pumpReal(tester, fake);
      expect(find.byType(ErrorStateView), findsOneWidget);
      fake.on('GET /users/me/recipes', 200, backend.envelope(const <Object>[]));
      await tester.tap(find.text('Thử lại'));
      await _wait(tester);
      expect(find.text('Chưa có công thức nào'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets(
        'says an edit is a new copy; no "Xoá"; the copy goes through POST and '
        'keeps the signature rule', (tester) async {
      final fake = server();
      await pumpReal(tester, fake);
      expect(find.text('Đậu hũ sốt của tôi'), findsOneWidget);
      expect(find.text(MyRecipesScreen.copyNote), findsOneWidget);
      expect(find.text('Xoá'), findsNothing);
      expect(find.byType(PopupMenuButton<Object?>), findsNothing);

      await tester.tap(find.byTooltip('Sửa thành bản mới: Đậu hũ sốt của tôi'));
      await _wait(tester);
      expect(find.text('Sửa thành bản mới'), findsOneWidget);
      expect(find.text(UserRecipeFormScreen.copyNote), findsOneWidget);
      expect(_field('Đậu hũ sốt của tôi (bản mới)'), findsOneWidget);

      // The swapped riêu of the variant: a signature, offered its original.
      expect(find.text('Nấm đùi gà'), findsOneWidget);
      expect(_field('Nấm đùi gà'), findsNothing);
      await tester.tap(find.text(RecipeIngredientRow.swapLabel).first);
      await _wait(tester, 750);
      expect(find.text('Đổi đạm — giữ đúng món'), findsOneWidget);
      await tester.tap(find.textContaining('Tempeh'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Áp dụng'));
      await _wait(tester, 750);

      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.text('Đã lưu thành công thức mới. Bản cũ vẫn còn.'),
          findsOneWidget);

      final body = fake.bodyOf('POST /recipes');
      expect(body['name'], 'Đậu hũ sốt của tôi (bản mới)');
      expect((body['ingredients'] as List).first, 'Tempeh 200 g');
      expect((body['instructions'] as List).first, savedVariantNote(dish, 2));
      expect(fake.calls.where((c) => c.contains('PUT') || c.contains('DELETE')),
          isEmpty);
      await _drain(tester);
    });

    testWidgets('its page has the same honest "Sửa thành bản mới"',
        (tester) async {
      final fake = server();
      await pumpReal(tester, fake,
          home: const RecipeDetailScreen(recipeId: savedId));
      await _wait(tester);
      expect(find.text('Sửa thành bản mới'), findsOneWidget);
      expect(find.text('Biến thể của «$dish»'), findsOneWidget);
      expect(find.text('≈ 400 kcal / phần'), findsOneWidget);
      expect(find.text('Năng lượng (ước tính)'), findsOneWidget);
      await _drain(tester);
    });

    test('the Remote service never calls what the BE does not have', () async {
      final fake = backend.FakeBackend();
      final c = await backend.backendContainer(fake);
      final api = c.read(mealPlannerApiProvider);
      expect(() => api.deleteMyRecipe(savedId), throwsException);
      expect(fake.seen, isEmpty);
      expect(backendRecipeItemsFor(dish), isNotNull);
      expect(recipeFromBackend, isNotNull);
    });
  });
}
