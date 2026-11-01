// integration_test_be/search_be_test.dart
// Search on the client (`ClientSearchService`) over the real BE: there is no
// `/search` route, so this is what a member and a guest actually get.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/search/data/client_search_service.dart';
import 'package:veganlife_mobile/features/search/domain/entities/search_result.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  ClientSearchService service(BeUser? user) {
    final dio = user?.dio ?? be.guestDio();
    return ClientSearchService(
      community: RemoteCommunityApiService(dio, currentUserId: () => user?.id),
      ingredients: RemoteIngredientApiService(dio),
      restaurants: MockRestaurantRepository(
        isSignedIn: () => user != null,
        currentUserId: () => 'u_me',
        currentUserName: () => 'FE IT',
      ),
      recipes: () => ClientSearchService.backendRecipes(
        isGuest: () => user == null,
        catalog: () => RecipeCatalog(dio, userId: user?.id),
        dio: dio,
        planId: () => null,
      ),
    );
  }

  group('client search', skip: be.skipReason, () {
    late BeUser me;
    late String marker;

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Search');
      marker = 'tìmkiếmthử${randomHex(6)}';
      await RemoteCommunityApiService(me.dio).createPost(CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Bài $marker về đậu hũ',
          body: 'Nội dung đủ dài để máy chủ nhận bài viết này.'));
    });

    beTest('a real post, with or without accents, for a guest too', () async {
      final plain = marker.replaceAll('ì', 'i').replaceAll('ế', 'e');
      for (final who in [me, null]) {
        for (final q in [marker, plain, plain.substring(0, 12)]) {
          final r = (await service(who).search(q)).toEntity();
          expect(r.posts.map((p) => p.title), contains('Bài $marker về đậu hũ'),
              reason: q);
        }
      }
    });

    beTest('ingredients through /ingredients?q=, accents ignored', () async {
      for (final q in ['đậu hũ', 'dau hu']) {
        final r = (await service(me).search(q)).toEntity();
        expect(r.ingredients.map((i) => i.name), contains('Đậu hũ'), reason: q);
        expect(r.ingredients.first.id, isNotEmpty);
      }
    });

    beTest('a guest gets no recipes, and the result says why', () async {
      final r = (await service(null).search('đậu')).toEntity();
      expect(r.recipes, isEmpty);
      expect(r.recipeScope, RecipeSearchScope.signedOut);
      expect(r.ingredients, isNotEmpty);
    });

    beTest('a member with no plan: the small catalogue, and it says so',
        () async {
      final r = (await service(me).search('đậu')).toEntity();
      expect(r.recipeScope, RecipeSearchScope.fridgeOnly);
      expect(r.recipes.length, lessThanOrEqualTo(10));
    });

    beTest('discover has nothing made up', () async {
      final page = (await service(me).discover()).toEntity();
      expect(page.trending, isEmpty);
      expect(page.seasonal, isEmpty);
      expect(page.popularRecipes, isEmpty);
    });
  });
}
