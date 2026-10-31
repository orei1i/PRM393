// test/nav_foundation/shell_tab_test.dart
// WP0 / N1: the shell tab lives in shellTabProvider; Android Back on another
// tab goes to Trang chủ, on Trang chủ it leaves the app; AppNav.toShellTab /
// resetTo come back to the same shell.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/scanner/domain/scan_mode.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
  'vl.onboarded': true,
};

void main() {
  // Real Roboto metrics (shipped with the SDK), as in the shell smoke tests:
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

  setUp(() {
    MockCommerceDb.reset();
    MockMealPlannerRepository.reset();
  });

  final nav = find.byKey(const ValueKey('shell-nav'));
  Finder navLabel(String label) =>
      find.descendant(of: nav, matching: find.text(label));

  /// The whole app (MaterialApp with its observers), signed in as Minh Anh.
  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(411, 913)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(_minhAnh);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const VeganLifeApp(),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  NavigatorState rootNavigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  int shownTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find
          .descendant(
              of: find.byType(AppShell), matching: find.byType(IndexedStack))
          .first)
      .index!;

  /// Records `SystemNavigator.pop` (the app closing).
  List<String> recordSystemCalls(WidgetTester tester) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  /// Android Back (the system back button / gesture).
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('the app registers its route stack on the root navigator',
      (tester) async {
    await pumpApp(tester);
    final stack = AppRouteStack.of(rootNavigator(tester));
    expect(stack, isNotNull);
    expect(stack!.routes, hasLength(1));
    expect(stack.routes.single.isFirst, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'Android Back on Thực đơn / Chuyên gia / Tôi selects Trang chủ; on '
      'Trang chủ it leaves the app', (tester) async {
    final container = await pumpApp(tester);
    final calls = recordSystemCalls(tester);
    expect(shownTab(tester), 0);

    for (final (label, tab) in [
      ('Thực đơn', ShellTab.planner),
      ('Chuyên gia', ShellTab.chefs),
      ('Tôi', ShellTab.me),
    ]) {
      await tester.tap(navLabel(label));
      await tester.pump(const Duration(seconds: 3));
      expect(container.read(shellTabProvider), tab, reason: label);
      expect(shownTab(tester), tab.index, reason: label);

      await systemBack(tester);
      expect(container.read(shellTabProvider), ShellTab.home, reason: label);
      expect(shownTab(tester), 0, reason: label);
      expect(calls, isNot(contains('SystemNavigator.pop')), reason: label);
    }

    await systemBack(tester);
    expect(calls, contains('SystemNavigator.pop'));
    expect(find.byType(AppShell), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'Back over a pushed page pops the page and keeps the tab; the next '
      'Back goes to Trang chủ', (tester) async {
    final container = await pumpApp(tester);
    final calls = recordSystemCalls(tester);
    await tester.tap(navLabel('Thực đơn'));
    await tester.pump(const Duration(seconds: 3));

    rootNavigator(tester).push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('trang con'))));
    await settle(tester);
    expect(find.text('trang con'), findsOneWidget);

    await systemBack(tester);
    expect(find.text('trang con'), findsNothing);
    expect(container.read(shellTabProvider), ShellTab.planner);

    await systemBack(tester);
    expect(container.read(shellTabProvider), ShellTab.home);
    expect(calls, isNot(contains('SystemNavigator.pop')));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'toShellTab from a pushed page: back on the same shell, Thực đơn '
      'selected', (tester) async {
    final container = await pumpApp(tester);
    final shell = tester.state(find.byType(AppShell));
    final navigator = rootNavigator(tester);
    final stack = AppRouteStack.of(navigator)!;

    for (final label in ['a', 'b']) {
      navigator.push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/$label'),
        builder: (_) => Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => AppNav.toShellTab(
                    Navigator.of(context), ref, ShellTab.planner),
                child: Text('Xem Thực đơn $label'),
              ),
            ),
          ),
        ),
      ));
      await settle(tester);
    }
    expect(stack.routes, hasLength(3));

    await tester.tap(find.text('Xem Thực đơn b'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(stack.routes, hasLength(1));
    expect(container.read(shellTabProvider), ShellTab.planner);
    expect(shownTab(tester), 1);
    expect(find.byType(MealPlannerScreen), findsOneWidget);
    expect(tester.state(find.byType(AppShell)), same(shell),
        reason: 'the shell (and every tab) keeps its state');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('resetTo keeps the shell and its tab underneath', (tester) async {
    await pumpApp(tester);
    await tester.tap(navLabel('Chuyên gia'));
    await tester.pump(const Duration(seconds: 3));
    final shell = tester.state(find.byType(AppShell));
    final navigator = rootNavigator(tester);
    for (final name in ['/directory', '/profile']) {
      navigator.push(MaterialPageRoute<void>(
          settings: RouteSettings(name: name),
          builder: (_) => Scaffold(body: Text(name))));
      await settle(tester);
    }

    AppNav.resetTo(
        navigator,
        MaterialPageRoute<void>(
            settings: RouteSettings(name: AppRoutes.booking('b_new')),
            builder: (_) => const Scaffold(body: Text('booking'))));
    await settle(tester);
    expect(
        [for (final r in AppRouteStack.of(navigator)!.routes) r.settings.name],
        ['/', '/booking/b_new']);

    navigator.pop();
    await settle(tester);
    expect(find.text('booking'), findsNothing);
    expect(shownTab(tester), 2);
    expect(tester.state(find.byType(AppShell)), same(shell));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the scanner\'s "open the planner" exit still selects Thực đơn',
      (tester) async {
    final container = await pumpApp(tester);
    expect(shownTab(tester), 0);
    await tester.tap(find.byKey(const ValueKey('scan-button')));
    await settle(tester);
    expect(find.byType(IngredientScannerScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(IngredientScannerScreen)))
        .pop(ScannerExit.openPlanner);
    await settle(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(IngredientScannerScreen), findsNothing);
    expect(container.read(shellTabProvider), ShellTab.planner);
    expect(shownTab(tester), 1);
    await tester.pump(const Duration(seconds: 3));
  });
}
