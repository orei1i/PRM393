import '../../domain/entities/shop_entities.dart';
import '../../domain/repositories/shops_repository.dart';

class MockShopsRepository implements ShopsRepository {
  @override
  LocationCoords get demoLocation => const LocationCoords(10.7769, 106.7009);
  @override
  List<VeganShop> get shops => const [
    VeganShop(
      id: 's1',
      name: 'Little Sprout Kitchen',
      address: 'District 1, Ho Chi Minh City',
      coords: LocationCoords(10.7789, 106.6984),
      description: 'Seasonal bowls, slow mornings, and thoughtful ingredients.',
      rating: 4.8,
      kind: 'Restaurant',
    ),
    VeganShop(
      id: 's2',
      name: 'The Kind Pantry',
      address: 'District 3, Ho Chi Minh City',
      coords: LocationCoords(10.784, 106.685),
      description: 'Plant-based staples, nut butters, and fresh local produce.',
      rating: 4.7,
      kind: 'Grocery',
    ),
    VeganShop(
      id: 's3',
      name: 'Moss & Mylk',
      address: 'Binh Thanh, Ho Chi Minh City',
      coords: LocationCoords(10.798, 106.710),
      description: 'Oat lattes and small-batch vegan pastries.',
      rating: 4.9,
      kind: 'Café',
    ),
    VeganShop(
      id: 's4',
      name: 'Green Table',
      address: 'Thao Dien, Ho Chi Minh City',
      coords: LocationCoords(10.805, 106.733),
      description: 'Comforting plant-based meals in a leafy courtyard.',
      rating: 4.6,
      kind: 'Restaurant',
    ),
  ];
}
