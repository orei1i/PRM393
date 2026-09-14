import '../entities/shop_entities.dart';

abstract interface class ShopsRepository {
  List<VeganShop> get shops;
  LocationCoords get demoLocation;
}
