// test/restaurant/m2_restaurant_test.dart
// The mock repositories wait like a network (0.35–1 s per call).
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/data/mock_ads_repository.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/data/models/restaurant_model.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/domain/food_match.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/controllers/restaurant_controllers.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/maps_launcher.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_route_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/submit_restaurant_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/widgets/restaurant_filter_sheet.dart';

Matcher apiError(int status) =>
    isA<ApiException>().having((e) => e.statusCode, 'statusCode', status);

const _q1 = MockLocationService.point;

MockRestaurantRepository _repo({bool signedIn = true}) =>
    MockRestaurantRepository(
      isSignedIn: () => signedIn,
      currentUserId: () => 'u_me',
      currentUserName: () => 'Minh Anh',
    );

Future<SharedPreferences> _prefs({bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues(signedIn
      ? {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'}
      : {});
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {bool signedIn = true,
    List<Override> overrides = const [],
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(signedIn: signedIn);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() {
    MockRestaurantRepository.reset();
    MockAdsRepository.resetEvents();
  });

  group('geo', () {
    test('haversine Q.1 → Q.7 matches the reference distance', () {
      // Reference: 4.629 km (independent haversine, R = 6371 km) from the
      // mock position to "Nhà Hàng Chay Vạn Hoa", Nguyễn Thị Thập, Q.7.
      final km = haversineKm(_q1, const GeoPoint(10.738, 106.716));
      expect(km, closeTo(4.63, 0.2));
      expect(haversineKm(_q1, _q1), 0);
      expect(haversineKm(_q1, const GeoPoint(10.7812, 106.699)),
          closeTo(0.52, 0.05));
    });

    test('distance labels', () {
      expect(formatDistance(null), 'Chưa có vị trí');
      expect(formatDistance(0.01), 'Dưới 50 m');
      expect(formatDistance(0.367), '370 m');
      expect(formatDistance(0.998), '1,0 km');
      expect(formatDistance(1.234), '1,2 km');
      expect(formatDistance(12.6), '13 km');
    });
  });

  group('DTO parsing', () {
    test('null coordinates, INT ids and a scalar createdBy', () {
      final r = RestaurantDto.fromJson({
        'id': 21,
        'createdBy': 7,
        'createdByName': 'Minh Anh',
        'name': 'Quán Chay An Lạc',
        'address': '12 Nguyễn Thị Minh Khai, Q.1, TP.HCM',
        'isVeganCertified': false,
        'latitude': null,
        'longitude': null,
        'reviewCount': 0,
      }).toEntity();
      expect(r.id, '21');
      expect(r.createdById, '7');
      expect(r.createdByName, 'Minh Anh');
      expect(r.location, isNull);
      expect(r.hasLocation, isFalse);
      expect(r.distanceKm, isNull);
      expect(r.averageRating, isNull);
    });

    test('joined createdBy object, string numbers, half a coordinate pair', () {
      final r = RestaurantDto.fromJson({
        'id': 'rs_x',
        'createdBy': {'id': 'u_thao_vy', 'fullName': 'Thảo Vy'},
        'name': 'X',
        'address': 'Y',
        'isVeganCertified': true,
        'latitude': '10.78',
        'longitude': null,
        'distanceKm': 1.5,
        'averageRating': 4.6,
        'reviewCount': '38',
      }).toEntity();
      expect(r.createdById, 'u_thao_vy');
      expect(r.createdByName, 'Thảo Vy');
      expect(r.location, isNull, reason: 'half a pair is no position');
      expect(r.averageRating, 4.6);
      expect(r.reviewCount, 38);

      final full = RestaurantDto.fromJson(
          {'id': 1, 'latitude': 10.78, 'longitude': 106.7}).toEntity();
      expect(full.location, const GeoPoint(10.78, 106.7));
      expect(full.createdById, isNull);
    });

    test('review reads user.fullName and INT ids; request omits null coords',
        () {
      final v = ReviewDto.fromJson({
        'id': 301,
        'userId': 7,
        'restaurantId': 21,
        'rating': 5,
        'comment': 'Bún riêu chay đậm vị',
        'createdAt': '2026-10-15T02:00:00Z',
        'user': {'id': 7, 'fullName': 'Minh Anh'},
      }).toEntity();
      expect(v.id, '301');
      expect(v.userId, '7');
      expect(v.restaurantId, '21');
      expect(v.userName, 'Minh Anh');
      expect(v.isEdited, isFalse);

      expect(const CreateRestaurantRequestDto(name: 'A', address: 'B').toJson(),
          {'name': 'A', 'address': 'B'});
      expect(
          const CreateRestaurantRequestDto(
                  name: 'A', address: 'B', latitude: 10.7, longitude: 106.7)
              .toJson(),
          {'name': 'A', 'address': 'B', 'latitude': 10.7, 'longitude': 106.7});
      expect(
          const CreateRestaurantRequestDto(name: 'A', address: 'B', media: [
            NewRestaurantMediaDto(
                mediaType: RestaurantMediaType.image, mediaUrl: 'i.jpg'),
            NewRestaurantMediaDto(
                mediaType: RestaurantMediaType.video, mediaUrl: 'v.mp4'),
          ]).toJson()['media'],
          [
            {'mediaType': 'Image', 'mediaUrl': 'i.jpg'},
            {'mediaType': 'Video', 'mediaUrl': 'v.mp4'},
          ]);
    });

    test('restaurant media: web shape, uploader object or null', () {
      final m = RestaurantMediaDto.fromJson({
        'id': 'rm_4',
        'mediaType': 'Video',
        'mediaUrl': 'https://x/v.mp4',
        'uploadedBy': {'id': 7, 'fullName': 'Minh Anh'},
        'createdAt': '2026-10-15T02:00:00Z',
      });
      expect(m.mediaType, RestaurantMediaType.video);
      expect(m.uploadedById, '7');
      expect(m.toEntity().uploadedByName, 'Minh Anh');
      expect(m.toEntity().isVideo, isTrue);
      final admin = RestaurantMediaDto.fromJson(
          {'id': 1, 'mediaType': 'image', 'mediaUrl': 'a.jpg'});
      expect(admin.mediaType, RestaurantMediaType.image);
      expect(admin.uploadedByName, isNull);
      expect(admin.toJson()['uploadedBy'], isNull);
    });
  });

  group('food matching', () {
    test('dish words drop "chay" and accents', () {
      expect(foodTokens('Bún riêu chay'), ['bún', 'riêu']);
      expect(foodTokens('Lẩu nấm & Đậu hũ'), ['lẩu', 'nấm', 'đậu', 'hũ']);
      expect(foodTokens('bun rieu CHAY'), ['bun', 'rieu']);
      expect(foodTokens('quán chay'), isEmpty);
    });

    test('drops trailing words until something mentions the dish', () {
      final texts = {
        'a': ['Phở chay nước trong, nhiều nấm.'],
        'b': ['Bánh xèo giòn'],
        'c': ['Phở bò tái'],
      };
      expect(foodMatchScores(texts, 'Phở chay nấm đông cô'), {'a': 2, 'c': 1});
      expect(matchFood(texts, 'Phở chay nấm đông cô'), {'a'},
          reason: 'two dish words beat one');
      expect(matchFood(texts, 'phở Hà Nội'), {'a', 'c'});
      expect(matchFood(texts, 'banh xeo'), {'b'});
      expect(matchFood(texts, 'xyzxyz'), isEmpty);
    });

    test('accents typed by the user must match; bare words match any', () {
      final texts = {
        'x': ['Trưa đông nên chờ hơi lâu, nhiều nấm.']
      };
      expect(matchFood(texts, 'lẩu nấm'), isEmpty, reason: 'lẩu ≠ lâu');
      expect(matchFood(texts, 'lau nam'), {'x'});
    });
  });

  group('MockRestaurantRepository', () {
    test('nearest first; no coordinates last as "Chưa có vị trí"', () async {
      final list = await _repo().listRestaurants(near: _q1);
      expect(list.take(3).map((r) => r.id),
          ['rs_thanh_tinh', 'rs_an_lac', 'rs_nha_gao']);
      expect(list.first.distanceKm, closeTo(0.367, 0.01));
      final noPosition = list.skipWhile((r) => r.distanceKm != null).toList();
      expect(noPosition.map((r) => r.id).toSet(),
          {'rs_ut_muoi', 'rs_nha_la', 'rs_qa_fail'});
      expect(noPosition.every((r) => r.toEntity().location == null), isTrue);
      expect(formatDistance(noPosition.first.distanceKm), 'Chưa có vị trí');
      for (var i = 1; i < list.length - noPosition.length; i++) {
        expect(
            list[i].distanceKm!, greaterThanOrEqualTo(list[i - 1].distanceKm!));
      }
    });

    test('certified filter and rating sort', () async {
      final repo = _repo();
      final certified =
          await repo.listRestaurants(near: _q1, certifiedOnly: true);
      expect(certified, hasLength(9));
      expect(certified.every((r) => r.isVeganCertified), isTrue);

      final byRating =
          await repo.listRestaurants(near: _q1, sort: RestaurantSort.rating);
      expect(byRating.take(3).map((r) => r.id),
          ['rs_hanh_tam', 'rs_sen_hong', 'rs_moc_nhien']);
      expect(byRating.first.averageRating, closeTo(4.75, 0.001));
      expect(byRating.last.id, 'rs_nha_la', reason: 'no reviews → last');
      final rated = byRating.where((r) => r.reviewCount > 0).toList();
      for (var i = 1; i < rated.length; i++) {
        expect(rated[i].averageRating!,
            lessThanOrEqualTo(rated[i - 1].averageRating!));
      }
    });

    test('radius keeps places within it (and drops unplaced ones)', () async {
      final repo = _repo();
      final in1 = await repo.listRestaurants(near: _q1, radiusKm: 1);
      expect(in1.map((r) => r.id), ['rs_thanh_tinh', 'rs_an_lac']);
      final in5 = await repo.listRestaurants(near: _q1, radiusKm: 5);
      expect(in5, hasLength(9));
      expect(in5.every((r) => r.distanceKm! <= 5), isTrue);
      expect(in5.map((r) => r.id), isNot(contains('rs_ut_muoi')));
      // Without a position the radius means nothing.
      expect(await repo.listRestaurants(radiusKm: 1), hasLength(14));
    });

    test('media: seeds like the web, oldest first', () async {
      final repo = _repo();
      final media = await repo.getMedia('rs_hanh_tam');
      expect(media.map((m) => m.id), ['rm_3', 'rm_4']);
      expect(media.last.mediaType, RestaurantMediaType.video);
      expect(media.first.mediaUrl,
          'https://res.cloudinary.com/veganlife/image/upload/v1/restaurants/hanh_tam_to_bun.jpg');
      expect(await repo.getMedia('rs_thanh_tinh'), isEmpty);
      await expectLater(repo.getMedia('rs_khong_co'), throwsA(apiError(404)));
    });

    test('query matches name, address or a dish in the reviews', () async {
      final repo = _repo();
      final byDish = await repo.listRestaurants(near: _q1, query: 'lẩu nấm');
      expect(byDish.map((r) => r.id).toSet(),
          {'rs_moc_nhien', 'rs_sen_hong', 'rs_van_hoa'});
      final byAddress =
          await repo.listRestaurants(near: _q1, query: 'Nguyễn Thị Thập');
      expect(byAddress.map((r) => r.id), ['rs_van_hoa']);
      expect(await repo.listRestaurants(query: 'xyzxyz'), isEmpty);
      await expectLater(
          repo.listRestaurants(query: 'quán #fail'), throwsA(apiError(503)));
    });

    test('suggestedForFood("bun rieu") without diacritics', () async {
      final list = await _repo().suggestedForFood('bun rieu', near: _q1);
      expect(list.map((r) => r.id), ['rs_an_lac', 'rs_hanh_tam']);
      final pho = await _repo()
          .suggestedForFood('Phở chay nấm đông cô', near: _q1, limit: 3);
      expect(pho.map((r) => r.id), ['rs_an_lac', 'rs_bo_de'],
          reason: '"phở … nấm … đông" outranks "phở … nấm"');
    });

    test('review upsert: one per member, average and count recomputed',
        () async {
      await expectLater(
          _repo(signedIn: false).upsertReview('rs_thanh_tinh',
              rating: 4, comment: 'Cơm chay văn phòng ngon'),
          throwsA(apiError(401)));

      final repo = _repo();
      final before = await repo.getRestaurant('rs_thanh_tinh');
      expect(before.reviewCount, 3);
      expect(before.averageRating, closeTo(10 / 3, 0.001));

      final first = await repo.upsertReview('rs_thanh_tinh',
          rating: 4, comment: 'Cơm chay văn phòng ngon, giao nhanh.');
      var r = await repo.getRestaurant('rs_thanh_tinh');
      expect(r.reviewCount, 4);
      expect(r.averageRating, closeTo(3.5, 0.001));
      var reviews = await repo.getReviews('rs_thanh_tinh');
      expect(reviews.first.id, first.id, reason: 'newest first');
      expect(reviews.first.userName, 'Minh Anh');

      final second = await repo.upsertReview('rs_thanh_tinh',
          rating: 2, comment: 'Lần này hơi nguội, chờ lâu.');
      expect(second.id, first.id, reason: 'replaced, not added');
      expect(second.updatedAt, isNotNull);
      r = await repo.getRestaurant('rs_thanh_tinh');
      expect(r.reviewCount, 4, reason: 'count unchanged');
      expect(r.averageRating, closeTo(3.0, 0.001));
      reviews = await repo.getReviews('rs_thanh_tinh');
      expect(reviews.where((v) => v.userId == 'u_me'), hasLength(1));
      expect(reviews.first.comment, 'Lần này hơi nguội, chờ lâu.');
    });

    test('review validation and #fail', () async {
      final repo = _repo();
      await expectLater(
          repo.upsertReview('rs_an_lac', rating: 0, comment: 'Ngon lắm luôn á'),
          throwsA(apiError(400)));
      await expectLater(
          repo.upsertReview('rs_an_lac', rating: 5, comment: 'Ngon'),
          throwsA(apiError(400)));
      await expectLater(
          repo.upsertReview('rs_an_lac',
              rating: 5, comment: 'Thử lỗi máy chủ #fail'),
          throwsA(apiError(503)));
      await expectLater(
          repo.upsertReview('rs_qa_fail',
              rating: 5, comment: 'Quán thử nghiệm ngon'),
          throwsA(apiError(503)));
      await expectLater(
          repo.getRestaurant('rs_khong_co'), throwsA(apiError(404)));
    });

    test('a suggested restaurant: uncertified, created by me, listed',
        () async {
      await expectLater(
          _repo(signedIn: false).createRestaurant(
              const CreateRestaurantRequestDto(
                  name: 'Cơm chay Hoa Sen', address: '9 Lý Tự Trọng, Q.1')),
          throwsA(apiError(401)));

      final repo = _repo();
      final created = (await repo.createRestaurant(
              const CreateRestaurantRequestDto(
                  name: 'Cơm chay Hoa Sen',
                  address: '9 Lý Tự Trọng, P. Bến Nghé, Q.1')))
          .toEntity();
      expect(created.isVeganCertified, isFalse);
      expect(created.createdById, 'u_me');
      expect(created.createdByName, 'Minh Anh');
      expect(created.location, isNull);
      expect(created.reviewCount, 0);
      expect(created.averageRating, isNull);

      final list = await repo.listRestaurants(near: _q1);
      final listed = list.firstWhere((r) => r.id == created.id);
      expect(listed.distanceKm, isNull);

      final withCoords = await repo.createRestaurant(CreateRestaurantRequestDto(
          name: 'Bếp chay Góc Phố',
          address: '20 Pasteur, P. Bến Nghé, Q.1',
          latitude: _q1.latitude,
          longitude: _q1.longitude));
      expect((await repo.getRestaurant(withCoords.id, near: _q1)).distanceKm,
          closeTo(0, 0.001));

      await expectLater(
          repo.createRestaurant(const CreateRestaurantRequestDto(
              name: 'Cơm chay Hoa Sen',
              address: '9 Lý Tự Trọng, P. Bến Nghé, Q.1')),
          throwsA(apiError(409)));
      await expectLater(
          repo.createRestaurant(const CreateRestaurantRequestDto(
              name: 'AB', address: '9 Lý Tự Trọng, Q.1')),
          throwsA(apiError(400)));
    });

    test('a suggestion keeps its media; 5 photos and 1 video at most',
        () async {
      final repo = _repo();
      NewRestaurantMediaDto img(int i) => NewRestaurantMediaDto(
          mediaType: RestaurantMediaType.image, mediaUrl: 'https://x/$i.jpg');
      const video = NewRestaurantMediaDto(
          mediaType: RestaurantMediaType.video, mediaUrl: 'https://x/v.mp4');
      final created = await repo.createRestaurant(CreateRestaurantRequestDto(
        name: 'Chay Góc Nhỏ',
        address: '15 Lê Thánh Tôn, P. Bến Nghé, Q.1',
        latitude: 10.7801,
        longitude: 106.7011,
        media: [img(1), img(2), video],
      ));
      final media = await repo.getMedia(created.id);
      expect(media.map((m) => m.mediaUrl),
          ['https://x/1.jpg', 'https://x/2.jpg', 'https://x/v.mp4']);
      expect(media.every((m) => m.uploadedByName == 'Minh Anh'), isTrue);

      await expectLater(
          repo.createRestaurant(CreateRestaurantRequestDto(
              name: 'Chay Sáu Ảnh',
              address: '16 Lê Thánh Tôn, P. Bến Nghé, Q.1',
              media: [for (var i = 0; i < 6; i++) img(i)])),
          throwsA(apiError(400)));
      await expectLater(
          repo.createRestaurant(const CreateRestaurantRequestDto(
              name: 'Chay Hai Video',
              address: '17 Lê Thánh Tôn, P. Bến Nghé, Q.1',
              media: [video, video])),
          throwsA(apiError(400)));
    });
  });

  group('RestaurantDetailState', () {
    test('withReview swaps the member review and recomputes', () {
      final base = RestaurantDetailState(
        restaurant: const Restaurant(
            id: 'r',
            name: 'R',
            address: 'A',
            isVeganCertified: true,
            averageRating: 4,
            reviewCount: 2),
        reviews: [
          RestaurantReview(
              id: 'v1',
              restaurantId: 'r',
              userId: 'u_me',
              userName: 'Minh Anh',
              rating: 5,
              comment: 'c',
              createdAt: DateTime(2026)),
          RestaurantReview(
              id: 'v2',
              restaurantId: 'r',
              userId: 'u_x',
              userName: 'X',
              rating: 3,
              comment: 'c',
              createdAt: DateTime(2026)),
        ],
      );
      expect(base.starCounts, [0, 0, 1, 0, 1]);
      final next = base.withReview(RestaurantReview(
          id: 'v1',
          restaurantId: 'r',
          userId: 'u_me',
          userName: 'Minh Anh',
          rating: 1,
          comment: 'edited',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026, 2)));
      expect(next.reviews.first.comment, 'edited');
      expect(next.restaurant.reviewCount, 2);
      expect(next.restaurant.averageRating, 2);
      expect(next.reviewBy('u_me')?.rating, 1);
      expect(next.reviewBy(null), isNull);
    });
  });

  group('screens', () {
    testWidgets('guest: compact header, sponsored row, filter sheet',
        (tester) async {
      await _pumpApp(tester, const RestaurantNearbyScreen(),
          signedIn: false, size: const Size(411, 4000));
      expect(find.text('Quán chay gần bạn'), findsOneWidget);
      await _wait(tester);
      expect(
          find.text('Gần: Quận 1, TP.HCM (vị trí mô phỏng)'), findsOneWidget);
      expect(find.text('Tìm tên quán, địa chỉ, món…'), findsOneWidget);
      expect(find.text('Bộ lọc'), findsOneWidget);
      expect(find.byTooltip('Xem bản đồ'), findsOneWidget);
      // The old inline chips and sort buttons moved into the sheet.
      expect(find.text('Gần nhất'), findsNothing);
      expect(find.text('Đã chứng nhận thuần chay'), findsNothing);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
      expect(find.text('370 m'), findsOneWidget);
      expect(find.text('Chưa có vị trí'), findsNWidgets(3));
      expect(find.text('4,5 (4)'), findsOneWidget, reason: 'An Lạc');
      expect(find.text('Gợi ý quán mới'), findsOneWidget);
      // Exactly one sponsored row, above the organic list.
      expect(find.text('Được tài trợ'), findsOneWidget);
      final ad = tester.getTopLeft(find.text('Được tài trợ')).dy;
      final first = tester.getTopLeft(find.text('Chay Thanh Tịnh')).dy;
      final last = tester.getTopLeft(find.text('Quán Chay Nhà Lá')).dy;
      expect(ad, lessThan(first));
      expect(first, lessThan(last));

      await tester.tap(find.text('Bộ lọc'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RestaurantFilterSheet), findsOneWidget);
      expect(find.text('Chỉ quán đã chứng nhận thuần chay'), findsOneWidget);
      for (final label in [
        'Gần nhất',
        'Đánh giá cao',
        '1 km',
        '3 km',
        '5 km',
        '10 km',
        'Không giới hạn',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('Chỉ quán đã chứng nhận thuần chay'));
      await tester.tap(find.text('Đánh giá cao'));
      await tester.tap(find.text('5 km'));
      await tester.pump();
      await tester.tap(find.text('Áp dụng'));
      await _wait(tester);
      expect(find.byType(RestaurantFilterSheet), findsNothing);
      expect(find.text('8 quán · trong 5 km · đánh giá cao trước'),
          findsOneWidget);
      expect(find.text('Chay Thanh Tịnh'), findsNothing, reason: 'uncertified');
      expect(find.text('Chưa có vị trí'), findsNothing);
      // Badge + removable chips.
      expect(find.text('3'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Đã chứng nhận'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Trong 5 km'), findsOneWidget);
      // 4,75★ is also the sponsored row, which fits these filters: on top,
      // and not repeated in the list.
      final top = tester.getTopLeft(find.text('Bún Riêu Chay Hạnh Tâm')).dy;
      final next = tester.getTopLeft(find.text('Bếp Chay Sen Hồng')).dy;
      expect(top, lessThan(next), reason: '4,75★ first');

      await tester.tap(find.byTooltip('Bỏ giới hạn bán kính'));
      await _wait(tester);
      expect(find.text('9 quán · đánh giá cao trước'), findsOneWidget);

      // "Đặt lại" in the sheet clears everything.
      await tester.tap(find.text('Bộ lọc'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Đặt lại'));
      await tester.pump();
      await tester.tap(find.text('Áp dụng'));
      await _wait(tester);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('initial query filters by dish; #fail shows retry',
        (tester) async {
      await _pumpApp(
          tester, const RestaurantNearbyScreen(initialQuery: 'bún riêu'),
          signedIn: false, size: const Size(411, 1600));
      await _wait(tester);
      expect(find.text('2 quán · gần nhất trước'), findsOneWidget);
      expect(find.text('Quán Chay An Lạc'), findsOneWidget);
      // The sponsored row on top stands for its place: no second row.
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsOneWidget);
      expect(find.text('Được tài trợ'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'xyzxyz');
      await _wait(tester);
      expect(find.text('Chưa có quán nào khớp'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '#fail');
      await _wait(tester);
      expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
    });

    testWidgets('large text on a small phone: no overflow', (tester) async {
      await _pumpApp(tester, const RestaurantNearbyScreen(),
          signedIn: false, size: const Size(360, 780), textScale: 2);
      await _wait(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Chay Thanh Tịnh'), findsOneWidget);
    });

    testWidgets('guest "Viết đánh giá" asks to sign in', (tester) async {
      await _pumpApp(
          tester, const RestaurantDetailScreen(restaurantId: 'rs_thanh_tinh'),
          signedIn: false, size: const Size(411, 1600));
      await _wait(tester);
      expect(find.text('Chay Thanh Tịnh'), findsWidgets);
      expect(find.text('Chưa chứng nhận — Ban quản trị đang xác minh'),
          findsOneWidget);
      expect(find.text('3 đánh giá'), findsOneWidget);
      await tester.tap(find.text('Viết đánh giá'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
      expect(
          find.text('Đăng nhập để viết đánh giá quán chay.'), findsOneWidget);
      expect(find.text('Gửi đánh giá'), findsNothing);
    });

    testWidgets(
        'detail: embedded map, in-app "Chỉ đường", Google Maps only in the '
        'overflow, "Ảnh & video"', (tester) async {
      final opened = <Uri>[];
      await _pumpApp(
        tester,
        const RestaurantDetailScreen(restaurantId: 'rs_an_lac'),
        size: const Size(411, 1600),
        overrides: [
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      await _wait(tester);
      expect(find.text('Mở bản đồ'), findsNothing);
      expect(find.text('Mở bằng Google Maps'), findsNothing);
      expect(find.byTooltip('Mở bản đồ lớn'), findsOneWidget);
      expect(find.text('Ảnh & video (2)'), findsOneWidget);

      await tester.tap(find.text('Chỉ đường'));
      await _wait(tester, 1000);
      expect(find.byType(RestaurantRouteScreen), findsOneWidget);
      expect(opened, isEmpty, reason: 'no navigation to Google Maps');
      // Tests route with the straight line (no OSRM under flutter test).
      expect(find.text('Không tải được tuyến đường — hiển thị đường thẳng'),
          findsOneWidget);
      expect(find.text('520 m (đường chim bay)'), findsOneWidget);
      expect(find.text('Từ: Quận 1, TP.HCM (vị trí mô phỏng)'), findsOneWidget);
      await tester.pageBack();
      await _wait(tester, 800);

      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Mở bằng Google Maps'));
      await tester.pump();
      expect(opened, hasLength(1));
      expect(opened.single.host, 'www.google.com');
      expect(opened.single.path, '/maps/dir/');
      expect(opened.single.queryParameters,
          {'api': '1', 'destination': '10.7812,106.699'});
    });

    testWidgets('detail without coordinates: note, no "Chỉ đường"',
        (tester) async {
      final opened = <Uri>[];
      await _pumpApp(
        tester,
        const RestaurantDetailScreen(restaurantId: 'rs_ut_muoi'),
        size: const Size(411, 1600),
        overrides: [
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
      );
      await _wait(tester);
      expect(find.textContaining('Quán chưa có vị trí trên bản đồ'),
          findsOneWidget);
      expect(find.text('Chỉ đường'), findsNothing);
      expect(find.byTooltip('Mở bản đồ lớn'), findsNothing);
      expect(find.text('Ảnh & video (3)'), findsOneWidget);
      await tester.tap(find.byTooltip('Thêm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Mở bằng Google Maps'));
      await tester.pump();
      expect(opened.single.path, '/maps/search/');
    });

    testWidgets('member: own review first, write then replace', (tester) async {
      await _pumpApp(
          tester, const RestaurantDetailScreen(restaurantId: 'rs_thanh_tinh'),
          size: const Size(411, 2000));
      await _wait(tester);
      await tester.tap(find.text('Viết đánh giá'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Viết đánh giá'), findsWidgets);

      await tester.tap(find.text('Gửi đánh giá'));
      await tester.pump();
      expect(find.text('Chọn số sao'), findsOneWidget);
      expect(find.text('Nhận xét cần ít nhất 10 ký tự'), findsOneWidget);

      await tester.tap(find.byTooltip('4 sao'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Nhận xét'),
          'Cơm văn phòng ngon, giao nhanh.');
      await tester.tap(find.text('Gửi đánh giá'));
      await _wait(tester, 2500);
      expect(find.text('Cảm ơn bạn! Đánh giá đã được đăng.'), findsOneWidget);
      expect(find.text('4 đánh giá'), findsOneWidget);
      expect(find.text('Sửa đánh giá của bạn'), findsOneWidget);
      expect(find.text('Bạn'), findsOneWidget);
      final mine =
          tester.getTopLeft(find.text('Cơm văn phòng ngon, giao nhanh.')).dy;
      final other =
          tester.getTopLeft(find.text('Mì xào chay giòn, rau cải ngọt.')).dy;
      expect(mine, lessThan(other), reason: 'own review first');
      await _wait(tester, 5000); // snackbar

      await tester.tap(find.text('Sửa đánh giá của bạn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('2 sao'));
      await tester.tap(find.text('Gửi đánh giá'));
      await _wait(tester, 2500);
      expect(find.text('Đã cập nhật đánh giá của bạn.'), findsOneWidget);
      expect(find.text('4 đánh giá'), findsOneWidget, reason: 'replaced');
      expect(find.textContaining('đã sửa'), findsOneWidget);
      await _wait(tester, 5000);
    });

    testWidgets('submitting a restaurant opens its detail', (tester) async {
      await _pumpApp(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1200));
      expect(find.text('Gợi ý quán mới'), findsOneWidget);
      expect(
          find.text('Quán mới hiển thị ngay với nhãn Chưa chứng nhận. '
              'Ban quản trị sẽ xác minh trước khi gắn nhãn Chứng nhận chay.'),
          findsOneWidget);

      await tester.tap(find.text('Gửi gợi ý'));
      await tester.pump();
      expect(find.text('Tên quán cần ít nhất 3 ký tự'), findsOneWidget);
      expect(find.text('Địa chỉ cần ít nhất 10 ký tự'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên quán'), 'Cơm chay Hoa Sen');
      await tester.enterText(find.widgetWithText(TextFormField, 'Địa chỉ'),
          '9 Lý Tự Trọng, P. Bến Nghé, Q.1');
      await tester.tap(find.text('Gửi gợi ý'));
      await _wait(tester, 3000);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(find.text('Được gợi ý bởi Minh Anh'), findsOneWidget);
      expect(find.text('Chưa chứng nhận — Ban quản trị đang xác minh'),
          findsOneWidget);
      expect(find.textContaining('Chưa có vị trí'), findsWidgets);
      expect(find.text('Chưa có đánh giá'), findsWidgets);
      await _wait(tester, 5000); // snackbar
    });

    testWidgets(
        'suggesting with "Dùng vị trí hiện tại" and a photo: the detail '
        'shows the map and the photo', (tester) async {
      await _pumpApp(tester, const SubmitRestaurantScreen(),
          size: const Size(411, 1800),
          overrides: [
            mediaApiProvider.overrideWithValue(
                MockMediaRepository(tick: const Duration(milliseconds: 50))),
          ]);
      expect(find.text('Vị trí quán'), findsOneWidget);
      expect(
          find.text('Chưa có vị trí trên bản đồ — mọi người sẽ không thấy '
              'khoảng cách và chỉ đường'),
          findsOneWidget);
      expect(
          find.text('Ảnh & video giới thiệu (không bắt buộc)'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên quán'), 'Chay Góc Phố');
      await tester.tap(find.text('Dùng vị trí hiện tại'));
      await _wait(tester, 500);
      expect(find.textContaining('Chưa có vị trí trên bản đồ —'), findsNothing);
      // The address was filled in and stays editable.
      expect(find.text('7 Công trường Lam Sơn, P. Bến Nghé, Q.1, TP.HCM'),
          findsOneWidget);
      expect(find.textContaining('10.77690, 106.70090'), findsOneWidget);

      // A photo from the mock samples, then the 14 MB one is refused.
      await tester.tap(find.text('Thêm ảnh/video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('dau_hu_sot_ca.jpg'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Đang tải ảnh/video lên…'), findsOneWidget);
      await _wait(tester, 1000);
      expect(find.text('Gửi gợi ý'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(find.text('Thêm ảnh/video'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('anh_qua_lon.png'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          find.text('Ảnh vượt quá 10 MB. Chọn tệp khác nhé.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await _wait(tester, 5000); // snackbar

      await tester.tap(find.text('Gửi gợi ý'));
      await _wait(tester, 3000);
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      expect(find.text('Được gợi ý bởi Minh Anh'), findsOneWidget);
      expect(find.byTooltip('Mở bản đồ lớn'), findsOneWidget);
      expect(find.text('Dưới 50 m'), findsOneWidget);
      expect(find.text('Ảnh & video (1)'), findsOneWidget);
      expect(find.text('Chỉ đường'), findsOneWidget);
      await _wait(tester, 5000); // snackbar
    });
  });
}
