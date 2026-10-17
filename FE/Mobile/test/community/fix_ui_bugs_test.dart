// test/community/fix_ui_bugs_test.dart
// Split from test/fix_ui_bugs_test.dart: regression tests for A17 (screenshots
// in FE/_screenshots/final/mobile).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

Future<SharedPreferences> _prefs([Map<String, Object> values = _minhAnh]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<SharedPreferences> _pump(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> session = _minhAnh,
  Size size = const Size(411, 913),
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(session);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  return prefs;
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Unmounts the tree and lets pending mock timers finish.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  // Real Roboto metrics (shipped with the SDK): the default test font draws
  // every glyph as a wide square, which would make every chip too wide.
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

  // ------------------------------------------------------------------ A17 --
  group('A17 search section headers', () {
    testWidgets('"Xem tất cả quán" sits at the right end of its row',
        (tester) async {
      await _pump(tester, const SearchScreen(initialQuery: 'bun rieu'),
          session: const {}, size: const Size(411, 2400));
      await _wait(tester, 3000);
      final all =
          tester.getRect(find.byKey(const ValueKey('search-all-restaurants')));
      expect(all.right, closeTo(411 - 8, 0.5));
      final title = tester.getRect(find.text('Quán gợi ý'));
      expect(title.left, closeTo(16, 0.5));
      expect(all.left, greaterThan(411 / 2),
          reason: 'not in the middle of the row');
      await _dispose(tester);
    });

    testWidgets('"Xoá lịch sử" too', (tester) async {
      await _pump(tester, const SearchScreen(), session: const {
        'vl.recent_searches': ['phở chay']
      });
      await tester.pump();
      final clear =
          tester.getRect(find.widgetWithText(TextButton, 'Xoá lịch sử'));
      expect(clear.right, closeTo(411 - 16, 0.5));
      await _dispose(tester);
    });

    testWidgets('large text: the action wraps instead of overflowing',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, const SearchScreen(initialQuery: 'bun rieu'),
          session: const {}, size: const Size(360, 2400));
      await _wait(tester, 3000);
      expect(tester.takeException(), isNull);
      final all =
          tester.getRect(find.byKey(const ValueKey('search-all-restaurants')));
      expect(all.right, closeTo(360 - 8, 0.5));
      await _dispose(tester);
    });
  });
}
