// lib/features/restaurant/domain/entities/restaurant.dart
import '../geo.dart';

/// `sort` query value of `GET /restaurants`.
enum RestaurantSort {
  distance('distance', 'Gần nhất'),
  rating('rating', 'Đánh giá cao');

  const RestaurantSort(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// A vegan restaurant (`restaurants` + the proposed `latitude`/`longitude`
/// columns + fields the server computes from `reviews` and the caller's
/// position).
class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.isVeganCertified,
    this.location,
    this.distanceKm,
    this.averageRating,
    this.reviewCount = 0,
    this.createdById,
    this.createdByName,
  });

  final String id;
  final String name;
  final String address;

  /// Verified by the admin team on the web console.
  final bool isVeganCertified;

  /// Null for most member submissions: shown as "Chưa có vị trí".
  final GeoPoint? location;

  /// From the caller's position; null without coordinates on either side.
  final double? distanceKm;

  /// Null until the first review.
  final double? averageRating;
  final int reviewCount;

  /// `restaurants.created_by`: set when a member suggested the place.
  final String? createdById;
  final String? createdByName;

  bool get hasLocation => location != null;
}

/// One member's review (`reviews`, one per user and restaurant).
class RestaurantReview {
  const RestaurantReview({
    required this.id,
    required this.restaurantId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String restaurantId;
  final String userId;
  final String userName;

  /// 1…5.
  final int rating;
  final String comment;
  final DateTime createdAt;

  /// Set once the author re-submits ("(đã sửa)").
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null;
}
