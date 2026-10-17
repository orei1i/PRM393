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

/// "Bán kính" choices of the filter sheet; `null` = "Không giới hạn".
const restaurantRadiusChoicesKm = <double?>[1, 3, 5, 10, null];

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

  /// Same restaurant with [distanceKm] measured from somewhere else (the
  /// map's "Tìm trong khu vực này" still shows distances from the user).
  Restaurant withDistance(double? km) => Restaurant(
        id: id,
        name: name,
        address: address,
        isVeganCertified: isVeganCertified,
        location: location,
        distanceKm: km,
        averageRating: averageRating,
        reviewCount: reviewCount,
        createdById: createdById,
        createdByName: createdByName,
      );
}

/// `restaurant_media.media_type`.
enum RestaurantMediaType {
  image('Image'),
  video('Video');

  const RestaurantMediaType(this.apiValue);
  final String apiValue;

  static RestaurantMediaType fromApi(Object? value) =>
      value?.toString().toLowerCase() == 'video' ? video : image;
}

/// A photo or the intro video of a restaurant (`restaurant_media`), shown in
/// the "Ảnh & video" strip. Members add them with "Gợi ý quán mới".
class RestaurantMedia {
  const RestaurantMedia({
    required this.id,
    required this.type,
    required this.url,
    this.uploadedByName,
    this.createdAt,
  });

  final String id;
  final RestaurantMediaType type;
  final String url;

  /// Null = the admin team.
  final String? uploadedByName;
  final DateTime? createdAt;

  bool get isVideo => type == RestaurantMediaType.video;
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
