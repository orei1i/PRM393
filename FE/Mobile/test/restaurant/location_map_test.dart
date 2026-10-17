// test/restaurant/location_map_test.dart
// Changing the user's location (address search, map pick, simulated
// current), the in-app maps (tiles off under test, or an offline fake tile
// provider) and in-app directions (OSRM parsing, straight-line fallback).
// Nothing here touches the network.
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/env.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/ads/data/mock_ads_repository.dart';
import 'package:veganlife_mobile/features/restaurant/data/geocoding_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/data/routing_service.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/location_picker_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_nearby_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_route_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/widgets/vl_map.dart';

const _q1 = MockLocationService.point;
const _benThanh = GeoPoint(10.7725, 106.698);

const _anLac = Restaurant(
  id: 'rs_an_lac',
  name: 'Quán Chay An Lạc',
  address: '12 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP.HCM',
  isVeganCertified: true,
  location: GeoPoint(10.7812, 106.699),
);

Future<SharedPreferences> _prefs(
    [Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<ProviderContainer> _container(
    {Map<String, Object> prefs = const {},
    List<Override> overrides = const []}) async {
  final p = await _prefs(prefs);
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(p),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const [],
    Size size = const Size(411, 900)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final p = await _prefs(
      {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'});
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

/// A button that opens [route] and keeps what it returns.
class _Opener<T> extends StatelessWidget {
  const _Opener({required this.route, required this.onResult});

  final Route<T> Function() route;
  final ValueChanged<T?> onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async =>
                onResult(await Navigator.of(context).push(route())),
            child: const Text('Mở'),
          ),
        ),
      );
}

class _FakeRouting implements RoutingService {
  _FakeRouting(this.answer);

  final Future<RouteResult> Function(GeoPoint from, GeoPoint to) answer;
  final calls = <(GeoPoint, GeoPoint)>[];

  @override
  Future<RouteResult> route(GeoPoint from, GeoPoint to) {
    calls.add((from, to));
    return answer(from, to);
  }
}

/// Answers every request with [body] and records the URLs.
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final Map<String, dynamic> body;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.uri);
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Offline tiles: a 1×1 transparent PNG for every tile.
class _OfflineTiles extends TileProvider {
  static final _png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  int requested = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requested++;
    return MemoryImage(_png);
  }
}

/// A slow drag that ends still, so the map does not fling.
Future<void> _pan(WidgetTester tester, Finder target, Offset by) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(by / 10);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 150));
  await gesture.up();
  await tester.pump();
}

Finder _pin(String name) =>
    find.byWidgetPredicate((w) => w is RestaurantPin && w.label == name);

void main() {
  setUp(() {
    MockRestaurantRepository.reset();
    MockAdsRepository.resetEvents();
    OsrmRoutingService.clearCache();
  });

  group('user location', () {
    test('JSON round trip; unreadable values are ignored', () {
      const l = UserLocation(
        point: _benThanh,
        label: 'Chợ Bến Thành',
        source: UserLocationSource.search,
        address: 'Lê Lợi, P. Bến Thành, Q.1, TP.HCM',
        city: 'TP. Hồ Chí Minh',
      );
      final back = UserLocation.fromJson(
          jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>)!;
      expect(back.point, _benThanh);
      expect(back.label, 'Chợ Bến Thành');
      expect(back.source, UserLocationSource.search);
      expect(back.address, l.address);
      expect(back.city, 'TP. Hồ Chí Minh');
      expect(back.isSimulated, isFalse);
      expect(UserLocation.fromJson({'lat': 1}), isNull);
      expect(UserLocation.fromJson('x'), isNull);
    });

    test('starts simulated in Q.1; a choice persists across restarts',
        () async {
      var c = await _container();
      final start = await c.read(userLocationProvider.future);
      expect(start.point, _q1);
      expect(start.label, 'Quận 1, TP.HCM (vị trí mô phỏng)');
      expect(start.isSimulated, isTrue);
      expect(start.city, 'TP. Hồ Chí Minh');

      const picked = UserLocation(
          point: _benThanh,
          label: 'Chợ Bến Thành',
          source: UserLocationSource.search);
      await c.read(userLocationProvider.notifier).setLocation(picked);
      expect(c.read(userLocationProvider).requireValue.label, 'Chợ Bến Thành');
      final prefs = c.read(sharedPreferencesProvider);
      expect(prefs.getString('vl.user_location'), contains('Chợ Bến Thành'));
      expect(c.read(recentLocationsProvider).map((l) => l.label),
          ['Chợ Bến Thành']);

      // "Restart": a new container over the same storage.
      c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final restored = await c.read(userLocationProvider.future);
      expect(restored.point, _benThanh);
      expect(restored.label, 'Chợ Bến Thành');
      expect(c.read(recentLocationsProvider), hasLength(1));

      // Back to the simulated position; it is not a "recent" place.
      final current = await c.read(userLocationProvider.notifier).useCurrent();
      expect(current.isSimulated, isTrue);
      expect(c.read(recentLocationsProvider), hasLength(1));
    });

    test('recent places: newest first, no duplicates, at most 5', () async {
      final c = await _container();
      final notifier = c.read(recentLocationsProvider.notifier);
      for (var i = 0; i < 7; i++) {
        await notifier.add(UserLocation(
            point: GeoPoint(10.7 + i / 100, 106.7),
            label: 'P$i',
            source: UserLocationSource.map));
      }
      await notifier.add(const UserLocation(
          point: GeoPoint(10.7 + 4 / 100, 106.7),
          label: 'P4',
          source: UserLocationSource.map));
      expect(c.read(recentLocationsProvider).map((l) => l.label),
          ['P4', 'P6', 'P5', 'P3', 'P2']);
    });
  });

  group('mock geocoder', () {
    const geo = MockGeocodingService();

    test('search without accents; names first; #fail → 503', () async {
      final hits = await geo.search('ben thanh');
      expect(hits.first.name, 'Chợ Bến Thành');
      expect(hits.first.city, 'TP. Hồ Chí Minh');
      expect((await geo.search('hoan kiem')).first.city, 'Hà Nội');
      expect((await geo.search('Đà Nẵng')).length, 4);
      expect(await geo.search('  '), isEmpty);
      expect(await geo.search('xyzxyz'), isEmpty);
      await expectLater(geo.search('quận 1 #fail'),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 503)));
      expect(MockGeocodingService.places.length, greaterThanOrEqualTo(20));
    });

    test('reverse: exact place, near a place, far away', () async {
      expect((await geo.reverse(_benThanh))!.name, 'Chợ Bến Thành');
      final near = (await geo.reverse(const GeoPoint(10.7735, 106.6990)))!;
      expect(near.name, 'Gần Chợ Bến Thành');
      expect(near.point, const GeoPoint(10.7735, 106.6990));
      final suburb = (await geo.reverse(const GeoPoint(10.90, 106.70)))!;
      expect(suburb.name, 'Vị trí đã chọn');
      expect(suburb.city, 'TP. Hồ Chí Minh');
      expect(await geo.reverse(const GeoPoint(12.5, 109.2)), isNull);
    });
  });

  group('routing', () {
    final osrmOk = {
      'code': 'Ok',
      'routes': [
        {
          'distance': 2604.3,
          'duration': 540.1,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [106.7009, 10.7769],
              [106.6995, 10.7790],
              [106.699, 10.7812],
            ],
          },
        },
      ],
    };

    test('OSRM URL: driving, lng,lat order, GeoJSON overview', () {
      final uri = OsrmRoutingService(baseUrl: 'https://router.example.org/')
          .routeUri(_q1, _anLac.location!);
      expect(
          uri.toString(),
          'https://router.example.org/route/v1/driving/106.700900,10.776900;'
          '106.699000,10.781200'
          '?overview=full&geometries=geojson&alternatives=false&steps=false');
      expect(Env.osrmBaseUrl, 'https://router.project-osrm.org');
    });

    test('parse: [lng, lat] → points, metres → km, seconds; errors throw', () {
      final r =
          OsrmRoutingService.parse(osrmOk, from: _q1, to: _anLac.location!);
      expect(r.points.first, const GeoPoint(10.7769, 106.7009));
      expect(r.points, hasLength(3));
      expect(r.distanceKm, closeTo(2.604, 0.001));
      expect(r.durationSeconds, closeTo(540, 1));
      expect(r.isStraightLine, isFalse);
      expect(
          '${formatDistance(r.distanceKm)} · ${formatTravelTime(r.durationSeconds!)}',
          '2,6 km · ≈ 9 phút');
      expect(
          () => OsrmRoutingService.parse({'code': 'NoRoute'},
              from: _q1, to: _anLac.location!),
          throwsA(isA<RoutingException>()));
      expect(
          () => OsrmRoutingService.parse({'code': 'Ok', 'routes': []},
              from: _q1, to: _anLac.location!),
          throwsA(isA<RoutingException>()));
    });

    test('one request per pair, then the in-memory cache', () async {
      final adapter = _JsonAdapter(osrmOk);
      final service = OsrmRoutingService(
          baseUrl: 'https://router.example.org',
          dio: Dio()..httpClientAdapter = adapter);
      final a = await service.route(_q1, _anLac.location!);
      final b = await service.route(_q1, _anLac.location!);
      expect(identical(a, b), isTrue);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.path,
          '/route/v1/driving/106.700900,10.776900;106.699000,10.781200');
    });

    test('travel time labels', () {
      expect(formatTravelTime(20), '≈ 1 phút');
      expect(formatTravelTime(540), '≈ 9 phút');
      expect(formatTravelTime(3600), '≈ 1 giờ');
      expect(formatTravelTime(3900), '≈ 1 giờ 5 phút');
    });

    test('routeProvider: any failure → straight line + haversine', () async {
      final failing = _FakeRouting((_, __) async => throw Exception('down'));
      final c = await _container(
          overrides: [routingServiceProvider.overrideWithValue(failing)]);
      final sub = c.listen(routeProvider((_q1, _anLac.location!)), (_, __) {});
      addTearDown(sub.close);
      final r = await c.read(routeProvider((_q1, _anLac.location!)).future);
      expect(r.isStraightLine, isTrue);
      expect(r.points, [_q1, _anLac.location!]);
      expect(r.distanceKm, closeTo(0.52, 0.01));
      expect(r.durationSeconds, isNull);
      expect(failing.calls, hasLength(1));
    });
  });

  group('location picker', () {
    testWidgets(
        'location chip → search an address → distances, order and the '
        'sponsored row follow; the choice is saved', (tester) async {
      await _pump(tester, const RestaurantNearbyScreen(),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(
          find.text('Gần: Quận 1, TP.HCM (vị trí mô phỏng)'), findsOneWidget);
      expect(find.text('Bún riêu chay 35k — riêu đậu hũ mềm'), findsOneWidget);

      await tester.tap(find.text('Gần: Quận 1, TP.HCM (vị trí mô phỏng)'));
      await _wait(tester, 500);
      expect(find.byType(LocationPickerScreen), findsOneWidget);
      expect(find.text('Chọn vị trí'), findsOneWidget);
      expect(find.text('Dùng vị trí hiện tại (mô phỏng)'), findsOneWidget);
      expect(find.text('Vị trí gần đây'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Tìm địa chỉ, phường, quận…'),
          'phu my hung');
      await _wait(tester, 1000);
      await tester.tap(find.text('Phú Mỹ Hưng'));
      await _wait(tester, 2000);

      expect(find.byType(LocationPickerScreen), findsNothing);
      expect(find.text('Gần: Phú Mỹ Hưng'), findsOneWidget);
      // Q.7 places first now; Mộc Nhiên is the nearest campaign.
      final vanHoa = tester.getTopLeft(find.text('Nhà Hàng Chay Vạn Hoa')).dy;
      final coBa = tester.getTopLeft(find.text('Bánh Xèo Chay Cô Ba Hiền')).dy;
      final thanhTinh = tester.getTopLeft(find.text('Chay Thanh Tịnh')).dy;
      expect(vanHoa, lessThan(coBa));
      expect(coBa, lessThan(thanhTinh));
      expect(find.text('1,1 km'), findsOneWidget);
      expect(find.text('Lẩu nấm 7 loại cho nhóm bạn'), findsOneWidget);
      expect(find.text('Bún riêu chay 35k — riêu đậu hũ mềm'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vl.user_location'), contains('Phú Mỹ Hưng'));

      // The place is offered again under "Vị trí gần đây".
      await tester.tap(find.text('Gần: Phú Mỹ Hưng'));
      await _wait(tester, 500);
      expect(find.text('Vị trí gần đây'), findsOneWidget);
      await tester.tap(find.text('Dùng vị trí hiện tại (mô phỏng)'));
      await _wait(tester, 2000);
      expect(
          find.text('Gần: Quận 1, TP.HCM (vị trí mô phỏng)'), findsOneWidget);
      expect(find.text('370 m'), findsOneWidget);
    });

    testWidgets('"Chọn trên bản đồ": drag, the address follows the pin',
        (tester) async {
      UserLocation? result;
      await _pump(
        tester,
        _Opener<UserLocation>(
          route: () => LocationPickerScreen.route(
              initial:
                  const UserLocation(point: _benThanh, label: 'Chợ Bến Thành'),
              startOnMap: true),
          onResult: (r) => result = r,
        ),
      );
      await tester.tap(find.text('Mở'));
      await _wait(tester, 1500);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(CenterPin), findsOneWidget);
      expect(find.text('Bản đồ nền đang tắt'), findsOneWidget);
      expect(find.text('Chợ Bến Thành'), findsOneWidget);

      await _pan(tester, find.byType(FlutterMap), const Offset(-60, -40));
      expect(find.text('Đang xác định địa chỉ…'), findsOneWidget);
      await _wait(tester, 2500);
      expect(find.text('Gần Chợ Bến Thành'), findsOneWidget);

      await tester.tap(find.text('Dùng vị trí này'));
      await _wait(tester, 800);
      expect(result, isNotNull);
      expect(result!.source, UserLocationSource.map);
      expect(result!.label, 'Gần Chợ Bến Thành');
      expect(result!.point, isNot(_benThanh));
      expect(haversineKm(result!.point, _benThanh), lessThan(1.5));
    });

    testWidgets('no match offers the map; closing returns nothing',
        (tester) async {
      UserLocation? result;
      var closed = false;
      await _pump(
        tester,
        _Opener<UserLocation>(
          route: LocationPickerScreen.route,
          onResult: (r) {
            result = r;
            closed = true;
          },
        ),
      );
      await tester.tap(find.text('Mở'));
      await _wait(tester, 800);
      await tester.enterText(find.byType(TextField), 'xyzxyz');
      await _wait(tester, 1000);
      expect(find.textContaining('Không tìm thấy địa chỉ phù hợp'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Chọn trên bản đồ'));
      await _wait(tester, 800);
      expect(find.text('Dùng vị trí này'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 800);
      expect(closed, isTrue);
      expect(result, isNull);
    });
  });

  group('map mode', () {
    testWidgets(
        'list ⇄ map; pins (sponsored ringed); preview → "Chỉ đường"; '
        '"Tìm trong khu vực này"', (tester) async {
      await _pump(tester, const RestaurantNearbyScreen());
      await _wait(tester);
      await tester.tap(find.byTooltip('Xem bản đồ'));
      await _wait(tester, 1000);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byTooltip('Xem danh sách'), findsOneWidget);
      expect(find.text('Bản đồ nền đang tắt'), findsOneWidget);
      expect(
          find.text(
              '3 quán chưa có vị trí trên bản đồ — xem ở chế độ danh sách.'),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == 'Vị trí của bạn'),
          findsOneWidget);
      final pins = tester.widgetList<RestaurantPin>(find.byType(RestaurantPin));
      expect(pins.length, greaterThanOrEqualTo(6));
      final sponsored = pins.where((p) => p.sponsored).map((p) => p.label);
      expect(sponsored, ['Bún Riêu Chay Hạnh Tâm']);
      expect(tester.widget<RestaurantPin>(_pin('Chay Thanh Tịnh')).certified,
          isFalse);
      expect(tester.widget<RestaurantPin>(_pin('Quán Chay An Lạc')).certified,
          isTrue);

      await tester.tap(_pin('Quán Chay An Lạc'));
      await tester.pump();
      expect(find.text('Xem quán'), findsOneWidget);
      expect(find.text('Chỉ đường'), findsOneWidget);
      expect(find.text('520 m'), findsOneWidget);
      await tester.tap(find.text('Chỉ đường'));
      await _wait(tester, 1000);
      expect(find.byType(RestaurantRouteScreen), findsOneWidget);
      expect(find.text('Quán Chay An Lạc'), findsOneWidget);
      await tester.pageBack();
      await _wait(tester, 800);

      // Pan → search this area → the list says so.
      expect(find.text('Tìm trong khu vực này'), findsNothing);
      await _pan(tester, find.byType(FlutterMap), const Offset(0, -150));
      await _wait(tester, 800);
      expect(find.text('Tìm trong khu vực này'), findsOneWidget);
      await tester.tap(find.text('Tìm trong khu vực này'));
      await _wait(tester);
      expect(find.text('Tìm trong khu vực này'), findsNothing);
      expect(find.widgetWithText(InputChip, 'Khu vực bản đồ'), findsOneWidget);

      await tester.tap(find.byTooltip('Xem danh sách'));
      await _wait(tester);
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.textContaining('trong khu vực bản đồ'), findsOneWidget);
      await tester.tap(find.byTooltip('Bỏ lọc khu vực'));
      await _wait(tester);
      expect(find.text('14 quán · gần nhất trước'), findsOneWidget);
    });

    testWidgets('tiles on: OSM attribution visible (offline fake tiles)',
        (tester) async {
      final tiles = _OfflineTiles();
      await _pump(
        tester,
        const RestaurantMapScreen(restaurant: _anLac),
        overrides: [
          mapTilesEnabledProvider.overrideWithValue(true),
          mapTileProviderProvider.overrideWithValue(tiles),
        ],
      );
      await _wait(tester, 1000);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.text('Bản đồ nền đang tắt'), findsNothing);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(tiles.requested, greaterThan(0));
      expect(tiles.headers['User-Agent'],
          'flutter_map (vn.veganlife.veganlife_mobile)');
      expect(find.text('Chỉ đường'), findsOneWidget);
      await _wait(tester, 6000); // the attribution popup folds after 5 s
    });
  });

  group('route screen', () {
    testWidgets('OSRM route: polyline, "2,6 km · ≈ 9 phút đi xe", credits',
        (tester) async {
      final fake = _FakeRouting((from, to) async => RouteResult(
            points: [from, const GeoPoint(10.779, 106.6995), to],
            distanceKm: 2.6043,
            durationSeconds: 540,
          ));
      await _pump(
        tester,
        const RestaurantRouteScreen(restaurant: _anLac),
        overrides: [routingServiceProvider.overrideWithValue(fake)],
      );
      await _wait(tester, 1000);
      expect(find.text('Chỉ đường'), findsOneWidget);
      expect(find.text('2,6 km · ≈ 9 phút đi xe'), findsOneWidget);
      expect(find.textContaining('Tuyến đường: OSRM'), findsOneWidget);
      expect(find.textContaining('Không tải được tuyến đường'), findsNothing);
      final line = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(line.polylines.single.points, hasLength(3));
      expect(find.text('Từ: Quận 1, TP.HCM (vị trí mô phỏng)'), findsOneWidget);
      expect(fake.calls.single, (_q1, _anLac.location!));
      // No Google Maps button on the page, only in the overflow.
      expect(find.text('Mở bằng Google Maps'), findsNothing);
    });

    testWidgets('a failure shows the straight line and the note',
        (tester) async {
      await _pump(
        tester,
        const RestaurantRouteScreen(restaurant: _anLac),
        overrides: [
          routingServiceProvider.overrideWithValue(
              _FakeRouting((_, __) async => throw Exception('offline'))),
        ],
      );
      await _wait(tester, 1000);
      expect(find.text('Không tải được tuyến đường — hiển thị đường thẳng'),
          findsOneWidget);
      expect(find.text('520 m (đường chim bay)'), findsOneWidget);
      final line = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(line.polylines.single.points, hasLength(2));
    });

    testWidgets('a server that never answers falls back within 6 s',
        (tester) async {
      await _pump(
        tester,
        const RestaurantRouteScreen(restaurant: _anLac),
        overrides: [
          routingServiceProvider.overrideWithValue(
              _FakeRouting((_, __) => Completer<RouteResult>().future)),
        ],
      );
      await _wait(tester, 1000);
      expect(find.text('Đang tìm đường…'), findsOneWidget);
      await _wait(tester, 5250);
      expect(find.text('Đang tìm đường…'), findsNothing);
      expect(find.text('Không tải được tuyến đường — hiển thị đường thẳng'),
          findsOneWidget);
    });

    testWidgets('"Đổi" picks another origin for this route only',
        (tester) async {
      final fake = _FakeRouting((from, to) async =>
          const StraightLineRoutingService().route(from, to));
      await _pump(
        tester,
        const RestaurantRouteScreen(restaurant: _anLac),
        overrides: [routingServiceProvider.overrideWithValue(fake)],
      );
      await _wait(tester, 1000);
      await tester.tap(find.text('Đổi'));
      await _wait(tester, 800);
      expect(find.text('Chọn điểm xuất phát'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'ben thanh');
      await _wait(tester, 1000);
      await tester.tap(find.text('Chợ Bến Thành'));
      await _wait(tester, 1000);
      expect(find.text('Từ: Chợ Bến Thành'), findsOneWidget);
      expect(fake.calls.last, (_benThanh, _anLac.location!));
      // The app-wide location did not change.
      final container = ProviderScope.containerOf(
          tester.element(find.byType(RestaurantRouteScreen)));
      expect(container.read(userLocationProvider).requireValue.point, _q1);
    });
  });
}
