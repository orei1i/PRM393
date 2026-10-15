// test/fix_bubble_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';

/// Device QA fixes for the "Hỏi AI" bubble:
/// - at rest it is a slim tab inside the screens' 16 dp content padding, so
///   it covers no control (the planner's "+" / "Xoá hết", buttons on the
///   tabs) wherever it rests on the edge;
/// - its rect is excluded from Android's edge Back gesture through
///   `MainActivity`, so dragging it never leaves the app.
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
  final bubble = find.byKey(const ValueKey('ask-ai'));
  final nav = find.byKey(const ValueKey('shell-nav'));

  Future<void> pumpShell(WidgetTester tester,
      {Map<String, Object> prefs = minhAnh, double dpr = 1}) async {
    tester.view
      ..physicalSize = screen * dpr
      ..devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
  }

  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: nav, matching: find.text(label)));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
  }

  /// Anything a finger can trigger: ink, gesture detectors with a tap,
  /// buttons, text fields.
  bool tappable(Widget w) => switch (w) {
        InkResponse(:final onTap, :final onLongPress) =>
          onTap != null || onLongPress != null,
        GestureDetector(:final onTap, :final onLongPress) =>
          onTap != null || onLongPress != null,
        ButtonStyleButton(:final onPressed) => onPressed != null,
        IconButton(:final onPressed) => onPressed != null,
        EditableText() => true,
        _ => false,
      };

  /// On-screen tappable widgets the resting bubble overlaps. Full-bleed
  /// rows (edge to edge: feed posts, list rows) are skipped: the tab only
  /// sits on their outer padding, and the controls inside them are checked
  /// on their own.
  List<String> covered(WidgetTester tester) {
    final tab = tester.getRect(bubble);
    final own = find
        .descendant(of: bubble, matching: find.byWidgetPredicate(tappable))
        .evaluate()
        .toSet();
    final hits = <String>[];
    for (final e in find.byWidgetPredicate(tappable).evaluate()) {
      if (own.contains(e)) continue;
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final r = (box.localToGlobal(Offset.zero) & box.size)
          .intersect(Offset.zero & screen);
      if (r.isEmpty) continue;
      if (r.left <= 0.5 && r.right >= screen.width - 0.5) continue;
      if (r.overlaps(tab)) hits.add('${e.widget.runtimeType} $r');
    }
    return hits;
  }

  group('resting tab', () {
    for (final (prefs, tabs) in [
      (minhAnh, ['Trang chủ', 'Thực đơn', 'Chuyên gia', 'Tôi']),
      (tam, ['Khách hàng']),
    ]) {
      testWidgets('covers no tappable widget on ${tabs.join(', ')}',
          (tester) async {
        await pumpShell(tester, prefs: prefs);
        for (final tab in tabs) {
          await openTab(tester, tab);
          expect(bubble.hitTestable(), findsOneWidget, reason: tab);
          final rect = tester.getRect(bubble);
          // Inside the screens' 16 dp content padding, on the leading edge.
          expect(rect.width, lessThanOrEqualTo(14), reason: tab);
          expect(rect.left, closeTo(0, 0.5), reason: tab);
          expect(covered(tester), isEmpty, reason: '$tab: tab at $rect');
        }
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets(
        'never on the pantry\'s "+" or "Xoá hết", even moved level with them',
        (tester) async {
      await pumpShell(tester);
      await openTab(tester, 'Thực đơn');
      final plannerList = find
          .descendant(
              of: find.byType(MealPlannerScreen),
              matching: find.byType(Scrollable))
          .first;
      final add = find.byTooltip('Thêm vào tủ');
      final clear = find.widgetWithText(TextButton, 'Xoá hết');
      await tester.scrollUntilVisible(add, 300, scrollable: plannerList);
      await settle(tester, 4);

      for (final control in [add, clear]) {
        expect(control.hitTestable(), findsOneWidget);
        // Drag the bubble to the right edge at the control's height (the
        // spot QA saw it on), let it dock there.
        final from = tester.getRect(bubble).center;
        final to = tester.getRect(control).center.dy;
        await tester.dragFrom(
            from, Offset(screen.width - 6 - from.dx, to - from.dy));
        await settle(tester, 12);
        final tab = tester.getRect(bubble);
        final target = tester.getRect(control);
        expect(tab.width, lessThanOrEqualTo(14));
        expect(tab.right, closeTo(screen.width, 0.5));
        expect((tab.center.dy - target.center.dy).abs(), lessThan(1),
            reason: 'level with $target');
        expect(tab.overlaps(target), isFalse,
            reason: 'tab $tab covers $target');
        expect(covered(tester), isEmpty);
        expect(control.hitTestable(), findsOneWidget);
      }
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('system Back gesture exclusion', () {
    Rect logical(Rect physical, double dpr) => Rect.fromLTRB(
        physical.left / dpr,
        physical.top / dpr,
        physical.right / dpr,
        physical.bottom / dpr);

    List<List<Rect>> mockChannel(WidgetTester tester) {
      final calls = <List<Rect>>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(askAiGestureExclusionChannel, (call) async {
        expect(call.method, 'setExclusionRects');
        calls.add([
          for (final m
              in (call.arguments as List).cast<Map<Object?, Object?>>())
            Rect.fromLTRB(
              (m['left']! as int).toDouble(),
              (m['top']! as int).toDouble(),
              (m['right']! as int).toDouble(),
              (m['bottom']! as int).toDouble(),
            ),
        ]);
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(askAiGestureExclusionChannel, null));
      return calls;
    }

    testWidgets(
        'Android: the resting tab, the bubble while dragged (in physical '
        'pixels), nothing while hidden', (tester) async {
      const dpr = 2.0;
      final calls = mockChannel(tester);
      await pumpShell(tester, dpr: dpr);
      await settle(tester);

      // At rest: one rect around the tab, flush with the left edge, well
      // under the 200 dp the system honours per edge.
      expect(calls, isNotEmpty);
      final rects = calls.last;
      expect(rects, hasLength(1));
      var excluded = logical(rects.single, dpr);
      final tab = tester.getRect(bubble);
      expect(excluded.contains(tab.topLeft), isTrue);
      expect(
          excluded.contains(tab.bottomRight - const Offset(0.5, 0.5)), isTrue);
      expect(excluded.left, 0);
      expect(excluded.height, inInclusiveRange(tab.height, 100));

      // Nothing new while nothing moves.
      final idle = calls.length;
      await settle(tester, 4);
      expect(calls.length, idle);

      // Dragging: each frame's rect follows the full bubble.
      final gesture = await tester.startGesture(tab.center);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(20, 25));
        await tester.pump(const Duration(milliseconds: 16));
        final now = tester.getRect(bubble);
        expect(now.shortestSide, greaterThanOrEqualTo(48));
        excluded = logical(calls.last.single, dpr);
        expect(excluded.contains(now.center), isTrue, reason: 'step $i');
        expect(excluded.width, lessThanOrEqualTo(now.width + 17));
        expect(excluded.height, lessThanOrEqualTo(now.height + 17));
      }
      expect(calls.length, greaterThan(idle + 4));
      await gesture.up();

      // Docked again at the new height: the rect moved with it.
      await settle(tester, 12);
      final docked = tester.getRect(bubble);
      expect(docked.width, lessThanOrEqualTo(14));
      expect(docked.top, greaterThan(tab.top + 100));
      excluded = logical(calls.last.single, dpr);
      expect(excluded.contains(docked.center), isTrue);

      // Hidden while the list scrolls: cleared at once.
      final list = find.byType(CustomScrollView).first;
      final scroll = await tester.startGesture(tester.getCenter(list));
      for (var i = 0; i < 12; i++) {
        await scroll.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(calls.last, isEmpty);
      expect(bubble, findsNothing);
      await scroll.up();
      await settle(tester, 4);
      expect(calls.last, hasLength(1));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('no channel traffic on iOS', (tester) async {
      final calls = mockChannel(tester);
      await pumpShell(tester);
      final gesture = await tester.startGesture(tester.getRect(bubble).center);
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(20, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester, 12);
      expect(calls, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
