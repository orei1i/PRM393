// test/shell_smoke/status_bar_scrim_test.dart
// Device QA B4: once Trang chủ (or Chuyên gia) scrolls its floating app bar
// away, posts must not run under a transparent status bar. The shell keeps
// an opaque strip in the app bar colour there, with status bar icons that
// suit it in light and dark mode.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/app_theme.dart';
import 'package:veganlife_mobile/core/widgets/app_logo.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';

void main() {
  setUp(MockMealPlannerRepository.reset);

  const screen = Size(411, 913);
  const statusBar = 24.0;
  const minhAnh = {
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  };
  final scrim = find.byKey(const ValueKey('shell-status-bar-scrim'));
  final nav = find.byKey(const ValueKey('shell-nav'));

  Future<void> pumpShell(WidgetTester tester, ThemeData theme) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: statusBar, bottom: 24)
      ..viewPadding = const FakeViewPadding(top: statusBar, bottom: 24);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(minhAnh);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(theme: theme, home: const AppShell()),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
  }

  Future<void> scrollDown(WidgetTester tester, Type screenType) async {
    final list = find.descendant(
        of: find.byType(screenType), matching: find.byType(CustomScrollView));
    for (var i = 0; i < 3; i++) {
      await tester.drag(list.first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  void expectScrim(WidgetTester tester, ThemeData theme) {
    expect(scrim, findsOneWidget);
    expect(tester.getRect(scrim), const Rect.fromLTWH(0, 0, 411, statusBar));
    expect(tester.widget<ColoredBox>(scrim).color,
        theme.appBarTheme.backgroundColor);
    // Drawn over the tabs (a later child of the same Stack).
    final stack = tester.widget<Stack>(
        find.ancestor(of: scrim, matching: find.byType(Stack)).first);
    expect(stack.children.first, isA<IndexedStack>());
    expect(
        find.descendant(
            of: find.byWidget(stack.children.last), matching: scrim),
        findsOneWidget);
  }

  SystemUiOverlayStyle overlayStyle(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.ancestor(
          of: scrim,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)))
      .value;

  testWidgets(
      'light: Trang chủ scrolled past its app bar keeps an opaque status '
      'bar strip with dark icons', (tester) async {
    final theme = AppTheme.light();
    await pumpShell(tester, theme);
    expect(find.byType(VeganLifeLogo).hitTestable(), findsOneWidget);

    await scrollDown(tester, FeedScreen);
    // The floating app bar is gone; the posts reach the top of the screen.
    expect(find.byType(VeganLifeLogo).hitTestable(), findsNothing);
    expectScrim(tester, theme);
    final style = overlayStyle(tester);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
    expect(style.statusBarColor, Colors.transparent);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('dark: light icons on the dark strip, Chuyên gia too',
      (tester) async {
    final theme = AppTheme.dark();
    await pumpShell(tester, theme);
    await scrollDown(tester, FeedScreen);
    expectScrim(tester, theme);
    expect(overlayStyle(tester).statusBarIconBrightness, Brightness.light);

    await tester
        .tap(find.descendant(of: nav, matching: find.text('Chuyên gia')));
    await tester.pump(const Duration(seconds: 3));
    await scrollDown(tester, ChefDirectoryScreen);
    expectScrim(tester, theme);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('touches in the strip reach the tab underneath', (tester) async {
    await pumpShell(tester, AppTheme.light());
    final ignore = tester.widget<IgnorePointer>(
        find.ancestor(of: scrim, matching: find.byType(IgnorePointer)).first);
    expect(ignore.ignoring, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });
}
