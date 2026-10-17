// test/shell_smoke/shell_feed_profile_test.dart
// Split from test/shell_feed_profile_test.dart: the "Hỏi AI" bubble on the
// feed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';

void main() {
  testWidgets(
      '"Hỏi AI" bubble steps aside while scrolling, never on the feed end',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pump(const Duration(seconds: 2)); // mock latency
    final ai = find.byKey(const ValueKey('ask-ai'));
    final feed = find.byType(CustomScrollView).first;
    expect(ai, findsOneWidget);

    // The bubble's fade needs a few frames; it returns once scrolling stops.
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    final gesture = await tester.startGesture(tester.getCenter(feed));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(ai, findsNothing);
    await gesture.up();
    await settle();
    expect(ai, findsOneWidget);

    // Scroll to the very end (more pages load on the way): the last line
    // shows above the tab bar and the bubble is not on it.
    final end = find.text('Bạn đã xem hết bài mới');
    for (var i = 0; i < 20 && end.evaluate().isEmpty; i++) {
      await tester.drag(feed, const Offset(0, -2000));
      await tester.pump(const Duration(seconds: 2));
    }
    await tester.drag(feed, const Offset(0, -2000));
    await tester.pump(const Duration(seconds: 2));
    // Full-width posts vary in height, so the list's extent estimate shrinks
    // at the end and it springs back: let that finish.
    await settle();
    await settle();
    expect(ai, findsOneWidget);
    final last = tester.getRect(end);
    expect(last.bottom,
        lessThan(tester.getRect(find.byKey(const ValueKey('shell-nav'))).top));
    expect(last.overlaps(tester.getRect(ai)), isFalse);
    await tester.pump(const Duration(seconds: 3));
  });
}
