import 'package:vegan_life/src/features/ai_nutrition/presentation/view_models/ai_nutrition_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vegan_life/src/bootstrap.dart';
import 'package:vegan_life/src/features/auth/domain/entities/auth_session.dart';
import 'package:vegan_life/src/features/community/presentation/view_models/create_post_view_model.dart';
import 'package:vegan_life/src/features/community/presentation/view_models/video_player_view_model.dart';

void main() {
  late AppDependencies d;
  setUp(() => d = AppDependencies(chatTokenDelay: Duration.zero));
  tearDown(() => d.dispose());

  test('Category catalog updates feed, explore and open composers', () {
    d.auth.signInAsMember();
    final composer = CreatePostViewModel(
      d.community,
      d.auth,
      d.categories,
      postId: 'p4',
    );
    addTearDown(composer.dispose);
    d.feed.setFilter('Breakfast');
    // Repository update simulates a catalog change from another client.
    d.categories.save('Morning meals', id: 'k3');
    expect(composer.category, 'Morning meals');
    expect(d.feed.filter, 'For you');
    expect(d.feed.filters, contains('Morning meals'));
    expect(d.explore.guestFilters, contains('Morning meals'));
    expect(d.feed.filters, isNot(contains('Breakfast')));
    expect(composer.save(), 'p4');
    expect(d.community.find('p4')!.category, 'Morning meals');
    d.categories.save('Seasonal');
    expect(composer.categories, contains('Seasonal'));
  });

  test('Reserved filter names are rejected and review alert resolves', () {
    d.auth.switchRole(UserRole.admin);
    expect(d.categoriesVm.save('Saved'), isFalse);
    expect(d.dashboard.logs.any((l) => l.warning), isTrue);
    d.aiOperationsVm.applyOverride(
      'a2',
      'Please consult a registered dietitian.',
      'Individual assessment needed',
    );
    expect(d.dashboard.logs.any((l) => l.warning), isFalse);
  });

  test('Stale composer cannot publish as a different actor', () {
    d.auth.signInAsMember();
    final composer = CreatePostViewModel(d.community, d.auth, d.categories);
    addTearDown(composer.dispose);
    composer.setTitle('A very tasty recipe');
    composer.setDescription('A plant-based meal for the family.');
    composer.setIngredients('tofu');
    composer.setSteps('Cook tofu.');
    d.auth.switchRole(UserRole.admin);
    expect(composer.save(), isNull);
  });

  test('Video playback stops if its shared content is removed', () {
    final player = VideoPlayerViewModel(d.community, 'p3');
    addTearDown(player.dispose);
    player.toggle();
    expect(player.playing, isTrue);
    player.seek(.5);
    expect(player.elapsed, '02:16');
    d.community.deletePost('p3');
    expect(player.post, isNull);
    expect(player.playing, isFalse);
    player.toggle();
    expect(player.playing, isFalse);
  });

  test(
    'Disposing streaming ViewModel completes the outstanding future',
    () async {
      d.auth.signInAsMember();
      final chat = AiNutritionViewModel(d.nutrition, d.auth);
      final pending = chat.submit('protein');
      chat.dispose();
      expect(await pending, isFalse);
      expect(chat.disposed, isTrue);
    },
  );
}
