// test/planner/m4_shell_scan_test.dart
// Split from test/m4_shell_scan_test.dart: the confirm-only scan flow and the
// mock scan scenarios.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/pantry_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/pantry_api_service.dart';
import 'package:veganlife_mobile/features/scanner/data/mock_scanner_repository.dart';
import 'package:veganlife_mobile/features/scanner/data/models/scan_result_model.dart';
import 'package:veganlife_mobile/features/scanner/data/scan_image_source.dart';
import 'package:veganlife_mobile/features/scanner/data/scanner_api_service.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scan_mode_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scanner_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// "Chọn ảnh" without a real gallery.
class _FakeGallery implements ScanImageSource {
  _FakeGallery(this.result);

  final Uint8List? result;
  int calls = 0;

  @override
  Future<Uint8List?> pickFromGallery() async {
    calls++;
    return result;
  }
}

void main() {
  // Real Roboto metrics (shipped with the SDK), as in the "Hỏi AI" test: the
  // default test font draws every glyph as a wide square.
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
    MockCommerceDb.reset();
    MockMealPlannerRepository.reset();
  });

  final scanButton = find.byKey(const ValueKey('scan-button'));

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    Map<String, Object> prefs = _minhAnh,
    double textScale = 1,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(411, 913)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        ...overrides
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const AppShell(),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  int shellTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find
          .descendant(
              of: find.byType(AppShell), matching: find.byType(IndexedStack))
          .first)
      .index!;

  group('confirm-only scan', () {
    testWidgets(
        'no amounts; "Lưu vào tủ lạnh" saves, then "Xem tủ lạnh" shows the '
        'fridge list over the scanner', (tester) async {
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'manual'});
      await tester.tap(scanButton);
      await settle(tester);

      await tester.enterText(
          find.widgetWithText(TextField, 'Thêm nguyên liệu'), 'Nấm mỡ');
      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      expect(find.text('Nấm mỡ'), findsOneWidget);
      expect(find.byTooltip('Tăng'), findsNothing);
      expect(find.byTooltip('Giảm'), findsNothing);
      expect(find.textContaining(' kg'), findsNothing);

      await tester.ensureVisible(find.text('Lưu vào tủ lạnh (1)'));
      await tester.tap(find.text('Lưu vào tủ lạnh (1)'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Đã lưu 1 nguyên liệu vào tủ lạnh'), findsOneWidget);
      expect(find.text('Tạo thực đơn từ tủ lạnh'), findsOneWidget);
      expect(MockPantryRepository.itemsOf('u_me').map((i) => i.ingredient),
          contains('Nấm mỡ'));

      expect(find.text('Xem trong Thực đơn'), findsNothing);
      await tester.ensureVisible(find.text('Xem tủ lạnh'));
      await tester.tap(find.text('Xem tủ lạnh'));
      await settle(tester);
      expect(find.byType(PantryScreen), findsOneWidget);
      // Not in the nutrition DB: listed without made-up figures.
      expect(find.text('Nấm mỡ'), findsOneWidget);
      expect(find.text('Chưa có dữ liệu dinh dưỡng'), findsOneWidget);
      expect(find.text('76 kcal / 100 g · 1 bìa ≈ 114 kcal'), findsOneWidget);

      // Back lands on the scanner, still open.
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(PantryScreen), findsNothing);
      expect(find.byType(IngredientScannerScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        '"Tạo thực đơn từ tủ lạnh" in "Xem tủ lạnh" closes both and shows '
        'Thực đơn', (tester) async {
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'manual'});
      await tester.tap(scanButton);
      await settle(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Thêm nguyên liệu'), 'Cà rốt');
      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      await tester.ensureVisible(find.text('Lưu vào tủ lạnh (1)'));
      await tester.tap(find.text('Lưu vào tủ lạnh (1)'));
      await tester.pump(const Duration(seconds: 2));
      await tester.ensureVisible(find.text('Xem tủ lạnh'));
      await tester.tap(find.text('Xem tủ lạnh'));
      await settle(tester);

      await tester.tap(find.descendant(
          of: find.byType(PantryScreen),
          matching: find.text('Tạo thực đơn từ tủ lạnh')));
      await settle(tester, 3);
      expect(find.text('Tạo lại cả tuần từ tủ lạnh?'), findsOneWidget);
      await tester.tap(find.text('Tạo lại'));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.byType(PantryScreen), findsNothing);
      expect(find.byType(IngredientScannerScreen), findsNothing);
      expect(shellTab(tester), 1);
      expect(
          find.textContaining('ưu tiên nguyên liệu trong tủ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('"Tạo thực đơn từ tủ lạnh" asks, builds the week, opens it',
        (tester) async {
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'manual'});
      await tester.tap(scanButton);
      await settle(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Thêm nguyên liệu'), 'Cà rốt');
      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      await tester.ensureVisible(find.text('Lưu vào tủ lạnh (1)'));
      await tester.tap(find.text('Lưu vào tủ lạnh (1)'));
      await tester.pump(const Duration(seconds: 2));

      await tester.ensureVisible(find.text('Tạo thực đơn từ tủ lạnh'));
      await tester.tap(find.text('Tạo thực đơn từ tủ lạnh'));
      await settle(tester, 3);
      // Minh Anh already has a week: replacing it is confirmed first.
      expect(find.text('Tạo lại cả tuần từ tủ lạnh?'), findsOneWidget);
      await tester.tap(find.text('Tạo lại'));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(find.byType(IngredientScannerScreen), findsNothing);
      expect(shellTab(tester), 1);
      expect(
          find.textContaining('ưu tiên nguyên liệu trong tủ'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('"Chọn ảnh" with an empty gallery offers the sample fridge',
        (tester) async {
      final gallery = _FakeGallery(null);
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'gallery'},
          overrides: [scanImageSourceProvider.overrideWithValue(gallery)]);
      await tester.tap(scanButton);
      await settle(tester);
      expect(gallery.calls, 1);
      expect(find.text('Chưa có ảnh nào được chọn'), findsOneWidget);

      await tester.tap(find.text('Dùng ảnh tủ lạnh mẫu'));
      await tester.pump(const Duration(seconds: 3)); // mock vision
      await settle(tester);
      expect(find.text('Tìm thấy 7 thực phẩm'), findsOneWidget);
      // Low confidence: confirm or remove, nothing else.
      expect(find.text('Rau chân vịt?'), findsWidgets);
      expect(find.text('Xác nhận'), findsWidgets);
      expect(
          find.text('Tìm thấy 7 thực phẩm · 5 thuần chay · 2 không thuần chay '
              '· 1 cần xác nhận'),
          findsOneWidget);
      expect(find.byTooltip('Tăng'), findsNothing);
      // No freshness anywhere: just whether each food is vegan.
      expect(find.textContaining('Tươi'), findsNothing);
      expect(find.textContaining('Dùng sớm'), findsNothing);
      expect(find.text('Thuần chay'), findsWidgets);
      expect(find.text('Không thuần chay'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'sample fridge: non-vegan foods are listed apart with a reason and '
        'swaps, and never saved', (tester) async {
      final gallery = _FakeGallery(null);
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'gallery'},
          overrides: [scanImageSourceProvider.overrideWithValue(gallery)]);
      await tester.tap(scanButton);
      await settle(tester);
      await tester.tap(find.text('Dùng ảnh tủ lạnh mẫu'));
      await tester.pump(const Duration(seconds: 3)); // mock vision
      await settle(tester);

      final tray = find
          .descendant(
              of: find.byType(ScannedIngredientsSheet),
              matching: find.byType(Scrollable))
          .first;
      Future<void> reveal(Finder finder) =>
          tester.scrollUntilVisible(finder, 120, scrollable: tray);

      await reveal(find.text('Không thuần chay — không lưu'));
      await reveal(find.text('Có nguồn gốc động vật: trứng'));
      expect(find.text('Trứng gà'), findsWidgets);
      expect(find.text('Gợi ý thay thế:'), findsWidgets);
      expect(find.widgetWithText(ActionChip, 'Đậu hũ non'), findsOneWidget);
      await reveal(find.text('Chứa sữa bò'));
      expect(find.widgetWithText(ActionChip, 'Sữa hạt'), findsOneWidget);
      // 4 confirmed vegan foods; the eggs, the milk and the unconfirmed
      // spinach are left out.
      await reveal(find.text('Lưu vào tủ lạnh (4)'));
      expect(find.textContaining('không thuần chay sẽ không được lưu'),
          findsOneWidget);

      // A swap joins the vegan list and the count.
      await reveal(find.widgetWithText(ActionChip, 'Đậu hũ non'));
      await tester.tap(find.widgetWithText(ActionChip, 'Đậu hũ non'));
      await tester.pump();
      await reveal(find.text('Lưu vào tủ lạnh (5)'));
      await tester.tap(find.text('Lưu vào tủ lạnh (5)'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Đã lưu 5 nguyên liệu vào tủ lạnh'), findsOneWidget);
      final fridge =
          MockPantryRepository.itemsOf('u_me').map((i) => i.ingredient);
      expect(fridge, containsAll(['Bông cải xanh', 'Cà rốt', 'Đậu hũ non']));
      expect(fridge, isNot(contains('Trứng gà')));
      expect(fridge, isNot(contains('Sữa bò')));
      expect(fridge, isNot(contains('Rau chân vịt')));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'typed non-vegan food: "Không thuần chay — không lưu", nothing to '
        'save until a vegan swap is picked', (tester) async {
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'manual'});
      await tester.tap(scanButton);
      await settle(tester);

      final tray = find
          .descendant(
              of: find.byType(ScannedIngredientsSheet),
              matching: find.byType(Scrollable))
          .first;
      Future<void> revealAbove(Finder finder) =>
          tester.scrollUntilVisible(finder, -120, scrollable: tray);

      await tester.enterText(
          find.widgetWithText(TextField, 'Thêm nguyên liệu'), 'Trứng vịt');
      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 thực phẩm · 1 không thuần chay'), findsOneWidget);
      expect(find.text('Không thuần chay — không lưu'), findsOneWidget);
      expect(find.text('Có nguồn gốc động vật: trứng'), findsOneWidget);
      // Everything is non-vegan: a clear "nothing to save" state, no button.
      await tester
          .ensureVisible(find.text('Chưa có thực phẩm thuần chay để lưu'));
      expect(find.textContaining('Lưu vào tủ lạnh'), findsNothing);

      await tester.ensureVisible(find.widgetWithText(ActionChip, 'Đậu hũ non'));
      await tester.tap(find.widgetWithText(ActionChip, 'Đậu hũ non'));
      await tester.pump();
      expect(find.text('Chưa có thực phẩm thuần chay để lưu'), findsNothing);
      await tester.ensureVisible(find.text('Lưu vào tủ lạnh (1)'));
      expect(find.text('Lưu vào tủ lạnh (1)'), findsOneWidget);
      await revealAbove(
          find.text('2 thực phẩm · 1 thuần chay · 1 không thuần chay'));

      // "Bỏ" removes the non-vegan item.
      await tester.ensureVisible(find.byTooltip('Bỏ trứng vịt'));
      await tester.tap(find.byTooltip('Bỏ trứng vịt'));
      await tester.pump();
      expect(find.text('Không thuần chay — không lưu'), findsNothing);
      await revealAbove(find.text('1 thực phẩm · 1 thuần chay'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a picked photo is analysed on screen', (tester) async {
      final gallery = _FakeGallery(Uint8List.fromList(List.filled(64, 7)));
      await pumpShell(tester,
          prefs: {..._minhAnh, ScanModeController.storageKey: 'gallery'},
          overrides: [scanImageSourceProvider.overrideWithValue(gallery)]);
      await tester.tap(scanButton);
      await settle(tester, 3); // route + picker
      await tester.pump(const Duration(seconds: 2)); // mock vision
      await settle(tester, 3);
      expect(find.text('Tìm thấy 7 thực phẩm'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('mock scan scenarios', () {
    Future<ScannerState> scanWith(String scenario) async {
      final container = ProviderContainer(overrides: [
        scannerApiProvider
            .overrideWithValue(MockScannerRepository(scenario: scenario)),
      ]);
      addTearDown(container.dispose);
      await container
          .read(scannerControllerProvider.notifier)
          .analyze(Uint8List(0));
      return container.read(scannerControllerProvider);
    }

    test('normal / empty / error', () async {
      expect((await scanWith('normal')).status, ScanStatus.detected);
      expect((await scanWith('empty')).status, ScanStatus.empty);
      final error = await scanWith('error');
      expect(error.status, ScanStatus.error);
      expect(error.errorMessage, contains('Không nhận diện được'));
    });

    test('the wire keeps no amounts', () async {
      final result = await MockScannerRepository().scanImage(Uint8List(0));
      for (final item in result.items) {
        expect(item.toJson().containsKey('quantity'), isFalse);
        expect(item.toJson().containsKey('unit'), isFalse);
      }
      // No freshness either: the scan only says what it is and if it's vegan.
      for (final item in result.items) {
        expect(item.toJson().containsKey('freshness'), isFalse);
        expect(item.isVegan, isNotNull);
      }
      // An older server that still sends them (and no `isVegan`) is fine:
      // the local check decides.
      final dto = DetectedIngredientDto.fromJson({
        'id': 'd1',
        'label': 'Đậu hũ',
        'confidence': 0.9,
        'freshness': 'use_soon',
        'quantity': 300,
        'unit': 'g',
      });
      expect(dto.toEntity().name, 'Đậu hũ');
      expect(dto.toEntity().isVegan, isTrue);
      expect(dto.toJson().containsKey('freshness'), isFalse);
    });
  });
}
