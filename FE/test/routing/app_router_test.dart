import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/ai_nutrition/presentation/views/ai_nutrition_chat_view.dart';

void main() {
  for (final route in [
    '/community',
    '/assistant',
    '/planner',
    '/bmi',
    '/discover',
    '/profile',
    '/my-content',
    '/create',
    '/edit/p2',
    '/admin',
    '/admin/moderation',
    '/admin/categories',
    '/admin/ai',
  ]) {
    testWidgets('Guest redirected from $route', (tester) async {
      final d = AppDependencies();
      await tester.pumpWidget(
        VeganLifeApp(dependencies: d, initialLocation: route),
      );
      await tester.pumpAndSettle();
      expect(find.text('A greener kind of everyday.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      d.dispose();
    });
  }
  for (final route in [
    '/admin',
    '/admin/moderation',
    '/admin/categories',
    '/admin/ai',
  ]) {
    testWidgets('Member redirected from $route', (tester) async {
      final d = AppDependencies();
      d.auth.signInAsMember();
      await tester.pumpWidget(
        VeganLifeApp(dependencies: d, initialLocation: route),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your daily dose of green.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      d.dispose();
    });
  }
  testWidgets('Leaving chat cancels an active response', (tester) async {
    final d = AppDependencies(chatTokenDelay: const Duration(milliseconds: 50));
    d.auth.signInAsMember();
    await tester.pumpWidget(
      VeganLifeApp(dependencies: d, initialLocation: '/assistant'),
    );
    await tester.pumpAndSettle();
    final pending = d.chat.submit('protein');
    await tester.pump(const Duration(milliseconds: 60));
    final context = tester.element(find.byType(AiNutritionChatView));
    GoRouter.of(context).go('/community');
    await tester.pumpAndSettle();
    expect(await pending, isFalse);
    expect(d.chat.busy, isFalse);
    expect(d.chat.messages.last.streaming, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    d.dispose();
  });
  for (final id in ['missing', 'p1']) {
    testWidgets('Invalid video $id renders unavailable state', (tester) async {
      final d = AppDependencies();
      await tester.pumpWidget(
        VeganLifeApp(dependencies: d, initialLocation: '/video/$id'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      d.dispose();
    });
  }
}
