// test/hybrid/planner_labels_test.dart
// §9 of the plan, word for word: what the planner, recipe, fridge and scanner
// screens hide and say when the real BE can't do something.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/pantry_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/check_in_sheet.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_picker_sheet.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/recipe_note_card.dart';
import 'package:veganlife_mobile/features/recipe/presentation/widgets/servings_stepper.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/scanner/data/mock_scanner_repository.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';
import 'package:veganlife_mobile/features/scanner/data/scan_image_source.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart';
import 'package:veganlife_mobile/features/scanner/domain/scan_mode.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';

const _realId = '6ae595c796695f5c139fa99b';

class _Recipes implements RecipeApiService {
  @override
  Future<RecipeDetailDto> getRecipe(String id) async =>
      RecipeDetailDto.fromJson({
        'id': id,
        'name': 'Cơm gạo lứt',
        'isVegan': true,
        'calories': 520,
        'proteinG': 26,
        if (id == _realId) ...{
          'ingredients': ['Gạo lứt', 'Đậu hũ 200 g'],
          'instructions': ['Sơ chế', 'Nấu'],
        } else if (id.length == 32)
          'isSnapshot': true,
      });
}

class _NoDishes extends MockScannerRepository {
  _NoDishes() : super(scenario: 'normal');

  @override
  Future<List<MenuSuggestionDto>> generateMenu(
          GenerateMenuRequestDto request) async =>
      const [];
}

class _NoPhoto implements ScanImageSource {
  @override
  Future<Uint8List?> pickFromGallery() async => null;
}

class _Fridge extends MockPantryRepository {
  _Fridge() : super(userId: 'u_me');

  @override
  Future<List<PantryItemDto>> getPantry() async => [
        PantryItemDto(
          id: 'p1',
          ingredient: 'Đậu hũ',
          quantity: 200,
          unit: 'g',
          expiryDate: DateTime.now().add(const Duration(days: 2)),
          allergyWarning: 'Cảnh báo dị ứng: soy, lá lốt',
        ),
        const PantryItemDto(
            id: 'p2', ingredient: 'Gạo lứt', quantity: 1, unit: 'phần'),
        const PantryItemDto(id: 'p3', ingredient: 'Bơ', isVegan: false),
      ];
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(411, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump(const Duration(seconds: 2));
}

/// Unmounts and lets the mock's timers finish.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(MockMealPlannerRepository.reset);
  tearDown(() => BackendModules.debugOverride(null));

  group('recipe page', () {
    Future<void> open(WidgetTester tester, String id) => _pump(
          tester,
          RecipeDetailScreen(recipeId: id),
          overrides: [recipeApiProvider.overrideWithValue(_Recipes())],
        );

    testWidgets('a real recipe only reads', (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await open(tester, _realId);

      expect(find.text(RecipeDetailScreen.readOnlyNote), findsOneWidget);
      expect(find.text('Nguyên liệu'), findsOneWidget);
      expect(find.text('Cách làm'), findsOneWidget);
      expect(find.text('Đánh giá'), findsNothing);
      expect(find.byType(ServingsStepper), findsNothing);
      expect(find.text('Lưu thành công thức của tôi'), findsNothing);
      expect(find.text('Thêm vào Thực đơn'), findsOneWidget);
      expect(find.textContaining('Đậu hũ'), findsOneWidget);
      expect(find.byType(DemoDataBanner), findsNothing);

      await tester.tap(find.text('Cách làm'));
      await tester.pumpAndSettle();
      expect(find.text('Sơ chế'), findsOneWidget);
      expect(find.byType(RecipeNoteCard), findsNothing);
      await _drain(tester);
    });

    testWidgets('only the plan knows the dish', (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await open(tester, '8da78bfdfb3147f0a9d8930ec2354bdc');

      expect(find.text('Món này chưa có chi tiết công thức.'), findsOneWidget);
      expect(find.text('Chưa có danh sách nguyên liệu.'), findsNothing);
      expect(find.text('Sao chép danh sách đi chợ'), findsNothing);
      expect(find.textContaining('520 kcal'), findsWidgets);
      expect(find.text('Thêm vào Thực đơn'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('a mock recipe keeps everything, under the banner',
        (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await open(tester, 'l5');

      expect(find.text(DemoDataBanner.label), findsOneWidget);
      expect(find.byType(ServingsStepper), findsOneWidget);
      expect(find.text('Đánh giá'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('fully mock: no banner', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester, 'l5');
      expect(find.byType(DemoDataBanner), findsNothing);
      expect(find.byType(ServingsStepper), findsOneWidget);
      await _drain(tester);
    });
  });

  group('check-in', () {
    Future<void> open(WidgetTester tester) =>
        _pump(tester, const Scaffold(body: CheckInSheet(heightCm: 172)));

    testWidgets('only the weight is asked, on the real BE', (tester) async {
      BackendModules.debugOverride(BackendModules.supportedByBackend);
      await open(tester);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.textContaining('Vòng eo'), findsNothing);
      expect(find.textContaining('Tỉ lệ mỡ'), findsNothing);
    });

    testWidgets('and with the mock', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('a weight the rules refuse stays in the sheet', (tester) async {
      BackendModules.debugOverride(BackendModules.supportedByBackend);
      await open(tester);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.tap(find.text('Lưu'));
      await tester.pump();
      expect(find.text('Cân nặng từ 30 đến 250 kg'), findsOneWidget);
    });
  });

  group('typed dish', () {
    Future<void> open(WidgetTester tester) async {
      await _pump(
          tester,
          const Scaffold(
              body: MealPickerSheet(slot: MealSlot.lunch, allergies: [])));
      await tester.ensureVisible(find.text('Tự nhập món'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tự nhập món'));
      await tester.pumpAndSettle();
    }

    testWidgets('macro inputs on the real BE', (tester) async {
      BackendModules.debugOverride({BackendModule.planner});
      await open(tester);
      expect(find.text('Đạm (g)'), findsOneWidget);
      expect(find.textContaining('Máy chủ chưa lưu'), findsNothing);
    });

    testWidgets('and with the mock', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester);
      expect(find.text('Đạm (g)'), findsOneWidget);
    });
  });

  group('fridge', () {
    Future<void> open(WidgetTester tester) => _pump(
          tester,
          const PantryScreen(),
          overrides: [pantryApiProvider.overrideWithValue(_Fridge())],
        );

    testWidgets('amount, expiry, warning and the edit sheet on the real BE',
        (tester) async {
      BackendModules.debugOverride({BackendModule.pantry});
      await open(tester);
      expect(find.textContaining('200 g · HSD '), findsOneWidget);
      expect(find.text('Sắp hết hạn'), findsOneWidget);
      expect(find.text('Bạn đã khai báo dị ứng với đậu nành, lá lốt'),
          findsOneWidget,
          reason: 'the app\'s names, not the raw ids of the BE');
      expect(find.textContaining('soy'), findsNothing);
      expect(find.text('Máy chủ ghi: không thuần chay'), findsOneWidget);
      expect(find.textContaining('1 phần'), findsNothing,
          reason: 'the default amount says nothing');

      await tester.tap(find.byTooltip('Sửa số lượng & hạn dùng').first);
      await tester.pumpAndSettle();
      expect(find.text('Số lượng'), findsOneWidget);
      expect(find.text('Đơn vị'), findsOneWidget);
    });

    testWidgets('no edit button with the mock', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester);
      expect(find.byTooltip('Sửa số lượng & hạn dùng'), findsNothing);
    });
  });

  group('scanner, nothing to suggest', () {
    Future<void> open(WidgetTester tester, {required String userId}) async {
      await _pump(
        tester,
        Scaffold(
          body: Stack(children: [
            ScannedIngredientsSheet(onRescan: () {}, onOpenPlanner: () {}),
          ]),
        ),
        overrides: [
          scannerApiProvider.overrideWithValue(_NoDishes()),
          mealPlannerApiProvider
              .overrideWithValue(MockMealPlannerRepository(userId: userId)),
        ],
      );
      final c = ProviderScope.containerOf(
          tester.element(find.byType(ScannedIngredientsSheet)));
      c.read(mealPlanControllerProvider);
      await tester.pump(const Duration(seconds: 3));
      final scanner = c.read(scannerControllerProvider.notifier)
        ..addManual('Cà chua');
      unawaited(scanner.generateMenu());
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('no plan this week: says why, and where to go', (tester) async {
      BackendModules.debugOverride({BackendModule.recipes});
      await open(tester, userId: 'u_new_without_plan');
      expect(find.text(ScannedIngredientsSheet.noPlanNote, skipOffstage: false),
          findsOneWidget);
      expect(find.text('Mở Thực đơn', skipOffstage: false), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('fully mock: not a word about it', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester, userId: 'u_new_without_plan');
      expect(find.text(ScannedIngredientsSheet.noPlanNote, skipOffstage: false),
          findsNothing);
      await _drain(tester);
    });
  });

  group('scanner, empty gallery', () {
    Future<void> open(WidgetTester tester) async {
      await _pump(
        tester,
        const IngredientScannerScreen(mode: ScanMode.gallery),
        overrides: [scanImageSourceProvider.overrideWithValue(_NoPhoto())],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no sample photo to send to a real scanner', (tester) async {
      BackendModules.debugOverride({BackendModule.scanner});
      await open(tester);
      expect(find.text('Bạn có thể chụp bằng camera hoặc nhập tay.'),
          findsOneWidget);
      expect(find.text('Dùng ảnh tủ lạnh mẫu'), findsNothing);
      expect(find.text('Nhập tay'), findsOneWidget);
    });

    testWidgets('with the mock it is offered', (tester) async {
      BackendModules.debugOverride(const {});
      await open(tester);
      expect(find.text('Dùng ảnh tủ lạnh mẫu'), findsOneWidget);
    });
  });
}
