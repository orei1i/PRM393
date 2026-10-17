// test/restaurant/ads_nearby_test.dart
// Store ads: one "Được tài trợ" row at the top of "Quán chay gần bạn"
// (placement "nearby", limit 1, like the web /ads), impressions and clicks.
// Replaces the feed interleave / feed card / post-ad-picker tests: ads no
// longer appear in the feed or in posts.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/data/ads_api_service.dart';
import 'package:veganlife_mobile/features/ads/data/mock_ads_repository.dart';
import 'package:veganlife_mobile/features/ads/data/models/ad_feed_item.dart';
import 'package:veganlife_mobile/features/ads/presentation/controllers/ads_controller.dart';
import 'package:veganlife_mobile/features/ads/presentation/widgets/sponsored_restaurant_row.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';

const _q1 = (lat: 10.7769, lng: 106.7009);

Future<SharedPreferences> _prefs(
    [Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const [],
    Map<String, Object> prefs = const {}}) async {
  tester.view
    ..physicalSize = const Size(411, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = await _prefs(prefs);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(p), ...overrides],
    child: MaterialApp(home: home),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Records what the screen reports, on top of the mock feed.
class _RecordingAds implements AdsApiService {
  final _mock = MockAdsRepository();
  final feeds = <({String placement, String? city, int limit})>[];
  final impressions = <String>[];
  final clicks = <String>[];

  @override
  Future<List<AdFeedItemDto>> getFeed({
    String placement = AdPlacement.nearby,
    String? city,
    double? lat,
    double? lng,
    int limit = AdPlacement.nearbyLimit,
  }) {
    feeds.add((placement: placement, city: city, limit: limit));
    return _mock.getFeed(
        placement: placement, city: city, lat: lat, lng: lng, limit: limit);
  }

  @override
  Future<void> reportImpression(String adId) async => impressions.add(adId);

  @override
  Future<void> reportClick(String adId) async => clicks.add(adId);
}

void main() {
  setUp(() {
    MockRestaurantRepository.reset();
    MockAdsRepository.resetEvents();
  });

  group('ads feed (mock mirrors the web campaigns, placement nearby)', () {
    test('one Running HCM campaign by default: the nearest, web item shape',
        () async {
      final ads = await MockAdsRepository()
          .getFeed(city: 'TP. Hồ Chí Minh', lat: _q1.lat, lng: _q1.lng);
      expect(ads.map((a) => a.id), ['ad_hanh_tam']);
      final ad = ads.single;
      expect(ad.placement, AdPlacement.nearby);
      expect(ad.restaurant.name, 'Bún Riêu Chay Hạnh Tâm');
      expect(ad.ctaType, AdCtaType.viewStore);
      expect(ad.ctaLabel, 'Xem quán');
      expect(ad.distanceKm, closeTo(2.6, 0.2));

      final json = ad.toJson();
      expect(json.keys.toSet(), {
        'id',
        'restaurantId',
        'placement',
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
      expect(json['placement'], 'nearby');
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

    test('limit, city, dates, placement and scenarios', () async {
      final both = await MockAdsRepository()
          .getFeed(lat: _q1.lat, lng: _q1.lng, limit: 10);
      expect(both.map((a) => a.id), ['ad_hanh_tam', 'ad_moc_nhien']);
      expect(both.last.ctaType, AdCtaType.book);
      expect(await MockAdsRepository().getFeed(city: 'Hà Nội'), isEmpty);
      expect(await MockAdsRepository().getFeed(placement: 'feed'), isEmpty);
      // In 4 days "Đặt tiệc chay" (Vạn Hoa) has started too.
      final later = MockAdsRepository(
          clock: () => DateTime.now().add(const Duration(days: 4)));
      expect((await later.getFeed(limit: 10)).map((a) => a.id),
          containsAll(['ad_hanh_tam', 'ad_moc_nhien', 'ad_van_hoa']));
      expect(await MockAdsRepository(scenario: 'empty').getFeed(), isEmpty);
      expect(MockAdsRepository(scenario: 'error').getFeed(),
          throwsA(isA<ApiException>()));
    });

    test('parser: case-insensitive CTA, label and placement fallbacks', () {
      final ad = AdFeedItemDto.fromJson({
        'id': 7,
        'restaurantId': 3,
        'restaurant': {'id': 3, 'name': 'Quán A', 'address': 'Q.1'},
        'headline': 'H',
        'message': 'M',
        'ctaType': 'directions',
      });
      expect(ad.id, '7');
      expect(ad.placement, 'nearby');
      expect(ad.ctaType, AdCtaType.directions);
      expect(ad.ctaLabel, 'Chỉ đường');
      expect(ad.distanceKm, isNull);
      expect(ad.restaurant.hasLocation, isFalse);
      final r = adRestaurant(ad);
      expect(r.id, '3');
      expect(r.location, isNull);
      expect(r.averageRating, isNull);
    });

    test('impressions and clicks are counted', () async {
      final repo = MockAdsRepository();
      await repo.reportImpression('ad_hanh_tam');
      await repo.reportClick('ad_hanh_tam');
      await repo.reportClick('ad_hanh_tam');
      expect(MockAdsRepository.impressionsOf('ad_hanh_tam'), 1);
      expect(MockAdsRepository.clicksOf('ad_hanh_tam'), 2);
      expect(MockAdsRepository.impressionsOf('ad_moc_nhien'), 0);
    });

    test('nearbyAdsProvider: placement nearby, limit 1, follows the location',
        () async {
      final ads = _RecordingAds();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        adsApiProvider.overrideWithValue(ads),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(nearbyAdsProvider, (_, __) {});
      addTearDown(sub.close);
      expect((await container.read(nearbyAdsProvider.future)).single.id,
          'ad_hanh_tam');
      expect(ads.feeds.single,
          (placement: 'nearby', city: 'TP. Hồ Chí Minh', limit: 1));

      // Phú Mỹ Hưng (Q.7): Mộc Nhiên is nearer.
      await container.read(userLocationProvider.notifier).setLocation(
          const UserLocation(
              point: GeoPoint(10.7295, 106.7213),
              label: 'Phú Mỹ Hưng',
              source: UserLocationSource.search,
              city: 'TP. Hồ Chí Minh'));
      expect((await container.read(nearbyAdsProvider.future)).single.id,
          'ad_moc_nhien');

      // Hà Nội: no campaign targets it.
      await container.read(userLocationProvider.notifier).setLocation(
          const UserLocation(
              point: GeoPoint(21.0287, 105.8524),
              label: 'Hồ Hoàn Kiếm',
              source: UserLocationSource.search,
              city: 'Hà Nội'));
      expect(await container.read(nearbyAdsProvider.future), isEmpty);
    });
  });

  group('"Được tài trợ" row in Quán chay gần bạn', () {
    testWidgets(
        'at most one row, first; one impression per display; tap = click '
        '→ restaurant', (tester) async {
      final ads = _RecordingAds();
      await _pump(tester, const RestaurantNearbyScreen(),
          overrides: [adsApiProvider.overrideWithValue(ads)]);
      await _wait(tester);
      expect(find.byType(SponsoredRestaurantRow), findsOneWidget);
      expect(find.text('Được tài trợ'), findsOneWidget);
      expect(find.text('Bún riêu chay 35k — riêu đậu hũ mềm'), findsOneWidget);
      expect(tester.getTopLeft(find.byType(SponsoredRestaurantRow)).dy,
          lessThan(tester.getTopLeft(find.text('Chay Thanh Tịnh')).dy));
      await _wait(tester, 500);
      expect(ads.impressions, ['ad_hanh_tam']);

      // Rebuilds (a new search) do not count again.
      await tester.enterText(find.byType(TextField), 'bún');
      await _wait(tester);
      await tester.enterText(find.byType(TextField), '');
      await _wait(tester);
      expect(find.byType(SponsoredRestaurantRow), findsOneWidget);
      expect(ads.impressions, ['ad_hanh_tam']);
      expect(ads.clicks, isEmpty);

      await tester.tap(find.text('Bún riêu chay 35k — riêu đậu hũ mềm'));
      await _wait(tester);
      expect(ads.clicks, ['ad_hanh_tam']);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsWidgets);
      await _wait(tester, 2000);
    });

    testWidgets('no row when no campaign runs (error / empty)', (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(), overrides: [
        adsApiProvider.overrideWithValue(MockAdsRepository(scenario: 'error')),
      ]);
      await _wait(tester);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
      expect(find.text('Được tài trợ'), findsNothing);
    });

    testWidgets('a "Đặt bàn" campaign shows its button too', (tester) async {
      final ad = AdFeedItemDto.fromJson({
        'id': 'ad_moc_nhien',
        'restaurantId': 'rs_moc_nhien',
        'restaurant': {
          'id': 'rs_moc_nhien',
          'name': 'Lẩu Nấm Chay Mộc Nhiên',
          'address': '88 Nguyễn Trãi, P.3, Q.5, TP.HCM',
          'isVeganCertified': true,
          'latitude': 10.7578,
          'longitude': 106.6815,
          'averageRating': 4.6,
          'reviewCount': 5,
        },
        'headline': 'Lẩu nấm 7 loại cho nhóm bạn',
        'message': '…',
        'ctaType': 'Book',
        'distanceKm': 3.0,
      });
      var shown = 0;
      await _pump(
        tester,
        Scaffold(
          body: ListView(children: [
            SponsoredRestaurantRow(ad: ad, onShown: () => shown++),
          ]),
        ),
      );
      await tester.pump();
      expect(shown, 1);
      expect(find.text('Đặt bàn'), findsOneWidget);
      expect(find.text('3,0 km'), findsOneWidget);
      expect(find.text('4,6 (5)'), findsOneWidget);
      await tester.tap(find.text('Đặt bàn'));
      await _wait(tester);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(MockAdsRepository.clicksOf('ad_moc_nhien'), 1);
      await _wait(tester, 2000);
    });
  });
}
