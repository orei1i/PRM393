// lib/features/restaurant/data/models/restaurant_model.dart
//
// GET /restaurants?lat=&lng=&q=&certifiedOnly=&sort=distance|rating&radiusKm=&limit=
// [ { "id": 21, "createdBy": 7, "createdByName": "Minh Anh", "name": "Quán Chay An Lạc",
//     "address": "12 Nguyễn Thị Minh Khai, Q.1, TP.HCM", "isVeganCertified": true,
//     "latitude": 10.7812, "longitude": 106.699, "distanceKm": 0.6,
//     "averageRating": 4.6, "reviewCount": 38 } ]
//
// `latitude`/`longitude` are proposed nullable columns. `distanceKm` (only
// when the request has lat/lng), `averageRating` (null without reviews),
// `reviewCount` and `createdByName` are computed by BE. `createdBy` may also
// arrive as the joined user `{ "id", "fullName" }` (web admin shape).
// `q` matches the name, the address, or a dish mentioned in the reviews.
// `radiusKm` (with lat/lng) keeps only places within that distance, so
// places without coordinates drop out.
//
// GET /restaurants/{id}/media   (restaurant_media, oldest first)
// [ { "id": "rm_1", "mediaType": "Image",
//     "mediaUrl": "https://res.cloudinary.com/veganlife/image/upload/v1/restaurants/an_lac_mat_tien.jpg",
//     "uploadedBy": { "id": 7, "fullName": "Minh Anh" } /* null = admin team */,
//     "createdAt": "…" } ]
//
// POST /restaurants
// { "name": "…", "address": "…", "latitude": 10.77, "longitude": 106.70,
//   "media": [ { "mediaType": "Image", "mediaUrl": "…" }, { "mediaType": "Video", "mediaUrl": "…" } ] }
// at most 5 images and 1 video, uploaded first with POST /media/images|videos.
//
// GET /restaurants/{id}/reviews
// [ { "id": 301, "userId": 7, "restaurantId": 21, "rating": 5, "comment": "Bún riêu chay đậm vị…",
//     "createdAt": "…", "updatedAt": null, "user": { "id": 7, "fullName": "Minh Anh" } } ]
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';

double? _readNullableDouble(Object? value) => value == null
    ? null
    : switch (value) {
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };

class RestaurantDto {
  const RestaurantDto({
    required this.id,
    required this.name,
    required this.address,
    this.isVeganCertified = false,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.averageRating,
    this.reviewCount = 0,
    this.createdById,
    this.createdByName,
  });

  factory RestaurantDto.fromJson(Map<String, dynamic> json) {
    final createdBy = json['createdBy'];
    final creator = createdBy is Map<String, dynamic> ? createdBy : null;
    return RestaurantDto(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      address: json['address'] as String? ?? '',
      isVeganCertified: json['isVeganCertified'] == true,
      latitude: _readNullableDouble(json['latitude']),
      longitude: _readNullableDouble(json['longitude']),
      distanceKm: _readNullableDouble(json['distanceKm']),
      averageRating: _readNullableDouble(json['averageRating']),
      reviewCount: readInt(json['reviewCount']),
      createdById:
          creator != null ? creator['id']?.toString() : createdBy?.toString(),
      createdByName: json['createdByName'] as String? ??
          creator?['fullName'] as String? ??
          creator?['name'] as String?,
    );
  }

  final String id;
  final String name;
  final String address;
  final bool isVeganCertified;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final double? averageRating;
  final int reviewCount;
  final String? createdById;
  final String? createdByName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdBy': createdById == null ? null : apiId(createdById!),
        'createdByName': createdByName,
        'name': name,
        'address': address,
        'isVeganCertified': isVeganCertified,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'averageRating': averageRating,
        'reviewCount': reviewCount,
      };

  Restaurant toEntity() => Restaurant(
        id: id,
        name: name,
        address: address,
        isVeganCertified: isVeganCertified,
        // A half-filled pair is as good as none.
        location: latitude != null && longitude != null
            ? GeoPoint(latitude!, longitude!)
            : null,
        distanceKm: distanceKm,
        averageRating: reviewCount == 0 ? null : averageRating,
        reviewCount: reviewCount,
        createdById: createdById,
        createdByName: createdByName,
      );
}

class ReviewDto {
  const ReviewDto({
    required this.id,
    required this.restaurantId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.updatedAt,
  });

  factory ReviewDto.fromJson(Map<String, dynamic> json) {
    final user = readMap(json['user']);
    return ReviewDto(
      id: json['id']?.toString() ?? '',
      restaurantId: json['restaurantId']?.toString() ?? '',
      userId: (json['userId'] ?? user['id'])?.toString() ?? '',
      userName: user['fullName'] as String? ??
          user['name'] as String? ??
          json['userName'] as String? ??
          'Thành viên',
      rating: readInt(json['rating']).clamp(1, 5),
      comment: json['comment'] as String? ?? json['content'] as String? ?? '',
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: readDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String restaurantId;
  final String userId;
  final String userName;
  final int rating;
  final String comment;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': apiId(userId),
        'restaurantId': apiId(restaurantId),
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'user': {'id': apiId(userId), 'fullName': userName},
      };

  RestaurantReview toEntity() => RestaurantReview(
        id: id,
        restaurantId: restaurantId,
        userId: userId,
        userName: userName,
        rating: rating,
        comment: comment,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class RestaurantMediaDto {
  const RestaurantMediaDto({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    this.uploadedById,
    this.uploadedByName,
    this.createdAt,
  });

  factory RestaurantMediaDto.fromJson(Map<String, dynamic> json) {
    final by = json['uploadedBy'];
    final person = by is Map<String, dynamic> ? by : null;
    return RestaurantMediaDto(
      id: json['id']?.toString() ?? '',
      mediaType: RestaurantMediaType.fromApi(json['mediaType']),
      mediaUrl: json['mediaUrl'] as String? ?? '',
      uploadedById: person?['id']?.toString() ?? by?.toString(),
      uploadedByName:
          person?['fullName'] as String? ?? person?['name'] as String?,
      createdAt: readDateTime(json['createdAt']),
    );
  }

  final String id;
  final RestaurantMediaType mediaType;
  final String mediaUrl;
  final String? uploadedById;
  final String? uploadedByName;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mediaType': mediaType.apiValue,
        'mediaUrl': mediaUrl,
        'uploadedBy': uploadedById == null
            ? null
            : {'id': apiId(uploadedById!), 'fullName': uploadedByName},
        'createdAt': createdAt?.toUtc().toIso8601String(),
      };

  RestaurantMedia toEntity() => RestaurantMedia(
        id: id,
        type: mediaType,
        url: mediaUrl,
        uploadedByName: uploadedByName,
        createdAt: createdAt,
      );
}

/// One uploaded file attached to a suggestion (`media[]` of POST
/// /restaurants).
class NewRestaurantMediaDto {
  const NewRestaurantMediaDto(
      {required this.mediaType, required this.mediaUrl});

  final RestaurantMediaType mediaType;
  final String mediaUrl;

  Map<String, dynamic> toJson() =>
      {'mediaType': mediaType.apiValue, 'mediaUrl': mediaUrl};
}

/// POST /restaurants. The server sets `createdBy` = me and
/// `isVeganCertified` = false; the coordinates and media are optional.
class CreateRestaurantRequestDto {
  const CreateRestaurantRequestDto({
    required this.name,
    required this.address,
    this.latitude,
    this.longitude,
    this.media = const [],
  });

  /// At most this many photos and videos per suggestion.
  static const maxImages = 5;
  static const maxVideos = 1;

  final String name;
  final String address;
  final double? latitude;
  final double? longitude;
  final List<NewRestaurantMediaDto> media;

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        if (latitude != null && longitude != null) ...{
          'latitude': latitude,
          'longitude': longitude,
        },
        if (media.isNotEmpty) 'media': [for (final m in media) m.toJson()],
      };
}
