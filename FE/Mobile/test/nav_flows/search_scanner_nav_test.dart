// test/nav_flows/search_scanner_nav_test.dart
// WP-C: search results and ingredient pages go back to a recipe already
// open (§6 N10 ingredient side, N11); a dish added from the scanner offers
// "Xem thực đơn" (N12).
@Timeout(Duration(seconds: 180))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/vl_card.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/controllers/scan_mode_controller.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/add_to_plan_sheet.dart';
import 'package:veganlife_mobile/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
  'vl.onboarded': true,
};

/// Search and the recipe / ingredient pages are open to guests; a guest
/// also skips the recipe page's meal-target comparison.
const _guest = {'vl.onboarded': true};

void main() {
  // Real Roboto metrics (shipped with the SDK), as in the shell smoke tests.
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

  Future<ProviderContainer> pumpApp(WidgetTester tester,
      {Map<String, Object> prefs = _minhAnh,
      Size size = const Size(411, 2000)}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const VeganLifeApp(),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> wait(WidgetTester tester, [int seconds = 3]) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  NavigatorState root(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  List<String?> stack(WidgetTester tester) =>
      [for (final r in AppRouteStack.of(root(tester))!.routes) r.settings.name];

  int shownTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find
          .descendant(
              of: find.byType(AppShell), matching: find.byType(IndexedStack))
          .first)
      .index!;

  Future<void> push(WidgetTester tester, Route<Object?> route,
      [int seconds = 3]) async {
    root(tester).push(route);
    await wait(tester, seconds);
  }

  group('N11 search results', () {
    testWidgets('a recipe opens over the search', (tester) async {
      await pumpApp(tester, prefs: _guest);
      await push(tester, SearchScreen.route(initialQuery: 'bun rieu'));
      await tester.tap(find.text('Bún riêu chay').first);
      await wait(tester);
      expect(stack(tester), ['/', '/search', '/recipe/l5']);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await wait(tester);
    });

    testWidgets(
        'the recipe the search was opened from comes back instead of a copy',
        (tester) async {
      await pumpApp(tester, prefs: _guest);
      await push(tester, RecipeDetailScreen.route('l5', name: 'Bún riêu chay'));
      await push(tester, SearchScreen.route(initialQuery: 'bun rieu'));
      expect(stack(tester), ['/', '/recipe/l5', '/search']);

      await tester.tap(find.text('Bún riêu chay').first);
      await wait(tester);
      expect(stack(tester), ['/', '/recipe/l5']);
      expect(find.byType(SearchScreen, skipOffstage: false), findsNothing);
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await wait(tester);
    });
  });

  testWidgets(
      'N10 recipe › ingredient › "Công thức có nguyên liệu này" › the same '
      'recipe goes back to it', (tester) async {
    await pumpApp(tester, prefs: _guest);
    await push(tester, RecipeDetailScreen.route('l5', name: 'Bún riêu chay'));
    await push(tester, IngredientDetailScreen.route(name: 'Cà chua'));
    expect(stack(tester), ['/', '/recipe/l5', '/ingredient/ca chua']);

    // The row under "Công thức có nguyên liệu này" (the dish is also a
    // "Món gợi ý" tag).
    final row = find.widgetWithText(ListTile, 'Bún riêu chay');
    await tester.scrollUntilVisible(row, 200,
        scrollable: find
            .descendant(
                of: find.byType(IngredientDetailScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(row);
    await wait(tester);
    expect(stack(tester), ['/', '/recipe/l5']);
    expect(
        find.byType(IngredientDetailScreen, skipOffstage: false), findsNothing);
    await wait(tester);
  });

  testWidgets(
      'N12 scanner idea › "Thêm vào thực đơn" › "Xem thực đơn" leaves the '
      'scanner for the Thực đơn tab', (tester) async {
    final container = await pumpApp(tester,
        prefs: {..._minhAnh, ScanModeController.storageKey: 'manual'},
        size: const Size(411, 913));
    expect(shownTab(tester), ShellTab.home.index);
    await tester.tap(find.byKey(const ValueKey('scan-button')));
    await wait(tester, 2);
    expect(find.byType(IngredientScannerScreen), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Thêm nguyên liệu'), 'Cà rốt');
    await tester.tap(find.byTooltip('Thêm'));
    await tester.pump();

    final tray = find
        .descendant(
            of: find.byType(ScannedIngredientsSheet),
            matching: find.byType(Scrollable))
        .first;
    Future<void> reveal(Finder finder) =>
        tester.scrollUntilVisible(finder, 120, scrollable: tray);

    final suggest = find.textContaining('Gợi ý món từ nguyên liệu này');
    await reveal(suggest);
    await tester.tap(suggest);
    await wait(tester, 3); // mock AI
    // The idea built around "Cà rốt"; its buttons are inside its card.
    const dish = 'Đậu hũ xào bông cải cà rốt';
    await reveal(find.text(dish));
    final tile =
        find.ancestor(of: find.text(dish), matching: find.byType(VLCard)).first;
    final add =
        find.descendant(of: tile, matching: find.text('Thêm vào thực đơn'));
    await tester.ensureVisible(add);
    await tester.pump();
    expect(find.text('Xem thực đơn'), findsNothing);
    await tester.tap(add);
    await wait(tester, 1);

    final confirm = find.descendant(
        of: find.byType(AddToPlanSheet), matching: find.byType(FilledButton));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await wait(tester, 3);
    expect(find.textContaining('Đã thêm "$dish" vào'), findsOneWidget,
        reason: 'the snackbar is kept');

    final view = find.descendant(of: tile, matching: find.text('Xem thực đơn'));
    expect(view, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('Thêm vào thực đơn')),
        findsNothing);
    await tester.ensureVisible(view);
    await tester.pump();
    await tester.tap(view);
    await wait(tester);
    expect(find.byType(IngredientScannerScreen), findsNothing);
    expect(stack(tester), ['/']);
    expect(container.read(shellTabProvider), ShellTab.planner);
    expect(shownTab(tester), ShellTab.planner.index);
    await wait(tester);
  });
}
