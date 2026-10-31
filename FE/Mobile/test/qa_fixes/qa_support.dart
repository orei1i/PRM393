// test/qa_fixes/qa_support.dart
// What the QA regression tests share.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';

const minhAnhSession = <String, Object>{
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
  'vl.onboarded': true,
};

const tamSession = <String, Object>{
  'vl.access_token': 'mock.jwt.tam',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
  'vl.onboarded': true,
};

/// A container with [session] saved on the device.
Future<ProviderContainer> qaContainer(
    {Map<String, Object> session = minhAnhSession}) async {
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  return container;
}

/// [home] in a plain app on the mock modules. Returns the screen's container.
Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  Widget home, {
  Map<String, Object> session = minhAnhSession,
  Size size = const Size(411, 2000),
  List<Override> overrides = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  return ProviderScope.containerOf(tester.element(find.byWidget(home)));
}

Future<void> wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Lets the mock's timers finish before the test ends.
Future<void> disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

/// Pumps until [finder] shows, at most [ms].
Future<void> waitFor(WidgetTester tester, Finder finder,
    [int ms = 8000]) async {
  for (var t = 0; t < ms && finder.evaluate().isEmpty; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}
