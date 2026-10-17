// test/shell_smoke/guest_tabs_test.dart
// Guests read Trang chủ and Chuyên gia; Thực đơn, Quét and Tôi ask them to
// sign in. A freshly registered member opens every tab without an error.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/app.dart';
import 'package:veganlife_mobile/core/session/auth_api_service.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/guest_gate.dart';
import 'package:veganlife_mobile/core/widgets/state_views.dart';
import 'package:veganlife_mobile/features/chef/presentation/screens/chef_directory_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';
import 'package:veganlife_mobile/features/scanner/presentation/screens/ingredient_scanner_screen.dart';

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

  setUp(() {
    MockAuthDb.reset();
    MockProfileRepository.reset();
    MockMealPlannerRepository.reset();
  });

  final nav = find.byKey(const ValueKey('shell-nav'));
  final scanButton = find.byKey(const ValueKey('scan-button'));

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(411, 913)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'vl.onboarded': true});
    final sp = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pump(const Duration(seconds: 3)); // mock latency
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: nav, matching: find.text(label)));
    await tester.pump(const Duration(seconds: 3));
  }

  Finder gateIn(Type screen) => find.descendant(
      of: find.byType(screen), matching: find.byType(GuestGate));
  Finder gateButtons(Type screen) => find.descendant(
      of: find.byType(screen),
      matching: find.widgetWithText(FilledButton, 'Đăng nhập'));

  testWidgets(
      'a guest reads Trang chủ and Chuyên gia; the personal tabs and '
      'Quét ask to sign in', (tester) async {
    await pumpShell(tester);
    expect(find.byType(FeedScreen), findsOneWidget);
    expect(gateButtons(FeedScreen), findsNothing);

    await openTab(tester, 'Chuyên gia');
    expect(find.byType(ChefDirectoryScreen), findsOneWidget);
    expect(gateButtons(ChefDirectoryScreen), findsNothing);
    expect(find.byType(ErrorStateView), findsNothing);

    await openTab(tester, 'Thực đơn');
    expect(find.text('Thực đơn 7 ngày của riêng bạn'), findsOneWidget);
    expect(gateButtons(MealPlannerScreen), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MealPlannerScreen),
            matching: find.widgetWithText(OutlinedButton, 'Tạo tài khoản')),
        findsOneWidget);

    await openTab(tester, 'Tôi');
    expect(find.text('Hồ sơ VeganLife của bạn'), findsOneWidget);
    expect(gateButtons(ProfileScreen), findsOneWidget);

    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(gateIn(IngredientScannerScreen), findsOneWidget);
    expect(gateButtons(IngredientScannerScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a freshly registered member opens every tab without an error',
      (tester) async {
    final container = await pumpShell(tester);
    final signUp = container.read(sessionControllerProvider.notifier).register(
        const RegisterRequest(
            fullName: 'Trịnh Mới',
            email: 'trinh.moi@gmail.com',
            password: 'trinhmoi2026'));
    await tester.pump(const Duration(seconds: 2));
    await signUp;
    await tester.pump(const Duration(seconds: 3));

    for (final (tab, screen) in [
      ('Trang chủ', FeedScreen),
      ('Thực đơn', MealPlannerScreen),
      ('Chuyên gia', ChefDirectoryScreen),
      ('Tôi', ProfileScreen),
    ]) {
      await openTab(tester, tab);
      expect(find.byType(screen), findsOneWidget, reason: tab);
      expect(gateButtons(screen), findsNothing, reason: '$tab is open');
      expect(
          find.descendant(
              of: find.byType(screen), matching: find.byType(ErrorStateView)),
          findsNothing,
          reason: tab);
    }
    expect(find.text('Trịnh Mới'), findsWidgets);

    await tester.tap(scanButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(IngredientScannerScreen), findsOneWidget);
    expect(gateButtons(IngredientScannerScreen), findsNothing);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pump(const Duration(seconds: 3));
  });
}
