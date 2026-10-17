// lib/features/restaurant/data/geocoding_service.dart
//
// Address search and reverse geocoding go through the BE (a server proxy):
// the Nominatim usage policy forbids client-side autocomplete, and the BE can
// swap providers (Nominatim, VietMap…) without an app release.
//
// GET /geo/search?q=ben%20thanh   (public)
// [ { "name": "Chợ Bến Thành", "address": "Lê Lợi, P. Bến Thành, Q.1, TP.HCM",
//     "city": "TP. Hồ Chí Minh", "latitude": 10.7725, "longitude": 106.698 } ]
// GET /geo/reverse?lat=10.7726&lng=106.6981   (public; 404 = nothing known)
// { "name": "Gần Chợ Bến Thành", "address": "Lê Lợi, P. Bến Thành, Q.1, TP.HCM",
//   "city": "TP. Hồ Chí Minh", "latitude": 10.7726, "longitude": 106.6981 }
// `city` uses the web's AD_CITIES spelling (campaign targeting).
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/json_helpers.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../domain/geo.dart';
import 'location_service.dart';

/// A place from address search or reverse geocoding.
class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.address,
    required this.point,
    this.city,
  });

  factory GeoPlace.fromJson(Map<String, dynamic> json) => GeoPlace(
        name: json['name'] as String? ?? json['label'] as String? ?? '',
        address: json['address'] as String? ?? '',
        city: json['city'] as String?,
        point: GeoPoint(
            readDouble(json['latitude']), readDouble(json['longitude'])),
      );

  final String name;
  final String address;
  final String? city;
  final GeoPoint point;

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'city': city,
        'latitude': point.latitude,
        'longitude': point.longitude,
      };

  UserLocation toUserLocation(UserLocationSource source) => UserLocation(
        point: point,
        label: name,
        source: source,
        address: address.isEmpty ? null : address,
        city: city,
      );
}

abstract interface class GeocodingService {
  /// Places matching [query] (best first); empty for a blank query.
  Future<List<GeoPlace>> search(String query);

  /// What is at [point]; `null` when nothing is known there.
  Future<GeoPlace?> reverse(GeoPoint point);
}

class RemoteGeocodingService implements GeocodingService {
  RemoteGeocodingService(this._dio);

  final Dio _dio;

  @override
  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return guardApi(() async {
      final res = await _dio.get<List<dynamic>>(ApiEndpoints.geoSearch,
          queryParameters: {'q': q});
      return (res.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(GeoPlace.fromJson)
          .toList();
    });
  }

  @override
  Future<GeoPlace?> reverse(GeoPoint point) async {
    try {
      return await guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
            ApiEndpoints.geoReverse,
            queryParameters: {'lat': point.latitude, 'lng': point.longitude});
        final data = res.data;
        return data == null ? null : GeoPlace.fromJson(data);
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}

/// Fixed places in TP.HCM, Hà Nội and Đà Nẵng (approximate coordinates), so
/// address search and map picking work offline. `#fail` in a query → 503.
class MockGeocodingService implements GeocodingService {
  const MockGeocodingService();

  static const _hcm = 'TP. Hồ Chí Minh';
  static const _hn = 'Hà Nội';
  static const _dn = 'Đà Nẵng';

  static const places = <GeoPlace>[
    GeoPlace(
        name: 'Nhà hát Thành phố',
        address: '7 Công trường Lam Sơn, P. Bến Nghé, Q.1, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7769, 106.7009)),
    GeoPlace(
        name: 'Chợ Bến Thành',
        address: 'Lê Lợi, P. Bến Thành, Q.1, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7725, 106.698)),
    GeoPlace(
        name: 'Nhà thờ Đức Bà',
        address: '01 Công xã Paris, P. Bến Nghé, Q.1, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7798, 106.699)),
    GeoPlace(
        name: 'Phố đi bộ Nguyễn Huệ',
        address: 'Nguyễn Huệ, P. Bến Nghé, Q.1, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7741, 106.7038)),
    GeoPlace(
        name: 'Hồ Con Rùa',
        address: 'Công trường Quốc tế, P. Võ Thị Sáu, Q.3, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7826, 106.6959)),
    GeoPlace(
        name: 'Chợ Bà Chiểu',
        address: 'Bạch Đằng, P.1, Q. Bình Thạnh, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.8016, 106.699)),
    GeoPlace(
        name: 'Landmark 81',
        address: '720A Điện Biên Phủ, P.22, Q. Bình Thạnh, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.795, 106.7218)),
    GeoPlace(
        name: 'Phú Mỹ Hưng',
        address: 'Nguyễn Văn Linh, P. Tân Phong, Q.7, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7295, 106.7213)),
    GeoPlace(
        name: 'Chợ Bình Tây',
        address: '57A Tháp Mười, P.2, Q.6, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.7499, 106.651)),
    GeoPlace(
        name: 'Đại học Bách khoa TP.HCM',
        address: '268 Lý Thường Kiệt, P.14, Q.10, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.773, 106.6595)),
    GeoPlace(
        name: 'Sân bay Tân Sơn Nhất',
        address: 'Trường Sơn, P.2, Q. Tân Bình, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.8188, 106.652)),
    GeoPlace(
        name: 'Khu Công nghệ cao',
        address: 'Xa lộ Hà Nội, P. Hiệp Phú, TP. Thủ Đức, TP.HCM',
        city: _hcm,
        point: GeoPoint(10.8411, 106.8099)),
    GeoPlace(
        name: 'Hồ Hoàn Kiếm',
        address: 'Đinh Tiên Hoàng, P. Hàng Trống, Q. Hoàn Kiếm, Hà Nội',
        city: _hn,
        point: GeoPoint(21.0287, 105.8524)),
    GeoPlace(
        name: 'Văn Miếu – Quốc Tử Giám',
        address: '58 Quốc Tử Giám, P. Văn Miếu, Q. Đống Đa, Hà Nội',
        city: _hn,
        point: GeoPoint(21.0293, 105.8355)),
    GeoPlace(
        name: 'Lăng Chủ tịch Hồ Chí Minh',
        address: '2 Hùng Vương, P. Điện Biên, Q. Ba Đình, Hà Nội',
        city: _hn,
        point: GeoPoint(21.0368, 105.8346)),
    GeoPlace(
        name: 'Hồ Tây',
        address: 'Thanh Niên, Q. Tây Hồ, Hà Nội',
        city: _hn,
        point: GeoPoint(21.058, 105.819)),
    GeoPlace(
        name: 'Times City',
        address: '458 Minh Khai, P. Vĩnh Tuy, Q. Hai Bà Trưng, Hà Nội',
        city: _hn,
        point: GeoPoint(20.9955, 105.868)),
    GeoPlace(
        name: 'Cầu Rồng',
        address: 'Nguyễn Văn Linh, Q. Hải Châu, Đà Nẵng',
        city: _dn,
        point: GeoPoint(16.0614, 108.227)),
    GeoPlace(
        name: 'Chợ Hàn',
        address: '119 Trần Phú, P. Hải Châu 1, Q. Hải Châu, Đà Nẵng',
        city: _dn,
        point: GeoPoint(16.068, 108.224)),
    GeoPlace(
        name: 'Bãi biển Mỹ Khê',
        address: 'Võ Nguyên Giáp, P. Phước Mỹ, Q. Sơn Trà, Đà Nẵng',
        city: _dn,
        point: GeoPoint(16.059, 108.247)),
    GeoPlace(
        name: 'Ngũ Hành Sơn',
        address: '81 Huyền Trân Công Chúa, Q. Ngũ Hành Sơn, Đà Nẵng',
        city: _dn,
        point: GeoPoint(16.003, 108.264)),
  ];

  /// Reverse geocoding names the nearest place within this distance…
  static const _nearKm = 1.5;

  /// …and keeps its city within this one.
  static const _cityKm = 30.0;

  @override
  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    await mockDelay(250);
    if (q.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Máy chủ đang bận, chưa tìm được địa chỉ. Thử lại sau.',
          statusCode: 503,
          code: 'unavailable');
    }
    final folded = foldVietnamese(q);
    final hits = places
        .where((p) => matchesQuery('${p.name} ${p.address} ${p.city}', q))
        .toList()
      // Name matches before address-only matches.
      ..sort((a, b) {
        final an = foldVietnamese(a.name).contains(folded) ? 0 : 1;
        final bn = foldVietnamese(b.name).contains(folded) ? 0 : 1;
        return an.compareTo(bn);
      });
    return hits.take(8).toList();
  }

  @override
  Future<GeoPlace?> reverse(GeoPoint point) async {
    await mockDelay(200);
    GeoPlace? nearest;
    var best = double.infinity;
    for (final p in places) {
      final d = haversineKm(point, p.point);
      if (d < best) {
        best = d;
        nearest = p;
      }
    }
    if (nearest == null || best > _cityKm) return null;
    if (best <= _nearKm) {
      return GeoPlace(
        name: best < 0.05 ? nearest.name : 'Gần ${nearest.name}',
        address: nearest.address,
        city: nearest.city,
        point: point,
      );
    }
    return GeoPlace(
      name: 'Vị trí đã chọn',
      address: '${formatCoordinates(point)} · ${nearest.city}',
      city: nearest.city,
      point: point,
    );
  }
}

final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  if (Env.useMockData) return const MockGeocodingService();
  return RemoteGeocodingService(ref.watch(dioProvider));
});
