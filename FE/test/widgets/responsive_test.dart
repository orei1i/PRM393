import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';

void main() {
  const screens = [
    ('Community', '/community', UserRole.member),
    ('Chat', '/assistant', UserRole.member),
    ('Planner', '/planner', UserRole.member),
    ('Dashboard', '/admin', UserRole.admin),
  ];
  for (final (name, route, role) in screens) {
    for (final width in [360.0, 768.0, 1280.0]) {
      for (final dark in [false, true]) {
        testWidgets('$name at ${width}px ${dark ? 'dark' : 'light'}', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final d = AppDependencies();
          d.auth.switchRole(role);
          d.theme.setMode(dark ? ThemeMode.dark : ThemeMode.light);
          await tester.pumpWidget(
            VeganLifeApp(dependencies: d, initialLocation: route),
          );
          for (final scale in [1.0, 1.6]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$name at text scale $scale',
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          d.dispose();
        });
      }
    }
  }
  testWidgets('Guest cannot open protected deep links', (tester) async {
    final d = AppDependencies();
    await tester.pumpWidget(
      VeganLifeApp(dependencies: d, initialLocation: '/admin/ai'),
    );
    await tester.pumpAndSettle();
    expect(find.text('A greener kind of everyday.'), findsOneWidget);
    expect(find.text('Keep AI accountable.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    d.dispose();
  });
}
