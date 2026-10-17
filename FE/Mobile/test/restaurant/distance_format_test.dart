// test/restaurant/distance_format_test.dart
//
// Device QA B5 (p14_04_list_hoan_kiem_no_sponsor): from Hồ Hoàn Kiếm the
// TP.HCM restaurants read "1141 km". Distances of 1.000 km and more use the
// Vietnamese thousands separator ("1.141 km"); short ones are unchanged.
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/widgets/restaurant_tile.dart';

/// "Hồ Hoàn Kiếm" of the mock geocoder.
const _hoanKiem = GeoPoint(21.0287, 105.8524);

void main() {
  test('thousands separator from 1.000 km; m and one decimal unchanged', () {
    expect(formatDistance(1141.2), '1.141 km');
    expect(formatDistance(1000), '1.000 km');
    expect(formatDistance(12345.6), '12.346 km');
    expect(formatDistance(999.4), '999 km');
    expect(formatDistance(12.6), '13 km');
    expect(formatDistance(9.96), '10 km', reason: 'not "10,0 km"');
    expect(formatDistance(1.234), '1,2 km');
    expect(formatDistance(0.367), '370 m');
    expect(formatDistance(0.01), 'Dưới 50 m');
    expect(formatDistance(null), 'Chưa có vị trí');
  });

  test('restaurants in TP.HCM seen from Hồ Hoàn Kiếm', () async {
    final rows = await MockRestaurantRepository(
      isSignedIn: () => true,
      currentUserId: () => 'u_me',
      currentUserName: () => 'Minh Anh',
    ).listRestaurants(near: _hoanKiem);
    final far = rows
        .map((r) => r.toEntity())
        .where((r) => (r.distanceKm ?? 0) >= 1000)
        .toList();
    expect(far, isNotEmpty);
    for (final r in far) {
      expect(formatDistance(r.distanceKm), matches(RegExp(r'^\d\.\d{3} km$')),
          reason: r.name);
    }
  });

  testWidgets('the list row shows "1.141 km"', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DistanceLabel(
          restaurant: Restaurant(
            id: 'r_far',
            name: 'Quán Chay An Lạc',
            address: 'Quận 1, TP.HCM',
            isVeganCertified: true,
            location: GeoPoint(10.7769, 106.7009),
            distanceKm: 1141.2,
          ),
        ),
      ),
    ));
    expect(find.text('1.141 km'), findsOneWidget);
    expect(find.text('1141 km'), findsNothing);
  });
}
