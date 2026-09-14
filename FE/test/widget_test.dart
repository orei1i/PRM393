import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';

void main() {
  testWidgets('Guest home renders and role changes redirect', (tester) async {
    final dependencies = AppDependencies();
    await tester.pumpWidget(VeganLifeApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('A greener kind of everyday.'), findsOneWidget);
    dependencies.auth.switchRole(UserRole.member);
    await tester.pumpAndSettle();
    expect(find.text('Your daily dose of green.'), findsOneWidget);
    dependencies.auth.switchRole(UserRole.admin);
    await tester.pumpAndSettle();
    expect(find.text('A healthy community starts here.'), findsOneWidget);
    dependencies.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('A greener kind of everyday.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    dependencies.dispose();
  });
}
