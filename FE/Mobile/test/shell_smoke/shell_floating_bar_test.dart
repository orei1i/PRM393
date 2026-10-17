// test/shell_smoke/shell_floating_bar_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/theme/vl_colors.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

/// The TPBank-style floating bottom bar: a capsule off the screen edges with
/// a notch for the raised scan button, a sliding highlight on the selected
/// tab, the tabs scrolling behind it yet ending above it.
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

  const screen = Size(411, 913);
  const minhAnh = {
    'vl.access_token': 'mock.jwt',
    'vl.display_name': 'Minh Anh',
    'vl.user_id': 'u_me',
    'vl.role': 'User',
  };
  const tam = {
    'vl.access_token': 'mock.jwt.tam',
    'vl.display_name': 'Lê Quang Tâm',
    'vl.user_id': 'u_chef_tam',
    'vl.role': 'Chef',
  };
  final nav = find.byKey(const ValueKey('shell-nav'));
  final capsule = find.byKey(const ValueKey('shell-bar-capsule'));
  final highlight = find.byKey(const ValueKey('shell-nav-highlight'));
  final scanButton = find.byKey(const ValueKey('scan-button'));
  Finder label(String text) =>
      find.descendant(of: nav, matching: find.text(text));
  Finder tabNode(String text) =>
      find.descendant(of: nav, matching: find.bySemanticsLabel(text));

  Future<void> pumpShell(
    WidgetTester tester, {
    Map<String, Object> prefs = minhAnh,
    double textScale = 1,
    double gestureInset = 24,
    ThemeData? theme,
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1
      ..padding = FakeViewPadding(top: 24, bottom: gestureInset)
      ..viewPadding = FakeViewPadding(top: 24, bottom: gestureInset);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: MaterialApp(
        theme: theme,
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
  }

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openTab(WidgetTester tester, String text) async {
    await tester.tap(label(text));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
  }

  testWidgets('a capsule floating off the edges, above the gesture area',
      (tester) async {
    await pumpShell(tester);
    final bar = tester.getRect(capsule);
    expect(bar.left, closeTo(12, 0.5));
    expect(bar.right, closeTo(screen.width - 12, 0.5));
    expect(bar.bottom, closeTo(screen.height - 24 - 8, 0.5));
    expect(bar.height, inInclusiveRange(64, 72));
    // The feed runs behind it.
    expect(
        tester.getRect(find.byType(FeedScreen)).bottom, greaterThan(bar.top));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'the selected highlight slides to the tapped tab, which is announced '
      'as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester);
    Offset pill() => tester.getRect(highlight).center;
    double item(String text) => tester.getCenter(label(text)).dx;

    expect(pill().dx, closeTo(item('Trang chủ'), 1));
    expect(
        tester.getSemantics(tabNode('Trang chủ')),
        containsSemantics(
            label: 'Trang chủ', isButton: true, isSelected: true));

    await tester.tap(label('Tôi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // On its way: past the first tab, not yet at the last.
    expect(pill().dx, greaterThan(item('Trang chủ') + 10));
    expect(pill().dx, lessThan(item('Tôi') - 10));
    await settle(tester);
    expect(pill().dx, closeTo(item('Tôi'), 1));
    expect(tester.getSemantics(tabNode('Tôi')),
        containsSemantics(label: 'Tôi', isButton: true, isSelected: true));
    expect(tester.getSemantics(tabNode('Trang chủ')),
        containsSemantics(isSelected: false));

    // Every tab target is at least 48 x 48.
    for (final text in ['Trang chủ', 'Thực đơn', 'Chuyên gia', 'Tôi']) {
      final size = tester.getSemantics(tabNode(text)).rect.size;
      expect(size.width, greaterThanOrEqualTo(48), reason: text);
      expect(size.height, greaterThanOrEqualTo(48), reason: text);
    }
    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
  });

  testWidgets(
      'notch: the scan button sits centred in it, rising above the capsule, '
      '"Quét" under it inside the bar', (tester) async {
    await pumpShell(tester);
    final bar = tester.getRect(capsule);
    final scan = tester.getRect(scanButton);
    expect(scan.center.dx, closeTo(bar.center.dx, 0.5));
    expect(scan.center.dx, closeTo(screen.width / 2, 0.5));
    expect(scan.top, lessThan(bar.top - 20), reason: 'rises above the bar');
    expect((scan.center.dy - bar.top).abs(), lessThan(8));
    expect(tester.getRect(nav).top, lessThanOrEqualTo(scan.top));

    final shape =
        (tester.widget<DecoratedBox>(capsule).decoration as ShapeDecoration)
            .shape;
    final path = shape.getOuterPath(bar);
    // The button never overlaps the bar's fill: the notch goes round it.
    for (var a = 0; a < 360; a += 10) {
      final p = scan.center +
          Offset.fromDirection(a * 3.14159265 / 180, scan.width / 2 + 1);
      if (bar.contains(p)) {
        expect(path.contains(p), isFalse, reason: 'button edge at $a°');
      }
    }
    expect(path.contains(Offset(scan.center.dx, bar.top + 2)), isFalse);
    // Solid elsewhere: beside the notch, below it, at the ends.
    for (final p in [
      Offset(scan.left - 40, bar.top + 3),
      Offset(scan.right + 40, bar.top + 3),
      Offset(scan.center.dx, bar.bottom - 6),
      Offset(bar.left + 30, bar.center.dy),
      Offset(bar.right - 30, bar.center.dy),
    ]) {
      expect(path.contains(p), isTrue, reason: '$p');
    }
    // Rounded ends: the corners are outside.
    expect(path.contains(bar.topLeft + const Offset(2, 2)), isFalse);

    final quet = tester.getRect(label('Quét'));
    expect(quet.top, greaterThanOrEqualTo(scan.bottom));
    expect(quet.bottom, lessThanOrEqualTo(bar.bottom));
    expect(quet.center.dx, closeTo(scan.center.dx, 1));
    await tester.pump(const Duration(seconds: 3));
  });

  group('every tab scrolls its last item above the bar', () {
    /// Scrolls [screenType]'s main list to its very end (loading more pages
    /// on the way) and returns the lowest text drawn in it.
    Future<double> lastItemBottom(WidgetTester tester, Type screenType,
        {Finder? end}) async {
      final screenFinder = find.byType(screenType);
      final scrollable = find
          .descendant(
              of: screenFinder,
              matching: find.byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down))
          .first;
      // Sections below the fold load when built, so the end can move:
      // stop once it holds still.
      double? lastMax;
      for (var i = 0; i < 25; i++) {
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump(const Duration(seconds: 2));
        final now = tester.state<ScrollableState>(scrollable).position;
        final atEnd = now.pixels >= now.maxScrollExtent - 0.5;
        final still =
            lastMax != null && (now.maxScrollExtent - lastMax).abs() < 0.5;
        lastMax = now.maxScrollExtent;
        if (atEnd && still && (end == null || end.evaluate().isNotEmpty)) {
          break;
        }
      }
      await settle(tester);
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5),
          reason: '$screenType scrolled to its end');
      if (end != null) expect(end, findsOneWidget);
      var bottom = 0.0;
      for (final e in find
          .descendant(of: screenFinder, matching: find.byType(RichText))
          .evaluate()) {
        final box = e.renderObject! as RenderBox;
        final r = box.localToGlobal(Offset.zero) & box.size;
        if (r.top < screen.height) {
          bottom = r.bottom > bottom ? r.bottom : bottom;
        }
      }
      return bottom;
    }

    for (final inset in [24.0, 48.0]) {
      testWidgets('member tabs, gesture inset $inset', (tester) async {
        await pumpShell(tester, gestureInset: inset);
        final barTop = tester.getRect(nav).top;
        expect(barTop, lessThanOrEqualTo(tester.getRect(scanButton).top));
        for (final (tab, type, end) in [
          ('Trang chủ', FeedScreen, find.text('Bạn đã xem hết bài mới')),
          ('Thực đơn', MealPlannerScreen, null),
          ('Chuyên gia', ChefDirectoryScreen, null),
          ('Tôi', ProfileScreen, null),
        ]) {
          await openTab(tester, tab);
          final bottom = await lastItemBottom(tester, type, end: end);
          expect(bottom, greaterThan(0), reason: tab);
          expect(bottom, lessThanOrEqualTo(barTop + 0.5),
              reason: '$tab: last item ends at $bottom, bar at $barTop');
          // Still floating: the tab runs behind the whole bar, down to the
          // screen bottom.
          expect(tester.getRect(find.byType(type)).bottom,
              closeTo(screen.height, 0.5),
              reason: tab);
        }
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('chef sees Chuyên gia', (tester) async {
      await pumpShell(tester, prefs: tam);
      expect(label('Khách hàng'), findsNothing);
      await openTab(tester, 'Chuyên gia');
      final bottom = await lastItemBottom(tester, ChefDirectoryScreen);
      expect(bottom, greaterThan(0));
      expect(bottom, lessThanOrEqualTo(tester.getRect(nav).top + 0.5));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('snackbars show above the bar', (tester) async {
    await pumpShell(tester);
    ScaffoldMessenger.of(tester.element(find.byType(FeedScreen)))
        .showSnackBar(const SnackBar(content: Text('Đã lưu bài viết')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    final snack = tester.getRect(find.byType(SnackBar));
    expect(snack.bottom, lessThanOrEqualTo(tester.getRect(nav).top + 0.5));
    await tester.pump(const Duration(seconds: 5));
  });

  for (final dark in [false, true]) {
    testWidgets(
        'labels fit at text scale 1.3 (${dark ? 'dark' : 'light'}), '
        'selected one in the primary colour', (tester) async {
      final theme = ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: [dark ? VLColors.dark : VLColors.light],
      );
      for (final (prefs, labels) in [
        (minhAnh, ['Trang chủ', 'Thực đơn', 'Quét', 'Chuyên gia', 'Tôi']),
        (tam, ['Trang chủ', 'Thực đơn', 'Quét', 'Chuyên gia', 'Tôi']),
      ]) {
        await pumpShell(tester, prefs: prefs, textScale: 1.3, theme: theme);
        expect(tester.takeException(), isNull);
        final bar = tester.getRect(capsule);
        for (final text in labels) {
          final r = tester.getRect(label(text));
          expect(r.top, greaterThanOrEqualTo(bar.top), reason: text);
          expect(r.bottom, lessThanOrEqualTo(bar.bottom), reason: text);
          expect(r.left, greaterThanOrEqualTo(bar.left), reason: text);
          expect(r.right, lessThanOrEqualTo(bar.right), reason: text);
          // One line (ellipsized if needed).
          expect(r.height, lessThan(2 * 12 * 1.3 * 1.2), reason: text);
        }
        final selected = tester.widget<Text>(label('Trang chủ'));
        expect(selected.style?.color, theme.colorScheme.primary);
        expect(tester.widget<Text>(label('Tôi')).style?.color,
            (dark ? VLColors.dark : VLColors.light).muted);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}
