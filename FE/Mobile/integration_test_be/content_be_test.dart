// integration_test_be/content_be_test.dart
//
// The modules switched on last, through their real adapters on a real BE:
// restaurants, ads, search, recipe reviews and notes, and the geocoder that has
// no provider configured here.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/mock_persona.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/data/ads_api_service.dart';
import 'package:veganlife_mobile/features/community/data/backend_posts.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_review_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_community_api_service.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_social_controllers.dart';
import 'package:veganlife_mobile/features/restaurant/data/geocoding_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/models/restaurant_model.dart';
import 'package:veganlife_mobile/features/restaurant/data/restaurant_api_service.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/controllers/restaurant_controllers.dart';
import 'package:veganlife_mobile/features/search/data/search_api_service.dart';
import 'package:veganlife_mobile/features/search/domain/entities/search_result.dart';

import 'be_harness.dart';

const _here = GeoPoint(10.7769, 106.7009);

Future<void> main() async {
  final be = await BeHarness.start();

  group('the build is wired to these modules', skip: be.skipReason, () {
    test('real by default, geocoding and video on purpose not', () {
      for (final m in [
        BackendModule.chatbot,
        BackendModule.search,
        BackendModule.restaurants,
        BackendModule.ads,
        BackendModule.recipeSocial,
      ]) {
        expect(BackendModules.isReal(m), isTrue, reason: m.name);
      }
      expect(BackendModules.isMock(BackendModule.geocoding), isTrue);
      expect(BackendModules.isMock(BackendModule.video), isTrue);
    });

    beTest('the providers hand out the Remote services', () async {
      final me = await be.newUser();
      final c = await me.container();
      addTearDown(c.dispose);
      expect(c.read(restaurantApiProvider), isA<RemoteRestaurantApiService>());
      expect(c.read(adsApiProvider), isA<RemoteAdsApiService>());
      expect(c.read(searchApiProvider), isA<RemoteSearchApiService>());
      expect(c.read(recipeCommunityApiProvider),
          isA<RoutedRecipeCommunityApiService>());
      expect(c.read(geocodingServiceProvider), isA<MockGeocodingService>());
    });
  });

  group('restaurants', skip: be.skipReason, () {
    late String admin;
    late BeUser member;
    late RestaurantApiService api;
    late RestaurantApiService guest;
    late String tag;
    late String restaurantId;
    late String photoUrl;

    Future<PickedMedia> image() async {
      final bytes = pngBytes();
      return PickedMedia.image(
        name: 'quan.png',
        sizeBytes: bytes.length,
        path: await tempFile('quan.png', bytes),
      );
    }

    setUpAll(() async {
      admin = await be.adminToken();
      member = await be.newUser(name: 'FE IT Quán');
      api = RemoteRestaurantApiService(member.dio);
      guest = RemoteRestaurantApiService(be.guestDio());
      tag = randomHex(8);

      // The way the submit screen does it: upload, keep the URL it displays.
      final upload = await RemoteMediaApiService(member.dio).uploadImage(
        await image(),
      );
      photoUrl = upload.absoluteUrl;
      expect(photoUrl, startsWith(Env.apiOrigin));
      final created = await api.createRestaurant(CreateRestaurantRequestDto(
        name: 'Quán chay $tag',
        address: '$tag Nguyễn Huệ, Q.1, TP.HCM',
        latitude: _here.latitude + 0.001,
        longitude: _here.longitude,
        media: [
          NewRestaurantMediaDto(
              mediaType: RestaurantMediaType.image, mediaUrl: photoUrl),
        ],
      ));
      expect(created.status, RestaurantSuggestionStatus.pending);
      expect(created.createdById, member.id);
      expect(created.createdByName, member.name);
      restaurantId = created.id;
    });

    beTest('waiting: the author sees it, nobody else does', () async {
      final mine = await api.getMySuggestions();
      expect(mine.map((s) => s.id), contains(restaurantId));
      expect(await api.getRestaurant(restaurantId, near: _here),
          isA<RestaurantDto>());
      await expectApiError(guest.getRestaurant(restaurantId), status: 404);
      final public = await guest.listRestaurants(query: tag);
      expect(public, isEmpty);
    });

    beTest('a second suggestion of the same place is refused', () async {
      await expectApiError(
        api.createRestaurant(CreateRestaurantRequestDto(
            name: 'Quán chay $tag', address: '$tag Nguyễn Huệ, Q.1, TP.HCM')),
        status: 409,
        code: 'duplicate',
      );
    });

    beTest('a guest cannot suggest or review', () async {
      await expectApiError(
        guest.createRestaurant(CreateRestaurantRequestDto(
            name: 'Quán khách $tag', address: '$tag đường Khách, Q.1, TP.HCM')),
        status: 401,
      );
      await expectApiError(
          guest.upsertReview(restaurantId,
              rating: 5, comment: 'Đánh giá khách'),
          status: 401);
    });

    beTest('rejected: the member reads the reason', () async {
      final other = await api.createRestaurant(CreateRestaurantRequestDto(
          name: 'Quán bị từ chối $tag', address: '$tag Lê Lợi, Q.1, TP.HCM'));
      final res = await rawRequest(
          'POST', '/admin/restaurants/${other.id}/review',
          token: admin,
          data: {'decision': 'Reject', 'reason': 'Trùng với quán đã có.'});
      expect(res.status, 200);
      final row = (await api.getMySuggestions())
          .firstWhere((s) => s.id == other.id)
          .toSuggestion();
      expect(row.status, RestaurantSuggestionStatus.rejected);
      expect(row.rejectionReason, 'Trùng với quán đã có.');
      expect(row.reviewedAt, isNotNull);
    });

    group('approved', () {
      setUpAll(() async {
        final res = await rawRequest(
            'POST', '/admin/restaurants/$restaurantId/review',
            token: admin, data: {'decision': 'Approve'});
        expect(res.status, 200);
      });

      beTest('it is public, with a distance from the member', () async {
        final rows = await guest.listRestaurants(near: _here, query: tag);
        expect(rows.map((r) => r.id), [restaurantId]);
        final r = rows.single.toEntity();
        expect(r.isVeganCertified, isFalse);
        expect(r.location, isNotNull);
        expect(r.distanceKm, closeTo(0.11, 0.05));
        expect(r.averageRating, isNull, reason: 'no reviews, no made-up mark');
        expect(r.reviewCount, 0);
        expect(r.createdByName, member.name);
      });

      beTest('radius and certified filters', () async {
        expect(
            await guest.listRestaurants(near: _here, query: tag, radiusKm: 5),
            hasLength(1));
        expect(
            await guest.listRestaurants(
                near: const GeoPoint(21.03, 105.85), query: tag, radiusKm: 5),
            isEmpty);
        expect(await guest.listRestaurants(query: tag, certifiedOnly: true),
            isEmpty);
        final res = await rawRequest(
            'PATCH', '/admin/restaurants/$restaurantId',
            token: admin, data: {'isVeganCertified': true});
        expect(res.status, 200);
        expect(await guest.listRestaurants(query: tag, certifiedOnly: true),
            hasLength(1));
      });

      beTest('the photo the member uploaded opens from the API host', () async {
        final media = await guest.getMedia(restaurantId);
        final photo = media.single.toEntity();
        expect(photo.type, RestaurantMediaType.image);
        expect(photo.url, photoUrl);
        expect(photo.uploadedByName, member.name);
        final res = await rawRequest('GET', photo.url);
        expect(res.status, 200);
      });

      beTest('one review per member: a re-submit replaces it', () async {
        await expectApiError(
            api.upsertReview(restaurantId, rating: 5, comment: 'ngắn'),
            status: 400);
        final first = await api.upsertReview(restaurantId,
            rating: 5, comment: 'Bún riêu chay đậm vị, phục vụ nhanh.');
        expect(first.toEntity().userId, member.id);
        expect(first.toEntity().userName, member.name);
        final second = await api.upsertReview(restaurantId,
            rating: 3, comment: 'Lần này nước dùng hơi nhạt so với lần trước.');
        expect(second.id, first.id);
        final reviews = await guest.getReviews(restaurantId);
        expect(reviews.map((r) => r.rating), [3]);
        final row = (await guest.getRestaurant(restaurantId)).toEntity();
        expect(row.averageRating, 3);
        expect(row.reviewCount, 1);
      });

      beTest('"my review" finds the real account, not a sample persona',
          () async {
        final c = await member.container();
        addTearDown(c.dispose);
        final session = c.read(sessionControllerProvider);
        final me = moduleUserId(BackendModule.restaurants, session);
        expect(me, member.id);
        final state =
            await c.read(restaurantDetailProvider(restaurantId).future);
        expect(state.reviewBy(me), isNotNull);
      });

      beTest('a dish in the reviews finds the place', () async {
        final rows = await guest.listRestaurants(query: 'nước dùng hơi nhạt');
        expect(rows.map((r) => r.id), contains(restaurantId));
        final food = await guest.suggestedForFood('quán chay $tag',
            near: _here, limit: 3);
        expect(food.map((r) => r.id), contains(restaurantId));
      });

      beTest('a post tagged with it shows the place ("Gắn quán")', () async {
        expect(BackendModules.restaurantTag, isTrue);
        final community = RemoteCommunityApiService(member.dio,
            currentUserId: () => member.id);
        final place = (await guest.getRestaurant(restaurantId)).toEntity();
        final post = await community.createPost(CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Bài gắn quán $tag',
          body: 'Nội dung đủ dài để máy chủ nhận bài viết này.',
          restaurant: TaggedRestaurant(
              id: place.id,
              name: place.name,
              isCertified: place.isVeganCertified),
        ));
        expect(post.restaurant?.id, place.id);
        expect(post.restaurant?.name, place.name);
        final read = await community.getPost(post.id);
        expect(read.toEntity().restaurant?.name, place.name);
        await member.raw('DELETE', '/posts/${post.id}');
      });

      beTest('removed by an admin: gone, with its reviews', () async {
        final other = await api.createRestaurant(CreateRestaurantRequestDto(
            name: 'Quán sẽ xoá $tag', address: '$tag Pasteur, Q.1, TP.HCM'));
        await rawRequest('POST', '/admin/restaurants/${other.id}/review',
            token: admin, data: {'decision': 'Approve'});
        expect((await guest.getRestaurant(other.id)).id, other.id);
        final res = await rawRequest('DELETE', '/admin/restaurants/${other.id}',
            token: admin);
        expect(res.status, 200);
        await expectApiError(guest.getRestaurant(other.id), status: 404);
      });
    });
  });

  group('ads', skip: be.skipReason, () {
    late String admin;
    late AdsApiService api;
    late String adId;
    late String restaurantId;

    Future<Map<String, dynamic>> campaign() async {
      final rows = await rawRequest('GET', '/admin/ads',
          token: admin, query: {'search': adId});
      final all = await rawRequest('GET', '/admin/ads', token: admin);
      return [...rows.dataList, ...all.dataList]
          .firstWhere((a) => a['id'] == adId);
    }

    setUpAll(() async {
      admin = await be.adminToken();
      api = RemoteAdsApiService(be.guestDio());
      final member = await be.newUser(name: 'FE IT Ads');
      final tag = randomHex(8);
      final place = await RemoteRestaurantApiService(member.dio)
          .createRestaurant(CreateRestaurantRequestDto(
        name: 'Quán quảng cáo $tag',
        address: '$tag Hai Bà Trưng, Q.3, TP.HCM',
        latitude: _here.latitude,
        longitude: _here.longitude,
      ));
      restaurantId = place.id;
      await rawRequest('POST', '/admin/restaurants/$restaurantId/review',
          token: admin, data: {'decision': 'Approve'});
      final now = DateTime.now().toUtc();
      final res = await rawRequest('POST', '/admin/ads', token: admin, data: {
        'restaurantId': restaurantId,
        'placement': 'nearby',
        'headline': 'Bún riêu chay $tag',
        'message': 'Tô đầy đặn, nước dùng ngọt từ rau củ.',
        'ctaType': 'ViewStore',
        'targetCity': 'TP. Hồ Chí Minh',
        'startAt': now.subtract(const Duration(days: 1)).toIso8601String(),
        'endAt': now.add(const Duration(days: 30)).toIso8601String(),
        'budget': 200000,
      });
      expect(res.status, 200);
      adId = res.dataMap['id'] as String;
    });

    tearDownAll(() async {
      await rawRequest('DELETE', '/admin/ads/$adId', token: admin);
    });

    beTest('the feed gives what the sponsored row shows', () async {
      final rows = await api.getFeed(
          city: 'tp. ho chi minh',
          lat: _here.latitude,
          lng: _here.longitude,
          limit: 50);
      final ad = rows.firstWhere((a) => a.id == adId);
      expect(ad.restaurantId, restaurantId);
      expect(ad.restaurant.id, restaurantId);
      expect(ad.restaurant.hasLocation, isTrue);
      expect(ad.ctaLabel, 'Xem quán');
      expect(ad.distanceKm, closeTo(0, 0.1));
      expect(ad.endAt, isNotNull);
    });

    beTest('another city does not get it, the nearest comes first', () async {
      final elsewhere = await api.getFeed(city: 'Hà Nội', limit: 50);
      expect(elsewhere.map((a) => a.id), isNot(contains(adId)));
      final nearest =
          await api.getFeed(lat: _here.latitude, lng: _here.longitude);
      expect(nearest, hasLength(lessThanOrEqualTo(1)));
    });

    beTest('impression and click count, no body needed', () async {
      await api.reportImpression(adId);
      await api.reportClick(adId);
      final row = await campaign();
      expect(row['impressions'], 1);
      expect(row['clicks'], 1);
      expect(row['spent'], 40);
      await expectApiError(api.reportClick(randomHex(24)), status: 404);
    });

    beTest('paused by the admin: it leaves the feed', () async {
      await rawRequest('POST', '/admin/ads/$adId/pause', token: admin);
      final rows = await api.getFeed(limit: 50);
      expect(rows.map((a) => a.id), isNot(contains(adId)));
      await rawRequest('POST', '/admin/ads/$adId/resume', token: admin);
      expect((await api.getFeed(limit: 50)).map((a) => a.id), contains(adId));
    });
  });

  group('search', skip: be.skipReason, () {
    late BeUser me;
    late SearchApiService member;
    late SearchApiService guest;
    late String marker;
    late String postId;
    late String imagePostId;

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Tìm');
      guest = RemoteSearchApiService(be.guestDio());
      marker = 'tìmthật${randomHex(6)}';
      final community =
          RemoteCommunityApiService(me.dio, currentUserId: () => me.id);
      final post = await community.createPost(CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Bài $marker về đậu hũ',
          body: 'Nội dung đủ dài để máy chủ nhận bài viết này.'));
      postId = post.id;
      final bytes = pngBytes();
      final upload = await RemoteMediaApiService(me.dio).uploadImage(
          PickedMedia.image(
              name: 'a.png',
              sizeBytes: bytes.length,
              path: await tempFile('a.png', bytes)));
      final image = await community.createPost(CreatePostRequestDto(
          type: PostType.discussion,
          title: 'Ảnh $marker về nấm',
          body: 'Nội dung đủ dài để máy chủ nhận bài viết này.',
          mediaType: PostMediaType.image,
          mediaUrl: upload.mediaUrl));
      imagePostId = image.id;
      final saved = SavedPostsStore(currentUserId: () => me.id);
      await saved.setSaved(postId, saved: true);
      member = RemoteSearchApiService(me.dio, saved: saved);
    });

    tearDownAll(() async {
      await me.raw('DELETE', '/posts/$postId');
      await me.raw('DELETE', '/posts/$imagePostId');
    });

    beTest('a real post, with or without accents, for a guest too', () async {
      final plain = marker.replaceAll('ì', 'i').replaceAll('ậ', 'a');
      for (final who in [member, guest]) {
        for (final q in [marker, plain, 'Bài $plain']) {
          final r = (await who.search(q)).toEntity();
          expect(r.query, q);
          expect(r.posts.map((p) => p.id), contains(postId), reason: q);
          expect(r.recipeScope, RecipeSearchScope.full);
          expect(r.postsTruncated, isFalse);
        }
      }
    });

    beTest('the post reads like one of the feed', () async {
      final r = (await member.search(marker)).toEntity();
      final saved = r.posts.firstWhere((p) => p.id == postId);
      expect(saved.savedByMe, isTrue, reason: '"Đã lưu" stays on the device');
      expect(saved.author.name, me.name);
      final image = r.posts.firstWhere((p) => p.id == imagePostId);
      expect(image.imageUrl ?? image.mediaUrl, startsWith(Env.apiOrigin));
    });

    beTest('a hidden post is not found', () async {
      final admin = await be.adminToken();
      await rawRequest('POST', '/admin/posts/$postId/actions',
          token: admin, data: {'action': 'hide'});
      final r = (await guest.search(marker)).toEntity();
      expect(r.posts.map((p) => p.id), isNot(contains(postId)));
      await rawRequest('POST', '/admin/posts/$postId/actions',
          token: admin, data: {'action': 'unhide'});
      expect((await guest.search(marker)).toEntity().posts.map((p) => p.id),
          contains(postId));
    });

    beTest('recipes for a guest too, and they open', () async {
      final r = (await guest.search('cơm')).toEntity();
      expect(r.recipes, isNotEmpty);
      final recipe = r.recipes.first;
      expect(recipe.calories, isNotNull);
      expect(r.suggestion?.recipe.id, recipe.id);
      final opened = await RecipeCatalog(be.guestDio()).find(recipe.id);
      expect(opened?.name, recipe.name);
    });

    beTest('another member\'s private recipe is not found', () async {
      final other = await be.newUser();
      final name = 'Món riêng $marker';
      final res = await other.raw('POST', '/recipes', data: {
        'name': name,
        'calories': 300,
        'prepMinutes': 10,
        'instructions': ['Nấu chín rồi dọn ra đĩa.'],
        'ingredients': ['Đậu hũ'],
      });
      expect(res.status, lessThan(300));
      expect((await guest.search(name)).toEntity().recipes, isEmpty);
      expect((await member.search(name)).toEntity().recipes, isEmpty);
      final own = (await RemoteSearchApiService(other.dio).search(name))
          .toEntity()
          .recipes;
      expect(own.map((r) => r.name), [name]);
    });

    beTest('ingredients, accents ignored', () async {
      for (final q in ['đậu hũ', 'dau hu']) {
        final r = (await guest.search(q)).toEntity();
        expect(r.ingredients.map((i) => i.name), contains('Đậu hũ'));
        final id = r.ingredients.firstWhere((i) => i.name == 'Đậu hũ').id;
        final detail =
            await RemoteIngredientApiService(be.guestDio()).detail(id);
        expect(detail.toEntity().name, 'Đậu hũ');
      }
    });

    beTest('type narrows it; nothing typed finds nothing', () async {
      final videos =
          (await guest.search(marker, type: SearchType.video)).toEntity();
      expect(videos.posts, isEmpty);
      final blank = (await guest.search('   ')).toEntity();
      expect(blank.posts, isEmpty);
      expect(blank.suggestion, isNull);
    });

    beTest('suggestions while typing', () async {
      final rows = await guest.suggest('đậu hũ', limit: 8);
      expect(rows, isNotEmpty);
      expect(rows.length, lessThanOrEqualTo(8));
      expect(
          rows.map((r) => r.toEntity().kind), contains(SuggestKind.ingredient));
      expect(rows.every((r) => r.id != null), isTrue,
          reason: 'every row opens something');
      expect(await guest.suggest('đ'), isEmpty, reason: 'needs two characters');
      final mine = await guest.suggest(marker);
      expect(mine.where((r) => r.kind == 'post').map((r) => r.id),
          contains(postId));
    });

    beTest('the idle page has nothing made up', () async {
      final page = (await guest.discover(near: _here)).toEntity();
      expect(page.trending, isEmpty);
      expect(page.seasonal, isEmpty);
      for (final r in page.nearbyRestaurants) {
        expect(r.distanceKm, isNotNull);
      }
      for (final c in page.categories) {
        expect(c.label, isNotEmpty);
        expect(c.query, isNotEmpty);
      }
    });
  });

  group('recipe reviews and notes', skip: be.skipReason, () {
    late String recipeId;
    late BeUser me;
    late RecipeCommunityApiService api;
    late RecipeCommunityApiService guest;

    setUpAll(() async {
      final page = await rawRequest('GET', '/recipes', query: {'limit': 20});
      final rows = (page.dataMap['items'] as List).cast<Map<String, dynamic>>();
      // Another one each run, to keep the sums simple on a DB that grows.
      rows.shuffle();
      recipeId = rows.first['id'] as String;
      me = await be.newUser(name: 'FE IT Đánh giá');
      api = RemoteRecipeCommunityApiService(me.dio);
      guest = RemoteRecipeCommunityApiService(be.guestDio());
    });

    beTest('a guest reads, cannot write', () async {
      final page = await guest.getReviews(recipeId);
      expect(page.recipeId, recipeId);
      expect(page.myReview, isNull);
      await expectApiError(
          guest.upsertMyReview(recipeId,
              const UpsertReviewRequestDto(rating: 5, content: 'Món rất ngon')),
          status: 401);
      await expectApiError(guest.getMyNote(recipeId), status: 401);
    });

    beTest('write, replace, delete: the sums follow', () async {
      final before = await guest.getReviews(recipeId);
      await expectApiError(
          api.upsertMyReview(recipeId,
              const UpsertReviewRequestDto(rating: 5, content: 'ngắn')),
          status: 400);

      final first = await api.upsertMyReview(
          recipeId,
          const UpsertReviewRequestDto(
              rating: 5, content: 'Món rất ngon, dễ nấu.'));
      expect(first.ratingCount, before.summary.count + 1);
      expect(first.review.authorId, me.id);
      expect(first.review.authorName, me.name);
      expect(first.review.isVerifiedChef, isFalse);

      final second = await api.upsertMyReview(
          recipeId, const UpsertReviewRequestDto(rating: 2));
      expect(second.ratingCount, before.summary.count + 1, reason: 'replaced');
      expect(second.review.id, first.review.id);
      expect(second.review.content, isNull, reason: 'the text is optional');

      final mine = await api.getReviews(recipeId);
      expect(mine.myReview?.rating, 2);
      expect(mine.items.map((r) => r.id), isNot(contains(first.review.id)),
          reason: 'not repeated');
      expect(mine.summary.distribution[2], greaterThanOrEqualTo(1));

      final others = await guest.getReviews(recipeId);
      expect(others.items.map((r) => r.id), contains(first.review.id));

      final totals = await api.deleteMyReview(recipeId);
      expect(totals.ratingCount, before.summary.count);
      expect((await api.getReviews(recipeId)).myReview, isNull);
    });

    beTest('pages of reviews', () async {
      final people = [for (var i = 0; i < 3; i++) await be.newUser()];
      for (final p in people) {
        await RemoteRecipeCommunityApiService(p.dio).upsertMyReview(
            recipeId,
            const UpsertReviewRequestDto(
                rating: 4, content: 'Món ăn được lắm.'));
      }
      final first = await guest.getReviews(recipeId, limit: 2);
      expect(first.items, hasLength(2));
      expect(first.nextCursor, isNotNull);
      final second =
          await guest.getReviews(recipeId, cursor: first.nextCursor, limit: 2);
      expect(second.items.map((r) => r.id),
          isNot(anyElement(isIn(first.items.map((r) => r.id)))));
    });

    beTest('a member\'s recipe: no reviews, and not by its author', () async {
      final res = await me.raw('POST', '/recipes', data: {
        'name': 'Món của tôi ${randomHex(6)}',
        'calories': 300,
        'prepMinutes': 10,
        'instructions': ['Nấu chín rồi dọn ra đĩa.'],
        'ingredients': ['Đậu hũ'],
      });
      expect(res.status, lessThan(300));
      final mine = res.dataMap['id'] as String;
      await expectApiError(
          api.upsertMyReview(
              mine,
              const UpsertReviewRequestDto(
                  rating: 5, content: 'Ngon lắm luôn đó')),
          status: 403,
          code: 'own_recipe');
      await expectApiError(guest.getReviews(mine),
          status: 404, code: 'private_recipe');
    });

    beTest('a note: none, saved, replaced, emptied, deleted', () async {
      expect(await api.getMyNote(recipeId), isNull);
      final saved = await api.saveMyNote(recipeId, ' Bớt muối ');
      expect(saved?.entity.content, 'Bớt muối');
      expect((await api.getMyNote(recipeId))?.entity.content, 'Bớt muối');

      final other = RemoteRecipeCommunityApiService((await be.newUser()).dio);
      expect(await other.getMyNote(recipeId), isNull, reason: 'it is private');

      expect(await api.saveMyNote(recipeId, '   '), isNull);
      expect(await api.getMyNote(recipeId), isNull);

      await api.saveMyNote(recipeId, 'Lần sau thêm nấm');
      await api.deleteMyNote(recipeId);
      expect(await api.getMyNote(recipeId), isNull);
    });

    beTest('the controllers of the screen, on the real account', () async {
      final user = await be.newUser(name: 'FE IT Màn đánh giá');
      final c = await user.container();
      addTearDown(c.dispose);
      final sub = c.listen(recipeReviewsProvider(recipeId), (_, __) {});
      addTearDown(sub.close);
      final start = await c.read(recipeReviewsProvider(recipeId).future);
      final notifier = c.read(recipeReviewsProvider(recipeId).notifier);
      await notifier.submit(rating: 4, content: 'Đã nấu thử, rất hợp khẩu vị.');
      final after = c.read(recipeReviewsProvider(recipeId)).requireValue;
      expect(after.myReview?.rating, 4);
      expect(after.summary.count, start.summary.count + 1);
      await notifier.deleteMine();
      expect(c.read(recipeReviewsProvider(recipeId)).requireValue.myReview,
          isNull);

      final noteSub = c.listen(recipeNoteProvider(recipeId), (_, __) {});
      addTearDown(noteSub.close);
      await c.read(recipeNoteProvider(recipeId).future);
      await c.read(recipeNoteProvider(recipeId).notifier).save('Ghi chú thật');
      expect(c.read(recipeNoteProvider(recipeId)).requireValue?.content,
          'Ghi chú thật');
    });

    beTest('a sample recipe stays with the mock, a real one goes to the BE',
        () async {
      final routed = RoutedRecipeCommunityApiService(
          remote: api, mock: MockRecipeCommunityRepository(userId: me.id));
      // `l5` is a mock id: the BE would answer 404.
      final sample = await routed.getReviews('l5');
      expect(sample.summary.count, greaterThan(0));
      final real = await routed.getReviews(recipeId);
      expect(real.recipeId, recipeId);
    });
  });

  group('geocoding: no provider configured on this BE', skip: be.skipReason,
      () {
    late GeocodingService real;

    setUp(() => real = RemoteGeocodingService(be.guestDio()));

    beTest('both routes say 503, with a message; nothing is made up', () async {
      await expectApiError(real.search('Bến Thành'),
          status: 503, code: 'geo_unavailable');
      await expectApiError(real.reverse(_here),
          status: 503, code: 'geo_unavailable');
    });

    test('so the app keeps the labelled sample list', () async {
      final places = await const MockGeocodingService().search('Bến Thành');
      expect(places.map((p) => p.name), contains('Chợ Bến Thành'));
    });
  });

  group('errors stay readable', skip: be.skipReason, () {
    beTest('a bad query is the server\'s Vietnamese message', () async {
      final dio = be.guestDio();
      try {
        await dio.get<Object?>('/restaurants', queryParameters: {'sort': 'x'});
        fail('expected a 400');
      } on DioException catch (e) {
        final error = e.error;
        expect(error, isA<ApiException>());
        expect((error! as ApiException).message, isVietnamese);
      }
    });
  });
}
