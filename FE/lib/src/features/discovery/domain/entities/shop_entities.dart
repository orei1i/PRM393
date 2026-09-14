class LocationCoords {
  const LocationCoords(this.latitude, this.longitude);
  final double latitude, longitude;
}

class VeganShop {
  const VeganShop({
    required this.id,
    required this.name,
    required this.address,
    required this.coords,
    required this.description,
    required this.rating,
    required this.kind,
  });
  final String id, name, address, description, kind;
  final LocationCoords coords;
  final double rating;
}

class ShopResult {
  const ShopResult(this.shop, this.distanceKm);
  final VeganShop shop;
  final double distanceKm;
  String get distanceLabel => '${distanceKm.toStringAsFixed(1)} km';
}
