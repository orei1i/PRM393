import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';

void main() {
  const cases = [
    ('/explore', UserRole.guest, 'tofu'),
    ('/community', UserRole.member, 'lentils'),
    ('/assistant', UserRole.member, 'My unfinished question'),
    ('/planner', UserRole.member, 'tofu, spinach'),
    ('/discover', UserRole.member, 'Grocery'),
    ('/bmi', UserRole.member, '170'),
  ];
  for (final (route, role, value) in cases) {
    testWidgets('$route restores input when navigating back', (tester) async {
      final d = AppDependencies();
      d.auth.switchRole(role);
      await tester.pumpWidget(
        VeganLifeApp(dependencies: d, initialLocation: route),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(TextField).first));
      await tester.enterText(find.byType(TextField).first, value);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      router.go('/post/p1');
      await tester.pumpAndSettle();
      router.go(route);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        value,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      d.dispose();
    });
  }
}
