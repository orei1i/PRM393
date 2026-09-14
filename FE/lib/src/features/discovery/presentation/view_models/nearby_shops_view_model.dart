import 'dart:math' as math;
import '../../../../core/state/view_model.dart';
import '../../domain/entities/shop_entities.dart';
import '../../domain/repositories/shops_repository.dart';

class NearbyShopsViewModel extends ViewModel {
  NearbyShopsViewModel(this._repository);
  final ShopsRepository _repository;
  String _query = '', _kind = 'All';
  bool _map = false;
  String? _selected;
  static const kinds = ['All', 'Restaurant', 'Café', 'Grocery'];
  bool get mapMode => _map;
  String get kind => _kind;
  String get query => _query;
  List<ShopResult> get results {
    final items = _repository.shops
        .where(
          (s) =>
              (_kind == 'All' || s.kind == _kind) &&
              '${s.name} ${s.address} ${s.description}'.toLowerCase().contains(
                _query.toLowerCase(),
              ),
        )
        .map((s) => ShopResult(s, distance(_repository.demoLocation, s.coords)))
        .toList();
    items.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return List.unmodifiable(items);
  }

  ShopResult? get selected {
    for (final item in results) {
      if (item.shop.id == _selected) return item;
    }
    return results.firstOrNull;
  }

  void setQuery(String value) {
    _query = value.trim();
    _selected = null;
    emit();
  }

  void setKind(String value) {
    _kind = value;
    _selected = null;
    emit();
  }

  void setMap(bool value) {
    _map = value;
    emit();
  }

  void selectShop(String id) {
    _selected = id;
    emit();
  }

  static double distance(LocationCoords a, LocationCoords b) {
    const radians = math.pi / 180;
    final dLat = (b.latitude - a.latitude) * radians;
    final dLon = (b.longitude - a.longitude) * radians;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.latitude * radians) *
            math.cos(b.latitude * radians) *
            math.pow(math.sin(dLon / 2), 2);
    return 6371 * 2 * math.asin(math.sqrt(h.clamp(0, 1)));
  }
}
