// test/integration_advisor/advisor_harness.dart
// Shared set-up for the WP-D integration tests: real Roboto metrics, the
// whole app (or a recipe page) with the planner clock pinned to Thứ Năm
// 29/10/2026 9:00, and the root navigator's route names.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/navigation/app_nav.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';

/// Thursday 29/10/2026, 9:00.
DateTime advisorNow() => DateTime(2026, 10, 29, 9);

/// Minh Anh (member), signed in and past onboarding.
const minhAnhPrefs = <String, Object>{
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
  'vl.onboarded': true,
};

/// A guest past onboarding (search and recipe pages are open to guests).
const guestPrefs = <String, Object>{'vl.onboarded': true};

/// Real Roboto metrics (shipped with the SDK): the default test font draws
/// every glyph as a square, so rows that fit on a phone overflow there.
Future<void> loadRoboto() async {
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
}

/// The whole app ([VeganLifeApp]) for [prefs], after the mock latency.
Future<ProviderContainer> pumpAdvisorApp(WidgetTester tester,
    {Map<String, Object> prefs = minhAnhPrefs,
    Size size = const Size(411, 3000)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      plannerClockProvider.overrideWithValue(advisorNow),
    ],
    child: const VeganLifeApp(),
  ));
  await tester.pump(const Duration(seconds: 3)); // mock latency
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Taps [finder], then lets [ms] of mock latency pass.
Future<void> tapAndSettle(WidgetTester tester, Finder finder,
    [int ms = 600]) async {
  await tester.tap(finder);
  await settle(tester, ms);
}

NavigatorState rootNavigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

/// Names of the root navigator's routes, bottom (`/`, the shell) first.
List<String?> routeNames(WidgetTester tester) => [
      for (final r in AppRouteStack.of(rootNavigator(tester))!.routes)
        r.settings.name
    ];

/// Pushes [route] on the root navigator and lets [ms] pass.
Future<void> pushRoute(WidgetTester tester, Route<Object?> route,
    [int ms = 3000]) async {
  rootNavigator(tester).push(route);
  await settle(tester, ms);
}

/// Android Back once (the top sheet or page, through its `PopScope`).
Future<void> systemBack(WidgetTester tester, [int ms = 1000]) async {
  await tester.binding.handlePopRoute();
  await settle(tester, ms);
}

/// Unmounts the app and lets pending mock timers finish.
Future<void> disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}
