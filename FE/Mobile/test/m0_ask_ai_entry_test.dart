// test/m0_ask_ai_entry_test.dart
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/screens/chat_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';

/// The "Hỏi AI" chat-head bubble: reachable on every tab, resting as a slim
/// tab on the screen edge (never on the tab bar / scan button or the
/// planner's first swap button), opens the assistant in one tap, out of the
/// way while a list scrolls, draggable to either edge with the spot
/// remembered.
void main() {
  // Real Roboto metrics, shipped with the SDK: the default test font draws
  // every glyph as a square, so rows that fit on a phone overflow here.
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

  const screen = Size(411, 913);
  final bubble = find.byKey(const ValueKey('ask-ai'));
  final nav = find.byKey(const ValueKey('shell-nav'));
  final scanButton = find.byKey(const ValueKey('scan-button'));

  Future<SharedPreferences> pumpShell(WidgetTester tester,
      {Map<String, Object> extra = const {}, bool fullApp = false}) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh',
      ...extra
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child:
          fullApp ? const VeganLifeApp() : const MaterialApp(home: AppShell()),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return prefs;
  }

  // Fades, springs and the dock (1.5 s after a move) need a few frames.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: nav, matching: find.text(label)));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    await settle(tester);
  }

  /// Docked: a tab at most 14 dp wide, flush with an edge, ≥ 48 dp tall.
  void expectDocked(WidgetTester tester, {required bool right, String? why}) {
    final r = tester.getRect(bubble);
    expect(r.width, lessThanOrEqualTo(14), reason: why);
    expect(r.height, greaterThanOrEqualTo(48), reason: why);
    if (right) {
      expect(r.right, closeTo(screen.width, 0.5), reason: why);
    } else {
      expect(r.left, closeTo(0, 0.5), reason: why);
    }
  }

  testWidgets(
      'on every tab: a slim edge tab clear of the bar, the scan button and '
      'the first swap button; one tap opens the assistant', (tester) async {
    await pumpShell(tester);
    for (final tab in ['Trang chủ', 'Thực đơn', 'Chuyên gia', 'Tôi']) {
      await openTab(tester, tab);
      expect(bubble.hitTestable(), findsOneWidget, reason: tab);
      // Default spot: the leading edge, where screens keep their padding.
      expectDocked(tester, right: false, why: tab);
      final rest = tester.getRect(bubble);
      expect(rest.overlaps(tester.getRect(nav)), isFalse, reason: tab);
      expect(rest.overlaps(tester.getRect(scanButton)), isFalse, reason: tab);
      // Clear of the bottom-right corner where primary buttons live.
      expect(rest.center.dy, lessThan(screen.height / 2), reason: tab);
      expect(
          find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.key == const ValueKey('ask-ai') &&
              w.properties.label == 'Hỏi AI' &&
              w.properties.button == true),
          findsOneWidget);
      expect(find.byTooltip('Hỏi trợ lý dinh dưỡng AI'), findsOneWidget);
    }

    // Not on Thực đơn's first swap button.
    await openTab(tester, 'Thực đơn');
    final swap = find.byTooltip('Đổi bữa sáng');
    expect(swap, findsOneWidget);
    final rest = tester.getRect(bubble);
    expect(rest.overlaps(tester.getRect(swap)), isFalse,
        reason: 'bubble $rest covers the swap button ${tester.getRect(swap)}');

    // One tap on the slim tab reaches the assistant.
    await tester.tap(bubble.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsOneWidget);
    await settle(tester);
    // Not over the assistant itself.
    expect(bubble, findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('steps aside while a list scrolls, back when it stops',
      (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'Thực đơn');
    final list = find.descendant(
        of: find.byType(MealPlannerScreen),
        matching: find.byType(CustomScrollView));
    expect(bubble, findsOneWidget);

    // A slow drag, the finger slipping back a little before lifting.
    final gesture = await tester.startGesture(tester.getCenter(list),
        kind: PointerDeviceKind.touch);
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(0, -4));
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(bubble, findsNothing);
    await gesture.moveBy(const Offset(0, 3));
    await tester.pump(const Duration(milliseconds: 32));
    await gesture.up();
    await settle(tester);
    expect(bubble, findsOneWidget);
    expectDocked(tester, right: false);

    // A fling hides it until the list settles.
    await tester.fling(list, const Offset(0, -200), 1500);
    await tester.pump(const Duration(milliseconds: 250));
    expect(bubble, findsNothing);
    await settle(tester, 10);
    expect(bubble, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'pulled out of the tab it is a full bubble under the finger; springs '
      'to the nearest edge, docks again, spot remembered', (tester) async {
    final prefs = await pumpShell(tester);
    final start = tester.getRect(bubble);

    // Mid-drag: the full ≥ 48 dp bubble follows the finger.
    final gesture = await tester.startGesture(start.center);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(25, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final finger = start.center + const Offset(250, -200);
    var rect = tester.getRect(bubble);
    expect(rect.shortestSide, greaterThanOrEqualTo(48));
    expect(rect.contains(finger), isTrue, reason: '$rect vs finger $finger');
    await gesture.up();

    // Springs to the right edge as the full bubble, then docks there.
    await settle(tester);
    rect = tester.getRect(bubble);
    expect(rect.right, closeTo(screen.width - 12, 0.5),
        reason: 'snapped to the right edge');
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.top, lessThan(start.top - 150));
    await settle(tester, 6);
    expectDocked(tester, right: true);
    final rightTop = tester.getRect(bubble).top;
    expect(prefs.getString(AskAiBubbleStore.sideKey), 'right');
    final y = prefs.getDouble(AskAiBubbleStore.yKey);
    expect(y, isNotNull);

    // Dragged onto the bar: stops above it (scan button included).
    await tester.drag(bubble.hitTestable(), const Offset(-160, 900));
    await settle(tester, 12);
    rect = tester.getRect(bubble);
    expect(rect.bottom, lessThanOrEqualTo(tester.getRect(nav).top - 8 + 0.5));
    expect(rect.overlaps(tester.getRect(scanButton)), isFalse);
    expect(prefs.getDouble(AskAiBubbleStore.yKey), closeTo(1, 0.001));
    await tester.pump(const Duration(seconds: 3));

    // A restart puts it back where it was left, docked.
    final saved = {
      AskAiBubbleStore.sideKey: 'right',
      AskAiBubbleStore.yKey: y!,
    };
    await tester.pumpWidget(const SizedBox());
    await pumpShell(tester, extra: saved);
    expectDocked(tester, right: true);
    expect(tester.getRect(bubble).top, closeTo(rightTop, 0.5));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('long press: "Ẩn bong bóng" with undo, "Đưa về vị trí mặc định"',
      (tester) async {
    final prefs = await pumpShell(tester, extra: {
      AskAiBubbleStore.sideKey: 'right',
      AskAiBubbleStore.yKey: 0.1,
    });
    expectDocked(tester, right: true);

    await tester.longPress(bubble.hitTestable());
    await settle(tester, 3);
    expect(find.text('Đưa về vị trí mặc định'), findsOneWidget);
    await tester.tap(find.text('Đưa về vị trí mặc định'));
    await settle(tester);
    // Shown full size at the default spot for a moment, then docked there.
    expect(tester.getRect(bubble).left, closeTo(12, 0.5));
    await settle(tester, 8);
    expectDocked(tester, right: false);
    expect(prefs.getString(AskAiBubbleStore.sideKey), 'left');
    expect(prefs.containsKey(AskAiBubbleStore.yKey), isFalse);

    await tester.longPress(bubble.hitTestable());
    await settle(tester, 3);
    await tester.tap(find.text('Ẩn bong bóng'));
    await settle(tester, 3);
    expect(bubble, findsNothing);
    expect(find.text('Hoàn tác'), findsOneWidget);
    await tester.tap(find.text('Hoàn tác'));
    await settle(tester);
    expect(bubble, findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('hidden while the keyboard is up', (tester) async {
    await pumpShell(tester);
    expect(bubble, findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settle(tester, 3);
    expect(bubble, findsNothing);
    tester.view.resetViewInsets();
    await settle(tester, 3);
    expect(bubble, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'in the app: stays over screens pushed from the tabs, not over '
      'full-screen flows or screens marked AskAiBubbleFree', (tester) async {
    await pumpShell(tester, fullApp: true);
    expect(bubble, findsOneWidget);
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);

    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('Chi tiết')))));
    await settle(tester);
    expect(find.text('Chi tiết'), findsOneWidget);
    expect(bubble, findsOneWidget);

    navigator.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            const Scaffold(body: Center(child: Text('Toàn màn hình')))));
    await settle(tester);
    expect(bubble, findsNothing);

    navigator.pop();
    await settle(tester);
    expect(bubble, findsOneWidget);

    // A screen with its main action on the bottom/right edge opts out.
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const AskAiBubbleFree(
            child: Scaffold(body: Center(child: Text('Buổi tư vấn'))))));
    await settle(tester);
    expect(find.text('Buổi tư vấn'), findsOneWidget);
    expect(bubble, findsNothing);
    navigator.pop();
    await settle(tester);
    expect(bubble, findsOneWidget);

    navigator.pop();
    await settle(tester);
    expect(bubble, findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
