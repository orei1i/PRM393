// test/m4_reels_ads_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/data/mock_ads_repository.dart';
import 'package:veganlife_mobile/features/ads/data/models/ad_feed_item.dart';
import 'package:veganlife_mobile/features/ads/presentation/controllers/ads_controller.dart';
import 'package:veganlife_mobile/features/ads/presentation/widgets/sponsored_store_card.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/feed_screen.dart';
import 'package:veganlife_mobile/features/reels/data/reels_api_service.dart';
import 'package:veganlife_mobile/features/reels/presentation/controllers/reels_controller.dart';
import 'package:veganlife_mobile/features/reels/presentation/screens/reels_player_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/maps_launcher.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';
import 'package:video_player/video_player.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// Plays without the video plugin and records what the page asks of it.
class _FakeVideo extends VideoPlayerController {
  _FakeVideo(String url) : super.networkUrl(Uri.parse(url));

  bool disposed = false;

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 12),
      size: const Size(720, 1280),
    );
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(411, 913)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(_minhAnh);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
    child: MaterialApp(home: home),
  ));
  await tester.pump(const Duration(seconds: 3)); // mock latency
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('ads feed (mock mirrors the web campaigns)', () {
    const q1 = (lat: 10.7769, lng: 106.7009);

    test('Running HCM campaigns only, nearest first, web item shape', () async {
      final ads = await MockAdsRepository()
          .getFeed(city: 'TP. Hồ Chí Minh', lat: q1.lat, lng: q1.lng);
      expect(ads.map((a) => a.id), ['ad_hanh_tam', 'ad_moc_nhien']);
      expect(ads.first.restaurant.name, 'Bún Riêu Chay Hạnh Tâm');
      expect(ads.first.ctaType, AdCtaType.viewStore);
      expect(ads.first.ctaLabel, 'Xem quán');
      expect(ads.last.ctaType, AdCtaType.book);
      expect(ads.first.distanceKm, closeTo(2.6, 0.2));
      expect(ads.first.distanceKm! <= ads.last.distanceKm!, isTrue);

      final json = ads.first.toJson();
      expect(json.keys.toSet(), {
        'id',
        'restaurantId',
        'restaurant',
        'headline',
        'message',
        'ctaType',
        'ctaLabel',
        'targetCity',
        'startAt',
        'endAt',
        'distanceKm',
      });
      expect((json['restaurant'] as Map<String, dynamic>).keys.toSet(), {
        'id',
        'name',
        'address',
        'isVeganCertified',
        'latitude',
        'longitude',
        'averageRating',
        'reviewCount',
      });
      // Round-trips through the parser unchanged.
      expect(AdFeedItemDto.fromJson(json).toJson(), json);
    });

    test('city, dates, paused and scenarios', () async {
      expect(await MockAdsRepository().getFeed(city: 'Hà Nội'), isEmpty);
      expect(await MockAdsRepository().getFeed(limit: 10), hasLength(2));
      // In 4 days "Đặt tiệc chay" (Vạn Hoa) has started too.
      final later = MockAdsRepository(
          clock: () => DateTime.now().add(const Duration(days: 4)));
      expect((await later.getFeed(limit: 10)).map((a) => a.id),
          containsAll(['ad_hanh_tam', 'ad_moc_nhien', 'ad_van_hoa']));
      expect(await MockAdsRepository(scenario: 'empty').getFeed(), isEmpty);
      expect(MockAdsRepository(scenario: 'error').getFeed(),
          throwsA(isA<ApiException>()));
    });

    test('parser: case-insensitive CTA, label fallback, optional fields', () {
      final ad = AdFeedItemDto.fromJson({
        'id': 7,
        'restaurantId': 3,
        'restaurant': {'id': 3, 'name': 'Quán A', 'address': 'Q.1'},
        'headline': 'H',
        'message': 'M',
        'ctaType': 'directions',
      });
      expect(ad.id, '7');
      expect(ad.ctaType, AdCtaType.directions);
      expect(ad.ctaLabel, 'Chỉ đường');
      expect(ad.distanceKm, isNull);
      expect(ad.restaurant.hasLocation, isFalse);
      expect(
          directionsUri(ad.restaurant).queryParameters['destination'], 'Q.1');
    });

    test('one ad after every 6 posts, each ad once', () {
      final posts = List.generate(13, (i) => i);
      final ads = [
        for (final id in ['a', 'b', 'c'])
          AdFeedItemDto.fromJson({
            'id': id,
            'restaurantId': 'r',
            'restaurant': {'id': 'r', 'name': 'R', 'address': ''},
            'headline': '',
            'message': '',
            'ctaType': 'ViewStore',
          }),
      ];
      final slots = interleaveAds(posts, ads);
      final adAt = [
        for (final (i, s) in slots.indexed)
          if (s is AdSlot<int>) i,
      ];
      expect(adAt, [6, 13]);
      expect(slots.whereType<PostSlot<int>>().map((s) => s.post), posts);
      expect(interleaveAds(posts, const []), hasLength(13));
    });
  });

  group('sponsored card', () {
    Future<AdFeedItemDto> firstAd() async =>
        (await MockAdsRepository().getFeed(lat: 10.7769, lng: 106.7009)).first;

    testWidgets('store, rating, distance, CTA → restaurant, "Chỉ đường" → Maps',
        (tester) async {
      final ad = await tester.runAsync(firstAd);
      final opened = <Uri>[];
      await _pump(
        tester,
        Scaffold(body: ListView(children: [SponsoredStoreCard(ad: ad!)])),
        overrides: [
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      expect(find.text('Được tài trợ'), findsOneWidget);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsOneWidget);
      expect(find.text('Chứng nhận thuần chay'), findsOneWidget);
      expect(find.textContaining('4 đánh giá'), findsOneWidget);
      expect(find.textContaining('km'), findsOneWidget);
      expect(find.text('Bún riêu chay 35k — riêu đậu hũ mềm'), findsOneWidget);

      await tester.tap(find.text('Chỉ đường'));
      await tester.pump();
      expect(opened.single.host, 'www.google.com');
      expect(opened.single.queryParameters['destination'], '10.8003,106.6977');

      await tester.tap(find.text('Xem quán'));
      await _frames(tester);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Trang chủ', () {
    testWidgets(
        'search and nearby in the app bar; a sponsored card after 6 posts',
        (tester) async {
      await _pump(tester, const FeedScreen());
      await tester.tap(find.byTooltip('Tìm kiếm'));
      await _frames(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(SearchScreen))).pop();
      await _frames(tester);

      await tester.tap(find.byTooltip('Quán chay gần bạn'));
      await _frames(tester);
      expect(find.byType(RestaurantNearbyScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(RestaurantNearbyScreen))).pop();
      await _frames(tester);
      await tester.pump(const Duration(seconds: 3));

      await tester.scrollUntilVisible(find.text('Được tài trợ'), 400,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('ad-ad_hanh_tam')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    test('reels are the community video posts, with playable clips', () async {
      final repo = MockReelsRepository(MockCommunityRepository(
          currentUserName: () => 'Minh Anh', isSignedIn: () => true));
      final reels = await repo.getReels();
      expect(reels, isNotEmpty);
      for (final r in reels) {
        final reel = r.toEntity();
        expect(reel.post.mediaType, PostMediaType.video);
        expect(reelSampleVideos, contains(reel.videoUrl));
      }
      expect(reels.first.toEntity().hasRecipe, isTrue);
    });

    testWidgets('Reels strip opens the player; a failed clip offers retry',
        (tester) async {
      await _pump(tester, const FeedScreen(), overrides: [
        reelVideoFactoryProvider
            .overrideWithValue((_) => throw Exception('no video plugin')),
      ]);
      expect(find.text('Reels'), findsOneWidget);
      await tester.tap(
          find.text('Chả lụa chay từ đậu hũ ky — không cần máy xay').first);
      await _frames(tester);
      expect(find.byType(ReelsPlayerScreen), findsOneWidget);
      expect(find.textContaining('Không phát được video'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      for (final t in ['Thích', 'Bình luận', 'Chia sẻ', 'Lưu']) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      expect(find.text('Xem công thức'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await _frames(tester);
      expect(find.byType(ReelsPlayerScreen), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('Reels player', () {
    testWidgets(
        'plays the active clip only, pauses on swipe, mute toggle, '
        'disposes every player', (tester) async {
      final created = <_FakeVideo>[];
      final repo = MockReelsRepository(MockCommunityRepository(
          currentUserName: () => 'Minh Anh', isSignedIn: () => true));
      final reels = (await tester.runAsync(repo.getReels))!
          .map((d) => d.toEntity())
          .toList();
      expect(reels.length, greaterThanOrEqualTo(2));
      await _pump(tester, ReelsPlayerScreen(reels: reels), overrides: [
        reelVideoFactoryProvider.overrideWithValue((url) {
          final v = _FakeVideo(url);
          created.add(v);
          return v;
        }),
      ]);
      expect(created, hasLength(1));
      expect(created.first.value.isPlaying, isTrue);
      expect(created.first.value.volume, 0, reason: 'autoplays muted');

      await tester.tap(find.byTooltip('Bật tiếng'));
      await tester.pump();
      expect(created.first.value.volume, 1);

      // Tap pauses, tap again resumes.
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      expect(created.first.value.isPlaying, isFalse);
      await tester.tapAt(const Offset(200, 400));
      await tester.pump();
      expect(created.first.value.isPlaying, isTrue);

      await tester.fling(find.byType(PageView), const Offset(0, -500), 2000);
      await _frames(tester);
      expect(created, hasLength(2));
      expect(created[1].value.isPlaying, isTrue);
      // The previous page is paused (or already gone with its player).
      expect(!created.first.value.isPlaying || created.first.disposed, isTrue);
      expect(created[1].value.volume, 1, reason: 'sound stays on');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(created.every((v) => v.disposed), isTrue);
    });
  });
}
