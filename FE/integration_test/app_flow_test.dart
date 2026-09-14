import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vegan_life/src/app.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/core/widgets/app_widgets.dart';
import 'package:vegan_life/src/features/ai_nutrition/presentation/view_models/ai_nutrition_view_model.dart';
import 'package:vegan_life/src/features/meal_planner/presentation/widgets/day_selector.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _waitForResponse(
  WidgetTester tester,
  AiNutritionViewModel viewModel,
) async {
  for (var attempt = 0; attempt < 200 && viewModel.busy; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    viewModel.busy,
    isFalse,
    reason: 'Demo response did not finish in 10 seconds',
  );
  await tester.pumpAndSettle();
}

Finder _dialogField(int index) => find
    .descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    )
    .at(index);

String _dialogText(WidgetTester tester, int index) => tester
    .widget<EditableText>(
      find.descendant(
        of: _dialogField(index),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Guest trial, member contribution and planning, admin review', (
    tester,
  ) async {
    final d = AppDependencies(chatTokenDelay: const Duration(milliseconds: 2));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      d.dispose();
    });
    await tester.pumpWidget(VeganLifeApp(dependencies: d));
    await tester.pumpAndSettle();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Try the assistant'));
    await tester.pumpAndSettle();
    for (final prompt in ['Plant protein ideas', 'Food swaps', 'Vitamin B12']) {
      await tester.enterText(find.byType(TextField).last, prompt);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byTooltip('Send question'));
      await _waitForResponse(tester, d.trialChat);
    }
    expect(d.trialChat.limit.remaining, 0);
    expect(find.text('Continue as demo member'), findsOneWidget);
    await tester.tap(find.text('Continue as demo member'));
    await tester.pumpAndSettle();
    expect(find.text('Your daily dose of green.'), findsOneWidget);
    await binding.takeScreenshot('01-community');

    await tester.tap(find.text('Share a recipe'));
    await tester.pumpAndSettle();
    final values = [
      'Sesame tofu lunch bowl',
      'A simple plant-based bowl for a busy day.',
      'Tofu, Rice, Sesame',
      'Cook rice.\nPan-fry tofu.\nCombine and serve.',
    ];
    for (var i = 0; i < values.length; i++) {
      final field = find.byType(TextFormField).at(i);
      await tester.ensureVisible(field);
      await tester.enterText(field, values[i]);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Publish recipe'));
    expect(find.text(values.first), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Upvote recipe'));
    await tester.tap(find.byTooltip('Upvote recipe'));
    await tester.pumpAndSettle();
    expect(find.text('1 votes'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(
      find.byType(TextField).last,
      'Try toasted sesame for extra flavor.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Post comment'));
    await tester.tap(find.text('Post comment'));
    await tester.pumpAndSettle();
    expect(
      d.community.comments.any(
        (c) => c.text == 'Try toasted sesame for extra flavor.',
      ),
      isTrue,
    );

    await _tapVisible(tester, find.text('Back'));
    expect(find.text('Your daily dose of green.'), findsOneWidget);
    expect(d.community.posts.any((post) => post.title == values.first), isTrue);

    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02-assistant');
    await tester.enterText(
      find.byType(TextField).last,
      'Protein ideas for dinner',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byTooltip('Send question'));
    await _waitForResponse(tester, d.chat);
    expect(d.chat.messages.length, 2);
    expect(d.chat.messages.last.streaming, isFalse);

    await tester.tap(find.text('Meal plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tofu, spinach');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Generate my week'));
    await tester.tap(find.text('Generate my week'));
    await tester.pumpAndSettle();
    expect(d.planner.plan.generation, 1);
    expect(d.planner.plan.days.length, 7);
    await tester.ensureVisible(find.byType(DaySelector));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03-planner');

    final plan = d.planner.plan;
    await _tapVisible(tester, find.byType(FilterChip).first);
    final shopping = d.planner.shopping;
    await _tapVisible(tester, find.text('BMI reference'));
    await _tapVisible(tester, find.text('Calculate BMI'));
    expect(d.planner.bmiError, isNotNull);
    await binding.takeScreenshot('07-bmi-validation');
    await binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(identical(d.planner.plan, plan), isTrue);
    expect(d.planner.shopping, shopping);
    expect(find.text('Retry'), findsNothing);
    expect(find.text(d.planner.bmiError!), findsNothing);

    await _tapVisible(tester, find.text('You'));
    await _tapVisible(tester, find.text('Manage my content'));
    await _tapVisible(tester, find.text('My Comments'));
    final comment = d.profile.comments.first;
    await _tapVisible(tester, find.text('Edit').first);
    await tester.enterText(_dialogField(0), ' ');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Save'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_dialogText(tester, 0), ' ');
    expect(d.profile.comments.first.text, comment.text);
    await tester.enterText(
      _dialogField(0),
      'A corrected comment from the device flow.',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Save'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      d.community.comments.firstWhere((c) => c.id == comment.id).text,
      'A corrected comment from the device flow.',
    );

    await _tapVisible(tester, find.text('My Posts'));
    final reportedPost = find.ancestor(
      of: find.text('Creamy mushroom pasta'),
      matching: find.byType(SurfaceCard),
    );
    await _tapVisible(
      tester,
      find.descendant(of: reportedPost, matching: find.text('Delete')),
    );
    await _tapVisible(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    expect(d.community.find('p2'), isNull);
    expect(
      d.moderation.flags.firstWhere((flag) => flag.id == 'f3').contentRemoved,
      isTrue,
    );
    expect(d.moderation.actions, isEmpty);
    expect(d.dashboardRepository.pendingReports, 2);

    await tester.tap(find.byTooltip('Switch demo role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ADMIN · demo'));
    await tester.pumpAndSettle();
    expect(find.text('A healthy community starts here.'), findsOneWidget);
    await binding.takeScreenshot('04-dashboard');
    await tester.ensureVisible(find.byTooltip('Show data table'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05-activity-chart');
    await tester.tap(find.byTooltip('Show data table'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);

    await tester.tap(find.text('Moderation'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve').first);
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(d.dashboardRepository.pendingReports, 1);
    await _tapVisible(tester, find.text('Resolved'));
    expect(find.text('CONTENT REMOVED'), findsOneWidget);
    await binding.takeScreenshot('08-removed-report');

    await _tapVisible(tester, find.text('AI ops'));
    await _tapVisible(tester, find.text('Manual override').first);
    const replacement =
        'Review all ingredients and consult a registered dietitian when needed.';
    await tester.enterText(_dialogField(0), replacement);
    await tester.enterText(_dialogField(1), 'x');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Apply local override'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_dialogText(tester, 0), replacement);
    expect(_dialogText(tester, 1), 'x');
    await binding.takeScreenshot('09-override-draft');
    await tester.enterText(
      _dialogField(1),
      'Reviewed during the device regression flow',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('Apply local override'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(d.aiOperations.logs.first.overrideText, replacement);

    await _tapVisible(tester, find.byTooltip('Appearance'));
    await _tapVisible(tester, find.text('dark theme'));
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06-dashboard-dark');
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('A greener kind of everyday.'), findsOneWidget);
    expect(d.trialChat.limit.remaining, 0);
    expect(tester.takeException(), isNull);
  });
}
