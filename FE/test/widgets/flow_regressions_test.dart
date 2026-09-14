import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/core/routes/app_shell.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';

Future<AppDependencies> _mount(
  WidgetTester tester,
  String route,
  UserRole role, {
  Size size = const Size(800, 900),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final d = AppDependencies();
  d.auth.switchRole(role);
  d.theme.setMode(dark ? ThemeMode.dark : ThemeMode.light);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    d.dispose();
  });
  await tester.pumpWidget(
    VeganLifeApp(dependencies: d, initialLocation: route),
  );
  await tester.pumpAndSettle();
  return d;
}

GoRouter _router(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppShell)));

void main() {
  for (final (size, scale) in [
    (const Size(800, 360), 1.0),
    (const Size(360, 640), 1.6),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Auth is scrollable and sign-in works at $size scale $scale dark=$dark',
        (tester) async {
          final d = await _mount(
            tester,
            '/trial',
            UserRole.guest,
            size: size,
            scale: scale,
            dark: dark,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'Trial layout before opening auth',
          );
          await tester.ensureVisible(find.text('Join'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Join'));
          await tester.pumpAndSettle();
          final button = find.text('Continue as demo member');
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(d.auth.role, UserRole.member);
          expect(
            _router(tester).routeInformationProvider.value.uri.path,
            '/community',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Chat composer and auth remain reachable with keyboard insets', (
    tester,
  ) async {
    final d = await _mount(
      tester,
      '/trial',
      UserRole.guest,
      size: const Size(360, 800),
      scale: 1.6,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      'Tofu\nRice\nSpinach\nLentils',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Send question'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Send question').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Join us'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue as demo member'));
    await tester.pumpAndSettle();
    expect(find.text('Continue as demo member').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Continue as demo member'));
    await tester.pumpAndSettle();
    expect(d.auth.role, UserRole.member);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('Video controls work at 360px and large text dark=$dark', (
      tester,
    ) async {
      await _mount(
        tester,
        '/video/p3',
        UserRole.guest,
        size: const Size(360, 800),
        scale: 1.6,
        dark: dark,
      );
      await tester.ensureVisible(find.byTooltip('Play demo'));
      await tester.tap(find.byTooltip('Play demo'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('00:03 / 04:32'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause demo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final (route, role, index) in [
    ('/bmi', UserRole.member, 2),
    ('/my-content', UserRole.member, 4),
    ('/edit/p2', UserRole.member, 4),
    ('/post/p1', UserRole.admin, 1),
    ('/video/p3', UserRole.guest, 0),
  ]) {
    testWidgets(
      '$route belongs to the correct navigation section for ${role.name}',
      (tester) async {
        await _mount(tester, route, role);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          index,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Wide navigation rail uses the same section ownership', (
    tester,
  ) async {
    await _mount(tester, '/bmi', UserRole.member, size: const Size(1280, 900));
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
    );
  });

  testWidgets('Publishing then Back returns to the member feed', (
    tester,
  ) async {
    await _mount(tester, '/create', UserRole.member);
    final router = _router(tester);
    final values = [
      'Regression tofu bowl',
      'A delicious plant-based lunch.',
      'Tofu, rice',
      'Cook rice.\nPan-fry tofu.',
    ];
    for (var i = 0; i < values.length; i++) {
      final field = find.byType(TextFormField).at(i);
      await tester.ensureVisible(field);
      await tester.enterText(field, values[i]);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final publish = find.ancestor(
      of: find.text('Publish recipe'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
    expect(publish.hitTestable(), findsOneWidget);
    await tester.tap(publish);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      startsWith('/post/'),
    );
    expect(router.canPop(), isFalse);
    await tester.ensureVisible(find.text('Back'));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/community');
    expect(tester.takeException(), isNull);
  });

  for (final (role, home) in [
    (UserRole.guest, '/explore'),
    (UserRole.admin, '/admin'),
  ]) {
    testWidgets('No-history Back respects ${role.name} home', (tester) async {
      await _mount(tester, '/post/p1', role);
      final router = _router(tester);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, home);
    });
  }

  testWidgets('Ordinary push and Back preserve the previous profile route', (
    tester,
  ) async {
    await _mount(tester, '/my-content', UserRole.member);
    final router = _router(tester);
    router.push('/post/p2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/my-content');
  });

  testWidgets(
    'Returning from invalid BMI shows no planner Retry and keeps shopping',
    (tester) async {
      final d = await _mount(tester, '/planner', UserRole.member);
      final plan = d.planner.plan;
      d.planner.toggleIngredient(d.planner.shopping.first.name);
      final shopping = d.planner.shopping;
      await tester.tap(find.text('BMI reference'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Calculate BMI'));
      await tester.tap(find.text('Calculate BMI'));
      await tester.pumpAndSettle();
      expect(d.planner.bmiError, isNotNull);
      _router(tester).pop();
      await tester.pumpAndSettle();
      expect(find.text(d.planner.bmiError!), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(identical(d.planner.plan, plan), isTrue);
      expect(d.planner.shopping, shopping);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Removed report is retained with no review or approval action', (
    tester,
  ) async {
    final d = await _mount(tester, '/admin/moderation', UserRole.admin);
    d.community.deletePost('p2');
    await tester.pumpAndSettle();
    expect(find.text('Creamy mushroom pasta'), findsNothing);
    await tester.tap(find.text('Resolved'));
    await tester.pumpAndSettle();
    expect(find.text('Creamy mushroom pasta'), findsOneWidget);
    expect(find.text('CONTENT REMOVED'), findsOneWidget);
    expect(find.text('Review content'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
