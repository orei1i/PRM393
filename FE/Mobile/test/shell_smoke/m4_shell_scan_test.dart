// test/shell_smoke/m4_shell_scan_test.dart
// Split from test/m4_shell_scan_test.dart: the bottom bar and the scan button.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/scanner/domain/scan_mode.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scan_mode_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';

import '../helpers/session_helpers.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

const _tam = {
  'vl.access_token': 'mock.jwt.tam',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
};

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

  final nav = find.byKey(const ValueKey('shell-nav'));
  final scanButton = find.byKey(const ValueKey('scan-button'));
  final aiBubble = find.byKey(const ValueKey('ask-ai'));
  Finder navLabel(String label) =>
      find.descendant(of: nav, matching: find.text(label));

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

  group('bottom bar', () {
    testWidgets(
        'Trang chủ, Thực đơn | big round Quét | Chuyên gia, Tôi; nothing '
        'covered by the button, the "Hỏi AI" bubble kept off both',
        (tester) async {
      await pumpShell(tester);
      for (final label in [
        'Trang chủ',
        'Thực đơn',
        'Quét',
        'Chuyên gia',
        'Tôi'
      ]) {
        expect(navLabel(label), findsOneWidget, reason: label);
      }
      expect(find.byType(NavigationBar), findsNothing,
          reason: '"Quét" is no longer a tab item');

      final scan = tester.getRect(scanButton);
      expect(scan.width, greaterThanOrEqualTo(64));
      expect(scan.height, greaterThanOrEqualTo(64));
      expect((scan.center.dx - 411 / 2).abs(), lessThan(1));
      // Two items on each side, in order.
      final xs = [
        for (final l in ['Trang chủ', 'Thực đơn', 'Chuyên gia', 'Tôi'])
          tester.getCenter(navLabel(l)).dx
      ];
      expect(xs[0] < xs[1] && xs[1] < scan.left, isTrue);
      expect(scan.right < xs[2] && xs[2] < xs[3], isTrue);
      // Raised: it starts well above the other items' icons.
      final homeIcon = tester.getRect(
          find.descendant(of: nav, matching: find.byIcon(Icons.home_rounded)));
      expect(scan.top, lessThan(homeIcon.top - 16));

      // The bar floats over the tab content, which runs behind it; the
      // bar's band includes the raised button and every tab list ends above
      // that band (shell_floating_bar_test.dart). The bubble floats clear of
      // both.
      expect(tester.getRect(nav).top, lessThanOrEqualTo(scan.top + 0.5));
      expect(tester.getRect(find.byType(FeedScreen)).bottom,
          greaterThan(tester.getRect(nav).top));
      final bubble = tester.getRect(aiBubble);
      expect(bubble.overlaps(scan), isFalse);
      expect(bubble.overlaps(tester.getRect(nav)), isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('large text: no overflow, button keeps its size',
        (tester) async {
      await pumpShell(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(navLabel('Quét'), findsOneWidget);
      expect(tester.getSize(scanButton), const Size(64, 64));
      expect(tester.getRect(scanButton).overlaps(tester.getRect(aiBubble)),
          isFalse);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'a chef sees "Chuyên gia" like every member; signing out goes back '
        'to Trang chủ, signing in again keeps the same tabs', (tester) async {
      final container = await pumpShell(tester, prefs: _tam);
      expect(navLabel('Chuyên gia'), findsOneWidget);
      expect(navLabel('Khách hàng'), findsNothing);

      await tester.tap(navLabel('Chuyên gia'));
      await tester.pump(const Duration(seconds: 2));
      expect(shellTab(tester), 2);
      expect(find.byType(ChefDirectoryScreen), findsOneWidget);

      final session = container.read(sessionControllerProvider.notifier);
      await session.signOut();
      await tester.pump(const Duration(seconds: 1));
      expect(shellTab(tester), 0, reason: 'signed out → Trang chủ');
      expect(navLabel('Chuyên gia'), findsOneWidget);

      await tester.tap(navLabel('Chuyên gia'));
      await tester.pump(const Duration(seconds: 2));
      final signIn = signInAs(container, tamChefAccount);
      await tester.pump(const Duration(seconds: 2));
      await signIn;
      await tester.pump(const Duration(seconds: 2));
      expect(container.read(sessionControllerProvider).isChef, isTrue);
      expect(shellTab(tester), 2, reason: 'signing in keeps the tab');
      expect(navLabel('Chuyên gia'), findsOneWidget);
      expect(navLabel('Khách hàng'), findsNothing);
      expect(find.byType(ChefDirectoryScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('scan button', () {
    testWidgets('tap opens the camera scan; long press picks and remembers',
        (tester) async {
      final container = await pumpShell(tester);
      expect(container.read(scanModeProvider), ScanMode.camera);

      await tester.tap(scanButton);
      await settle(tester);
      expect(
          tester
              .widget<IngredientScannerScreen>(
                  find.byType(IngredientScannerScreen))
              .mode,
          ScanMode.camera);
      // The camera plugin never answers in widget tests.
      expect(find.text('Hướng camera vào tủ lạnh'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await settle(tester);
      expect(find.byType(IngredientScannerScreen), findsNothing);

      await tester.longPress(scanButton);
      await settle(tester);
      expect(find.text('Quét tủ lạnh bằng cách nào?'), findsOneWidget);
      for (final label in ['Chụp hình', 'Chọn ảnh', 'Nhập tay']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Đang dùng'), findsOneWidget);
      await tester.tap(find.text('Nhập tay'));
      await settle(tester);
      expect(find.text('Nhập nguyên liệu bằng tay'), findsOneWidget);
      expect(find.text('Nguyên liệu trong tủ'), findsOneWidget);
      final prefs = container.read(sharedPreferencesProvider);
      expect(prefs.getString(ScanModeController.storageKey), 'manual');

      await tester.tap(find.byTooltip('Đóng'));
      await settle(tester);
      expect(
          find.descendant(
              of: scanButton,
              matching: find.byIcon(Icons.keyboard_alt_rounded)),
          findsOneWidget);
      // A plain tap now opens the remembered mode.
      await tester.tap(scanButton);
      await settle(tester);
      expect(
          tester
              .widget<IngredientScannerScreen>(
                  find.byType(IngredientScannerScreen))
              .mode,
          ScanMode.manual);
      await tester.pump(const Duration(seconds: 3));
    });

    test('the remembered mode survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final first = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(first.dispose);
      first.read(scanModeProvider.notifier).remember(ScanMode.gallery);

      final restarted = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(restarted.dispose);
      expect(restarted.read(scanModeProvider), ScanMode.gallery);
      expect(ScanMode.fromStorage('nonsense'), ScanMode.camera);
    });
  });
}
