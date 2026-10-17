// test/auth_shell/welcome_test.dart
// First launch: Welcome once (guest, `vl.onboarded` unset), then the shell.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/welcome_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';

Future<SharedPreferences> _pumpApp(WidgetTester tester,
    [Map<String, Object> prefs = const {}]) async {
  tester.view
    ..physicalSize = const Size(411, 913)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    child: const VeganLifeApp(),
  ));
  await tester.pump();
  return sp;
}

/// Mock latency of the shell's tabs (their loads chain: profile → stats).
Future<void> _settleShell(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 3));
}

int _tab(WidgetTester tester) => tester
    .widget<IndexedStack>(find
        .descendant(
            of: find.byType(AppShell), matching: find.byType(IndexedStack))
        .first)
    .index!;

void main() {
  setUp(() {
    MockAuthDb.reset();
    MockMealPlannerRepository.reset();
  });

  testWidgets(
      'a new install opens on Welcome; "Khám phá không cần đăng nhập" goes '
      'to Trang chủ and Welcome never shows again', (tester) async {
    final prefs = await _pumpApp(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.text('Ăn chay khoẻ, dễ dàng mỗi ngày'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    expect(
        find.widgetWithText(OutlinedButton, 'Tạo tài khoản'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);

    await tester.tap(find.text('Khám phá không cần đăng nhập'));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(FeedScreen), findsOneWidget);
    expect(prefs.getBool('vl.onboarded'), isTrue);
    expect(prefs.containsKey('vl.access_token'), isFalse);
    await _settleShell(tester);

    // Next launch.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const VeganLifeApp(),
    ));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    await _settleShell(tester);
  });

  testWidgets('a signed-in install skips Welcome', (tester) async {
    await _pumpApp(tester, {
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh',
      'vl.user_id': 'u_me',
      'vl.role': 'User',
    });
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    await _settleShell(tester);
  });

  testWidgets(
      'signing in from Welcome opens the shell; signing out lands on Trang '
      'chủ as a guest, not on Welcome', (tester) async {
    final prefs = await _pumpApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('Chuyên gia')); // test-account chip
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 2)); // mock latency
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(prefs.getString('vl.user_id'), tamChefAccount.userId);
    await _settleShell(tester);

    // Signed out from Tôi: Trang chủ, guest.
    final nav = find.byKey(const ValueKey('shell-nav'));
    await tester.tap(find.descendant(of: nav, matching: find.text('Tôi')));
    await _settleShell(tester);
    expect(_tab(tester), 3);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await container.read(sessionControllerProvider.notifier).signOut();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(_tab(tester), 0);
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
    await _settleShell(tester);
  });
}
