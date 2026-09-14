import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';
import 'package:vegan_life/src/features/community/domain/entities/community_entities.dart';
import 'package:vegan_life/src/features/community/presentation/view_models/post_detail_view_model.dart';
import 'package:vegan_life/src/features/community/presentation/view_models/create_post_view_model.dart';
import 'package:vegan_life/src/features/meal_planner/domain/entities/meal_entities.dart';
import 'package:vegan_life/src/features/discovery/domain/entities/shop_entities.dart';
import 'package:vegan_life/src/features/discovery/presentation/view_models/nearby_shops_view_model.dart';
import 'package:vegan_life/src/features/admin_moderation/domain/entities/moderation_entities.dart';
import 'package:vegan_life/src/features/trial_chat/presentation/view_models/trial_chat_view_model.dart';
import 'package:vegan_life/src/features/trial_chat/data/repositories/mock_trial_quota_repository.dart';

void main() {
  late AppDependencies d;
  setUp(() => d = AppDependencies(chatTokenDelay: Duration.zero));
  tearDown(() => d.dispose());
  test(
    'BMI validates input and calculates metric and imperial equivalents',
    () {
      d.auth.signInAsMember();
      d.planner.setHeight('170');
      d.planner.setWeight('65');
      expect(d.planner.calculateBmi(), isFalse);
      d.planner.setAdult(true);
      expect(d.planner.calculateBmi(), isTrue);
      expect(d.planner.profile!.bmi, closeTo(22.4913, .001));
      d.planner.setWeight('NaN');
      expect(d.planner.calculateBmi(), isFalse);
      d.planner.setWeight('-10');
      expect(d.planner.calculateBmi(), isFalse);
      d.planner.setUnit(MeasurementUnit.imperial);
      d.planner.setHeight('${170 / 2.54}');
      d.planner.setWeight('${65 / .45359237}');
      expect(d.planner.calculateBmi(), isTrue);
      expect(d.planner.profile!.bmi, closeTo(22.4913, .001));
      d.auth.signOut();
      expect(d.planner.profile, isNull);
      expect(d.planner.calculateBmi(), isFalse);
    },
  );
  test(
    'trial quota rejects empty and concurrent prompts and survives role changes',
    () async {
      expect(await d.trialChat.submit(' '), isFalse);
      expect(d.trialChat.limit.remaining, 3);
      final pending = d.trialChat.submit('protein');
      expect(await d.trialChat.submit('second concurrent question'), isFalse);
      expect(await pending, isTrue);
      expect(d.trialChat.limit.remaining, 2);
      await d.trialChat.submit('food swaps');
      await d.trialChat.submit('B12');
      expect(d.trialChat.limit.remaining, 0);
      expect(await d.trialChat.submit('fourth'), isFalse);
      d.auth.signInAsMember();
      d.auth.signOut();
      expect(d.trialChat.limit.remaining, 0);
      d.trialChat.clearConversation();
      expect(d.trialChat.limit.remaining, 0);
    },
  );
  test('app-scoped quota survives recreation of a trial ViewModel', () async {
    final quota = MockTrialQuotaRepository();
    final first = TrialChatViewModel(d.nutrition, d.auth, quota);
    await first.submit('B12');
    first.dispose();
    final second = TrialChatViewModel(d.nutrition, d.auth, quota);
    expect(second.limit.remaining, 2);
    second.dispose();
  });
  test('stream can fail, recover, and cancel on role downgrade', () async {
    d.auth.signInAsMember();
    expect(await d.chat.submit('/demo-error'), isFalse);
    expect(d.chat.busy, isFalse);
    expect(d.chat.error, isNotNull);
    expect(await d.chat.submit('protein'), isTrue);
    final pending = d.chat.submit('dinner');
    d.auth.signOut();
    expect(await pending, isFalse);
    expect(d.chat.messages, isEmpty);
  });
  test('votes toggle and switch without count drift; guest mutations fail', () {
    final vm = PostDetailViewModel(d.community, d.auth, 'p1');
    final base = vm.votes;
    expect(vm.toggleVote(VoteState.up), isFalse);
    d.auth.signInAsMember();
    vm.toggleVote(VoteState.up);
    expect(vm.votes, base + 1);
    vm.toggleVote(VoteState.up);
    expect(vm.votes, base);
    vm.toggleVote(VoteState.down);
    expect(vm.votes, base - 1);
    vm.toggleVote(VoteState.up);
    expect(vm.votes, base + 1);
    vm.setDraft('Great recipe!');
    vm.reply('c1');
    expect(vm.submitComment(), isTrue);
    expect(vm.replies('c1').last.text, 'Great recipe!');
    vm.dispose();
  });
  test(
    'create, edit, delete synchronize feed and profile with ownership checks',
    () {
      d.auth.signInAsMember();
      final vm = CreatePostViewModel(d.community, d.auth, d.categories);
      vm.setTitle('Test chickpea bowl');
      vm.setDescription('A delicious plant-based lunch.');
      vm.setIngredients('Chickpeas, Kale');
      vm.setSteps('Prepare ingredients.\nMix and serve.');
      final id = vm.save();
      expect(id, isNotNull);
      expect(d.feed.posts.first.id, id);
      expect(d.profile.posts.any((p) => p.id == id), isTrue);
      expect(d.profile.deletePost('p1'), isFalse);
      expect(d.profile.deletePost(id!), isTrue);
      expect(d.community.find(id), isNull);
      vm.dispose();
    },
  );
  test('feed pagination resets when filter or query changes', () {
    expect(d.feed.posts.length, 4);
    expect(d.feed.hasMore, isTrue);
    d.feed.loadMore();
    expect(d.feed.posts.length, 8);
    d.feed.setFilter('Breakfast');
    expect(d.feed.posts.length, 2);
    d.feed.setQuery('unfindable');
    expect(d.feed.posts, isEmpty);
    d.feed.setQuery('');
    d.feed.setFilter('For you');
    expect(d.feed.posts.length, 4);
  });
  test('weekly generator creates 7 days and shopping list responds', () async {
    d.auth.signInAsMember();
    d.planner.setPantry('tofu, spinach');
    await d.planner.generate();
    expect(d.planner.plan.days.length, 7);
    expect(d.planner.plan.days.every((day) => day.meals.length == 3), isTrue);
    expect(
      d.planner.plan.days.last.date
          .difference(d.planner.plan.days.first.date)
          .inDays,
      6,
    );
    d.planner.selectDay(4);
    expect(d.planner.selectedIndex, 4);
    final ingredient = d.planner.shopping.first;
    d.planner.toggleIngredient(ingredient.name);
    expect(d.planner.shopping.first.checked, !ingredient.checked);
  });
  test('distance sorting, filters, and map selection are consistent', () {
    expect(
      NearbyShopsViewModel.distance(
        const LocationCoords(10, 10),
        const LocationCoords(10, 10),
      ),
      0,
    );
    final results = d.shops.results;
    for (var i = 1; i < results.length; i++) {
      expect(
        results[i].distanceKm,
        greaterThanOrEqualTo(results[i - 1].distanceKm),
      );
    }
    d.shops.setQuery('Moss');
    d.shops.setMap(true);
    expect(d.shops.results.length, 1);
    expect(d.shops.selected!.shop.name, 'Moss & Mylk');
  });
  test('admin commands are guarded and moderation synchronizes data', () {
    expect(d.moderationVm.act('f1', ModerationDecision.delete), isFalse);
    expect(d.categoriesVm.save('New category'), isFalse);
    expect(
      d.aiOperationsVm.applyOverride(
        'a1',
        'A reviewed response.',
        'Checked source',
      ),
      isFalse,
    );
    d.auth.switchRole(UserRole.admin);
    expect(d.moderationVm.act('f1', ModerationDecision.warn), isTrue);
    expect(d.community.find('p3'), isNotNull);
    expect(d.moderationVm.act('f2', ModerationDecision.delete), isTrue);
    expect(d.community.find('p7'), isNull);
    expect(d.dashboardRepository.pendingReports, 1);
    expect(d.moderationVm.act('f2', ModerationDecision.delete), isFalse);
  });
  test(
    'category duplicates, in-use deletion, rename cascade and AI audit validation',
    () {
      d.auth.switchRole(UserRole.admin);
      expect(d.categoriesVm.save('Breakfast'), isFalse);
      expect(d.categoriesVm.delete('k3'), isFalse);
      expect(d.categoriesVm.save('Morning meals', id: 'k3'), isTrue);
      expect(d.community.find('p4')!.category, 'Morning meals');
      expect(d.categoriesVm.save('Seasonal'), isTrue);
      final category = d.categories.categories.last;
      expect(d.categoriesVm.delete(category.id), isTrue);
      expect(
        d.aiOperationsVm.applyOverride('a2', 'A useful replacement.', ''),
        isFalse,
      );
      expect(
        d.aiOperationsVm.applyOverride(
          'a2',
          'Please consult a qualified dietitian.',
          'Needs individual assessment',
        ),
        isTrue,
      );
      expect(
        d.aiOperations.logs.firstWhere((l) => l.id == 'a2').overridden,
        isTrue,
      );
    },
  );
}
