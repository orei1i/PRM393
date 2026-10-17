// test/planner/m3_widgets_test.dart
// Split from test/m3_widgets_test.dart: HealthProfileEditScreen (body stats,
// energy need, free-text allergies, meals of the day), RecipeDetailScreen
// (tabs) and Thực đơn.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

Future<SharedPreferences> _prefs({bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues(signedIn
      ? {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'}
      : {});
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {bool signedIn = true,
    List<Override> overrides = const [],
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(signedIn: signedIn);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  // Real Roboto metrics (shipped with the SDK), like m0_ask_ai_entry_test:
  // the default test font draws every glyph as a wide square.
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

  group('HealthProfileEditScreen', () {
    Future<void> open(WidgetTester tester,
        {Size size = const Size(411, 900)}) async {
      await _pumpApp(
        tester,
        size: size,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(HealthProfileEditScreen.route()),
                child: const Text('Mở hồ sơ'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở hồ sơ'));
      await _wait(tester);
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    FilledButton save(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu'));

    testWidgets('BMI preview follows typing; validation blocks saving',
        (tester) async {
      await open(tester);
      expect(save(tester).onPressed, isNull, reason: 'nothing changed yet');

      await tester.enterText(field('Chiều cao (cm)'), '170');
      await tester.enterText(field('Cân nặng (kg)'), '65');
      await tester.pump();
      expect(
          find.text('BMI 22,5 · Bình thường (chuẩn châu Á)'), findsOneWidget);
      await tester.enterText(field('Cân nặng (kg)'), '60');
      await tester.pump();
      expect(
          find.text('BMI 20,8 · Bình thường (chuẩn châu Á)'), findsOneWidget);

      await tester.enterText(field('Chiều cao (cm)'), '90');
      await tester.pump();
      expect(find.text('Chiều cao từ 100 đến 230 cm'), findsOneWidget);
      expect(find.text('Nhập chiều cao và cân nặng hợp lệ để xem BMI'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.text('Hồ sơ sức khoẻ'), findsOneWidget, reason: 'blocked');

      await tester.enterText(field('Chiều cao (cm)'), '170');
      await tester.enterText(field('Cân nặng (kg)'), '65,55');
      await tester.pump();
      expect(find.text('Cân nặng chỉ lấy 1 chữ số thập phân'), findsOneWidget);
    });

    testWidgets(
        '99.9 kg fails and keeps the input; a valid save offers '
        '"Tạo lại thực đơn"', (tester) async {
      await open(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Cân nặng (kg)'), '99,9');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester, 2000);
      expect(
          find.textContaining('Chưa lưu được hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.text('99,9'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Cân nặng (kg)'), '60');
      // Allergies are typed: "dau nanh" (no accents) suggests Đậu nành.
      final allergy = find.byKey(const ValueKey('allergy-input'));
      await tester.ensureVisible(allergy);
      await tester.enterText(allergy, 'dau nanh');
      await _wait(tester, 750);
      await tester.tap(find.widgetWithText(ListTile, 'Đậu nành'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Đậu nành'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester, 2000);
      expect(find.text('Đã lưu hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.text('Tạo lại thực đơn'), findsOneWidget);
      expect(find.text('Mở hồ sơ'), findsOneWidget, reason: 'popped');
      await _wait(tester, 7000); // snackbar + planner load timers
    });
  });

  group('RecipeDetailScreen', () {
    testWidgets(
        'header, then tabs "Nguyên liệu" / "Cách làm"; related search in '
        'the header', (tester) async {
      await _pumpApp(tester, const RecipeDetailScreen(recipeId: 'l5'),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.text('Bún riêu chay'), findsWidgets);
      expect(find.text('580 kcal / phần'), findsOneWidget);
      expect(find.text('Thuần chay'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Nguyên liệu'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Cách làm'), findsOneWidget);
      // "Nguyên liệu" first: the table "cho 2 phần", no steps yet.
      expect(find.text('cho 2 phần'), findsOneWidget);
      expect(find.text('300 g'), findsOneWidget);
      expect(find.textContaining('Hầm củ cải và bắp ngô'), findsNothing);

      await tester.tap(find.widgetWithText(Tab, 'Cách làm'));
      await _wait(tester, 750);
      expect(find.textContaining('Hầm củ cải và bắp ngô'), findsOneWidget);
      expect(find.text('300 g'), findsNothing);
      expect(find.text('5'), findsOneWidget, reason: 'numbered steps');

      await tester.tap(find.text('Tìm video & quán liên quan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(
          tester.widget<SearchScreen>(find.byType(SearchScreen)).initialQuery,
          'Bún riêu chay');
      // SearchScreen runs the real mock search now; let its delayed calls finish.
      await _wait(tester, 3000);
    });

    testWidgets('an ingredient row in the nutrition DB opens its detail',
        (tester) async {
      await _pumpApp(tester, const RecipeDetailScreen(recipeId: 'l5'),
          size: const Size(411, 2400));
      await _wait(tester, 2500); // the recipe, then the nutrition DB index
      // "Cà chua" (ing_ca_chua) is in the DB; "Bún tươi" is not.
      expect(
          find.descendant(
              of: find
                  .ancestor(
                      of: find.text('Bún tươi'), matching: find.byType(Row))
                  .first,
              matching: find.byIcon(Icons.chevron_right_rounded)),
          findsNothing);
      await tester.tap(find.text('Cà chua'));
      await tester.pump();
      await _wait(tester, 1500);
      expect(find.byType(IngredientDetailScreen), findsOneWidget);
      expect(find.text('18 kcal / 100 g · 1 quả ≈ 22 kcal'), findsOneWidget);
      await _wait(tester, 1500); // fridge + allergies load behind it
    });

    testWidgets('an unknown id shows "Không tìm thấy công thức"',
        (tester) async {
      await _pumpApp(tester,
          const RecipeDetailScreen(recipeId: 'khong_co', name: 'Món lạ'));
      expect(find.text('Món lạ'), findsOneWidget,
          reason: 'title while loading');
      await _wait(tester);
      expect(find.text('Không tìm thấy công thức'), findsOneWidget);
    });
  });

  testWidgets('Thực đơn: fill a slot from a chef suggestion and by hand',
      (tester) async {
    await _pumpApp(tester, const MealPlannerScreen(),
        size: const Size(411, 2600));
    await _wait(tester, 3000);
    // The fridge is a compact card here; the list has its own screen.
    expect(find.text('Nguyên liệu trong tủ'), findsOneWidget);
    expect(find.text('4 nguyên liệu'), findsOneWidget);
    expect(find.text('Đậu hũ, Cà chua, Nấm rơm, Gạo lứt'), findsOneWidget);
    expect(find.text('Xem tủ lạnh'), findsOneWidget);
    expect(find.text('Tạo thực đơn từ tủ lạnh'), findsWidgets);
    expect(find.byTooltip('Thêm vào tủ'), findsNothing);

    await tester.tap(find.byTooltip('Đổi bữa sáng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    Finder tab(String label) =>
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    for (final label in [
      'AI gợi ý',
      'Công thức của tôi',
      'Từ chuyên gia',
      'Tự nhập món'
    ]) {
      expect(tab(label), findsOneWidget, reason: label);
    }
    await tester.tap(tab('Từ chuyên gia'));
    await _wait(tester);
    await tester.tap(find.text('Cháo yến mạch hạt sen táo đỏ'));
    await _wait(tester);
    expect(find.text('Cháo yến mạch hạt sen táo đỏ'), findsOneWidget);
    expect(find.text('Chuyên gia · Lê Quang Tâm'), findsOneWidget);

    await tester.tap(find.byTooltip('Đổi bữa trưa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(tab('Tự nhập món'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên món'), 'Cơm tấm chay nhà làm');
    await tester.tap(find.text('Thêm vào bữa trưa'));
    await _wait(tester);
    expect(find.text('Cơm tấm chay nhà làm'), findsOneWidget);
    expect(find.text('Tự nhập'), findsOneWidget);
    expect(find.textContaining('Chưa rõ kcal', findRichText: true),
        findsOneWidget);
    await _wait(tester, 6000); // snackbars

    // "Xem tủ lạnh" opens the fridge list.
    await tester.ensureVisible(find.text('Xem tủ lạnh'));
    await tester.tap(find.text('Xem tủ lạnh'));
    await tester.pump();
    await _wait(tester, 1000);
    expect(find.byType(PantryScreen), findsOneWidget);
    expect(find.text('76 kcal / 100 g · 1 bìa ≈ 114 kcal'), findsOneWidget);
    await _wait(tester, 1000);
  });
}
