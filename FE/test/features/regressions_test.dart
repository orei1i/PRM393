import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';
import 'package:vegan_life/src/features/admin_ai_ops/domain/entities/ai_ops_entities.dart';
import 'package:vegan_life/src/features/admin_moderation/domain/entities/moderation_entities.dart';
import 'package:vegan_life/src/features/community/presentation/view_models/video_player_view_model.dart';
import 'package:vegan_life/src/features/meal_planner/data/repositories/mock_meal_plan_repository.dart';
import 'package:vegan_life/src/features/meal_planner/domain/entities/meal_entities.dart';
import 'package:vegan_life/src/features/meal_planner/presentation/view_models/meal_planner_view_model.dart';

class _FailingPlanRepository extends MockMealPlanRepository {
  bool shouldFail = false;
  @override
  WeeklyMealPlan generate({
    required DateTime weekStart,
    required int generation,
    required List<String> ingredients,
  }) {
    if (shouldFail) throw StateError('Controlled generation failure');
    return super.generate(
      weekStart: weekStart,
      generation: generation,
      ingredients: ingredients,
    );
  }
}

void main() {
  late AppDependencies d;
  setUp(() => d = AppDependencies(chatTokenDelay: Duration.zero));
  tearDown(() => d.dispose());

  test('BMI validation leaves planner and shopping selections unchanged', () {
    d.auth.signInAsMember();
    final vm = d.planner;
    final plan = vm.plan;
    vm.toggleIngredient(vm.shopping.first.name);
    final shopping = vm.shopping;
    expect(vm.calculateBmi(), isFalse);
    expect(vm.bmiError, contains('20 and older'));
    expect(vm.error, isNull);
    expect(vm.busy, isFalse);
    expect(identical(vm.plan, plan), isTrue);
    expect(vm.shopping, shopping);
    d.auth.signOut();
    expect(vm.bmiError, isNull);
    expect(vm.error, isNull);
  });

  test(
    'BMI commands do not clear loading or allow duplicate generation',
    () async {
      d.auth.signInAsMember();
      final vm = d.planner;
      final pending = vm.generate();
      expect(vm.busy, isTrue);
      expect(vm.calculateBmi(), isFalse);
      expect(vm.busy, isTrue);
      vm.setUnit(MeasurementUnit.imperial);
      vm.setAdult(true);
      vm.setHeight('67');
      vm.setWeight('143');
      expect(vm.calculateBmi(), isTrue);
      expect(vm.busy, isTrue);
      await vm.generate();
      await pending;
      expect(vm.plan.generation, 1);
      expect(vm.busy, isFalse);
      expect(vm.bmiError, isNull);
    },
  );

  test('BMI success cannot erase a failed generation or its retry', () async {
    d.auth.signInAsMember();
    final repo = _FailingPlanRepository();
    final vm = MealPlannerViewModel(repo, d.auth);
    addTearDown(vm.dispose);
    repo.shouldFail = true;
    await vm.generate();
    final error = vm.error;
    expect(error, isNotNull);
    vm.setAdult(true);
    vm.setHeight('170');
    vm.setWeight('65');
    expect(vm.calculateBmi(), isTrue);
    expect(vm.error, error);
    expect(vm.bmiError, isNull);
    repo.shouldFail = false;
    await vm.generate();
    expect(vm.error, isNull);
    expect(vm.plan.generation, 1);
  });

  test('Planner refresh preserves the same week and advances on Monday', () {
    d.auth.signInAsMember();
    var now = DateTime(2026, 9, 13, 23, 59);
    final vm = MealPlannerViewModel(
      MockMealPlanRepository(),
      d.auth,
      clock: () => now,
    );
    addTearDown(vm.dispose);
    vm.selectDay(6);
    vm.toggleIngredient(vm.shopping.first.name);
    final plan = vm.plan;
    final shopping = vm.shopping;
    vm.syncCurrentWeek();
    expect(identical(vm.plan, plan), isTrue);
    expect(vm.shopping, shopping);
    expect(vm.selectedIndex, 6);
    now = DateTime(2026, 9, 14);
    vm.syncCurrentWeek();
    expect(vm.plan.days.first.date, DateTime(2026, 9, 14));
    expect(vm.plan.days.last.date, DateTime(2026, 9, 20));
    expect(vm.selectedIndex, 0);
  });

  test('An in-flight generation cannot overwrite the refreshed week', () async {
    d.auth.signInAsMember();
    var now = DateTime(2026, 9, 13);
    final vm = MealPlannerViewModel(
      MockMealPlanRepository(),
      d.auth,
      clock: () => now,
    );
    addTearDown(vm.dispose);
    final pending = vm.generate();
    now = DateTime(2026, 9, 14);
    vm.syncCurrentWeek();
    final refreshed = vm.plan;
    await pending;
    expect(identical(vm.plan, refreshed), isTrue);
    expect(vm.busy, isFalse);
    await vm.generate();
    expect(vm.plan.days.first.date, DateTime(2026, 9, 14));
    expect(vm.plan.generation, 1);
  });

  test(
    'Generation crossing midnight uses the current week even without resume',
    () async {
      d.auth.signInAsMember();
      var now = DateTime(2026, 9, 13, 23, 59);
      final vm = MealPlannerViewModel(
        MockMealPlanRepository(),
        d.auth,
        clock: () => now,
      );
      addTearDown(vm.dispose);
      final pending = vm.generate();
      now = DateTime(2026, 9, 14);
      await pending;
      expect(vm.plan.days.first.date, DateTime(2026, 9, 14));
    },
  );

  test(
    'Owner deletion resolves reports without fabricating moderation actions',
    () {
      d.auth.signInAsMember();
      expect(d.dashboardRepository.pendingReports, 3);
      var notifications = 0;
      final subscription = d.moderation.changes.listen((_) => notifications++);
      addTearDown(subscription.cancel);
      expect(d.profile.deletePost('p2'), isTrue);
      final flag = d.moderation.flags.firstWhere((f) => f.id == 'f3');
      expect(flag.resolved, isTrue);
      expect(flag.contentRemoved, isTrue);
      expect(flag.actionable, isFalse);
      expect(d.dashboardRepository.pendingReports, 2);
      expect(notifications, 1);
      d.auth.switchRole(UserRole.admin);
      for (final decision in ModerationDecision.values) {
        expect(d.moderationVm.act('f3', decision), isFalse);
      }
      expect(d.moderation.actions, isEmpty);
    },
  );

  test('Admin delete records once and marks content unavailable', () {
    d.auth.switchRole(UserRole.admin);
    var notifications = 0;
    final subscription = d.moderation.changes.listen((_) => notifications++);
    addTearDown(subscription.cancel);
    expect(d.moderationVm.act('f1', ModerationDecision.delete), isTrue);
    expect(d.moderation.actions.length, 1);
    expect(d.moderation.flags.first.contentRemoved, isTrue);
    expect(d.dashboardRepository.pendingReports, 2);
    expect(notifications, 1);
    expect(d.moderationVm.act('f1', ModerationDecision.approve), isFalse);
    expect(d.moderation.actions.length, 1);
  });

  test('Deletion after approval preserves the audit history', () {
    d.auth.switchRole(UserRole.admin);
    d.moderationVm.act('f3', ModerationDecision.approve);
    d.auth.signInAsMember();
    d.profile.deletePost('p2');
    expect(d.moderation.flags.last.contentRemoved, isTrue);
    expect(d.moderation.actions.single.decision, ModerationDecision.approve);
    expect(d.dashboardRepository.pendingReports, 2);
  });

  testWidgets('Video clock is exact at tick three, completion and replay', (
    tester,
  ) async {
    final player = VideoPlayerViewModel(d.community, 'p3');
    addTearDown(player.dispose);
    player.toggle();
    await tester.pump(const Duration(seconds: 3));
    expect(player.elapsed, '00:03');
    await tester.pump(player.duration - const Duration(seconds: 3));
    expect(player.elapsed, player.durationLabel);
    expect(player.progress, 1);
    expect(player.playing, isFalse);
    player.toggle();
    expect(player.elapsed, '00:00');
    expect(player.playing, isTrue);
    player.seek(1);
    expect(player.playing, isFalse);
    player.seek(.5);
    expect(player.elapsed, '02:16');
    player.seek(double.nan);
    expect(player.elapsed, '02:16');
  });

  test('Review policy has one threshold and clears after manual override', () {
    const log = AiModelLog(
      id: 'review',
      prompt: 'Prompt',
      response: 'Sample',
      confidence: .79,
      latencyMs: 10,
    );
    const boundary = AiModelLog(
      id: 'boundary',
      prompt: 'Prompt',
      response: 'Sample',
      confidence: .8,
      latencyMs: 10,
    );
    expect(log.needsReview, isTrue);
    expect(boundary.needsReview, isFalse);
    expect(
      log.override('Reviewed response', 'Checked source').needsReview,
      isFalse,
    );
    d.auth.switchRole(UserRole.admin);
    d.aiOperationsVm.setFilter('Needs review');
    expect(d.aiOperationsVm.logs.every((l) => l.needsReview), isTrue);
    d.aiOperationsVm.applyOverride(
      'a2',
      'Reviewed nutrition guidance.',
      'Checked by reviewer',
    );
    expect(d.aiOperationsVm.logs, isEmpty);
    expect(d.dashboard.logs.any((l) => l.warning), isFalse);
  });
}
