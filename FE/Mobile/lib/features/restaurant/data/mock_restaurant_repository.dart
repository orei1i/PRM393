// lib/features/restaurant/data/mock_restaurant_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../domain/entities/restaurant.dart';
import '../domain/food_match.dart';
import '../domain/geo.dart';
import 'mock/restaurant_mock_data.dart';
import 'models/restaurant_model.dart';
import 'restaurant_api_service.dart';

/// In-memory restaurants and reviews. State is static so new reviews and
/// suggested places survive provider rebuilds (sign-in/out, account switches)
/// for the whole app session; [reset] restores the seeds for tests.
///
/// `#fail` in a review comment, a suggested name/address or a list query →
/// 503; any write on "Quán thử nghiệm QA #fail" → 503 too. Suggestions keep
/// their coordinates and media (at most 5 photos and 1 video → else 400).
class MockRestaurantRepository implements RestaurantApiService {
  MockRestaurantRepository({
    required this.isSignedIn,
    required this.currentUserId,
    required this.currentUserName,
  });

  final bool Function() isSignedIn;
  final String Function() currentUserId;
  final String Function() currentUserName;

  static final _db = _MockRestaurantDb();

  /// Back to the seeds (tests).
  static void reset() => _db.reset();

  static bool _fails(String text) => text.toLowerCase().contains('#fail');

  static ApiException _unavailable(String what) => ApiException(
      message: 'Máy chủ đang bận, chưa $what. Thử lại sau.',
      statusCode: 503,
      code: 'unavailable');

  static ApiException _invalid(String message) =>
      ApiException(message: message, statusCode: 400, code: 'validation');

  void _requireMember(String action) {
    if (!isSignedIn()) {
      throw ApiException(
          message: 'Vui lòng đăng nhập để $action.', statusCode: 401);
    }
  }

  _RestaurantRow _find(String id) {
    for (final r in _db.restaurants) {
      if (r.id == id) return r;
    }
    throw const ApiException(
        message: 'Quán không còn tồn tại.', statusCode: 404, code: 'not_found');
  }

  Iterable<_ReviewRow> _reviewsOf(String restaurantId) =>
      _db.reviews.where((v) => v.restaurantId == restaurantId);

  /// The texts a dish search looks at: the name and every review comment.
  Map<String, List<String>> _dishTexts(Iterable<_RestaurantRow> rows) => {
        for (final r in rows)
          r.id: [r.name, for (final v in _reviewsOf(r.id)) v.comment],
      };

  RestaurantDto _dto(_RestaurantRow r, GeoPoint? near) {
    final reviews = _reviewsOf(r.id).toList();
    final point =
        r.lat != null && r.lng != null ? GeoPoint(r.lat!, r.lng!) : null;
    // Round-trip through the wire format so the parser is exercised too.
    return RestaurantDto.fromJson({
      'id': r.id,
      'createdBy': r.createdById == null
          ? null
          : {'id': r.createdById, 'fullName': r.createdByName},
      'name': r.name,
      'address': r.address,
      'isVeganCertified': r.certified,
      'latitude': r.lat,
      'longitude': r.lng,
      'distanceKm':
          near == null || point == null ? null : haversineKm(near, point),
      'averageRating': reviews.isEmpty
          ? null
          : reviews.fold<int>(0, (s, v) => s + v.rating) / reviews.length,
      'reviewCount': reviews.length,
    });
  }

  ReviewDto _reviewDto(_ReviewRow v) => ReviewDto.fromJson({
        'id': v.id,
        'userId': v.userId,
        'restaurantId': v.restaurantId,
        'rating': v.rating,
        'comment': v.comment,
        'createdAt': v.createdAt.toUtc().toIso8601String(),
        'updatedAt': v.updatedAt?.toUtc().toIso8601String(),
        'user': {'id': v.userId, 'fullName': v.userName},
      });

  static int _byName(RestaurantDto a, RestaurantDto b) =>
      foldVietnamese(a.name).compareTo(foldVietnamese(b.name));

  /// Nearest first; no coordinates last.
  static int _byDistance(RestaurantDto a, RestaurantDto b) {
    final da = a.distanceKm, db = b.distanceKm;
    if (da != null && db != null && da != db) return da.compareTo(db);
    if ((da == null) != (db == null)) return da == null ? 1 : -1;
    return _byName(a, b);
  }

  /// Best average first, more reviews breaking ties; unrated last.
  static int _byRating(RestaurantDto a, RestaurantDto b) {
    final ra = a.reviewCount == 0 ? null : a.averageRating;
    final rb = b.reviewCount == 0 ? null : b.averageRating;
    if ((ra == null) != (rb == null)) return ra == null ? 1 : -1;
    if (ra != null && rb != null && ra != rb) return rb.compareTo(ra);
    if (a.reviewCount != b.reviewCount) {
      return b.reviewCount.compareTo(a.reviewCount);
    }
    return _byDistance(a, b);
  }

  @override
  Future<List<RestaurantDto>> listRestaurants({
    GeoPoint? near,
    String? query,
    bool certifiedOnly = false,
    RestaurantSort sort = RestaurantSort.distance,
    double? radiusKm,
    int? limit,
  }) async {
    await mockDelay(500);
    final q = query?.trim() ?? '';
    if (_fails(q)) throw _unavailable('tải được danh sách quán');
    var rows = _db.restaurants.where((r) => !certifiedOnly || r.certified);
    if (q.isNotEmpty) {
      final byDish = matchFood(_dishTexts(rows), q);
      rows = rows.where((r) =>
          byDish.contains(r.id) || matchesQuery('${r.name} ${r.address}', q));
    }
    var list = rows.map((r) => _dto(r, near)).toList();
    if (radiusKm != null && near != null) {
      list = list
          .where((r) => r.distanceKm != null && r.distanceKm! <= radiusKm)
          .toList();
    }
    list.sort(sort == RestaurantSort.rating ? _byRating : _byDistance);
    return limit == null ? list : list.take(limit).toList();
  }

  @override
  Future<List<RestaurantMediaDto>> getMedia(String restaurantId) async {
    await mockDelay(300);
    _find(restaurantId);
    return [
      for (final m in _db.media)
        if (m.restaurantId == restaurantId) _mediaDto(m),
    ];
  }

  RestaurantMediaDto _mediaDto(_MediaRow m) => RestaurantMediaDto.fromJson({
        'id': m.id,
        'mediaType': m.type.apiValue,
        'mediaUrl': m.url,
        'uploadedBy': m.uploadedBy == null
            ? null
            : {
                'id': m.uploadedBy,
                'fullName': m.uploadedByName ??
                    mockRestaurantPeople[m.uploadedBy] ??
                    'Thành viên',
              },
        'createdAt': m.createdAt.toUtc().toIso8601String(),
      });

  @override
  Future<RestaurantDto> getRestaurant(String id, {GeoPoint? near}) async {
    await mockDelay(400);
    return _dto(_find(id), near);
  }

  @override
  Future<List<ReviewDto>> getReviews(String restaurantId) async {
    await mockDelay(350);
    _find(restaurantId);
    return (_reviewsOf(restaurantId).toList()
          ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity)))
        .map(_reviewDto)
        .toList();
  }

  @override
  Future<ReviewDto> upsertReview(String restaurantId,
      {required int rating, required String comment}) async {
    await mockDelay(600);
    _requireMember('viết đánh giá');
    final restaurant = _find(restaurantId);
    final text = comment.trim();
    if (rating < 1 || rating > 5) throw _invalid('Chọn số sao từ 1 đến 5.');
    if (text.length < 10 || text.length > 500) {
      throw _invalid('Nhận xét cần từ 10 đến 500 ký tự.');
    }
    if (_fails(text) || _fails(restaurant.name)) {
      throw _unavailable('lưu được đánh giá');
    }
    final me = currentUserId();
    final now = DateTime.now();
    for (final v in _db.reviews) {
      if (v.restaurantId == restaurantId && v.userId == me) {
        v
          ..rating = rating
          ..comment = text
          ..userName = currentUserName()
          ..updatedAt = now;
        return _reviewDto(v);
      }
    }
    final review = _ReviewRow(
      id: 'rv_u_${now.millisecondsSinceEpoch}_${_db.seq++}',
      restaurantId: restaurantId,
      userId: me,
      userName: currentUserName(),
      rating: rating,
      comment: text,
      createdAt: now,
    );
    _db.reviews.add(review);
    return _reviewDto(review);
  }

  @override
  Future<RestaurantDto> createRestaurant(
      CreateRestaurantRequestDto request) async {
    await mockDelay(700);
    _requireMember('gợi ý quán mới');
    final name = request.name.trim();
    final address = request.address.trim();
    if (name.length < 3) throw _invalid('Tên quán cần ít nhất 3 ký tự.');
    if (address.length < 10) {
      throw _invalid('Địa chỉ cần ít nhất 10 ký tự.');
    }
    final images = request.media
        .where((m) => m.mediaType == RestaurantMediaType.image)
        .length;
    final videos = request.media.length - images;
    if (images > CreateRestaurantRequestDto.maxImages ||
        videos > CreateRestaurantRequestDto.maxVideos) {
      throw _invalid('Tối đa 5 ảnh và 1 video cho mỗi gợi ý.');
    }
    if (request.media.any((m) => m.mediaUrl.trim().isEmpty)) {
      throw _invalid('Ảnh hoặc video chưa tải lên xong.');
    }
    if ((request.latitude == null) != (request.longitude == null)) {
      throw _invalid('Toạ độ cần đủ vĩ độ và kinh độ.');
    }
    if (_fails(name) || _fails(address)) {
      throw _unavailable('gửi được gợi ý quán');
    }
    final duplicate = _db.restaurants.any((r) =>
        foldVietnamese(r.name) == foldVietnamese(name) &&
        foldVietnamese(r.address) == foldVietnamese(address));
    if (duplicate) {
      throw const ApiException(
          message: 'Quán này đã có trên VeganLife.',
          statusCode: 409,
          code: 'duplicate');
    }
    final row = _RestaurantRow(
      id: 'rs_u_${DateTime.now().millisecondsSinceEpoch}_${_db.seq++}',
      name: name,
      address: address,
      certified: false,
      createdById: currentUserId(),
      createdByName: currentUserName(),
      lat: request.latitude,
      lng: request.longitude,
    );
    _db.restaurants.add(row);
    final now = DateTime.now();
    for (final m in request.media) {
      _db.media.add(_MediaRow(
        id: 'rm_u_${now.millisecondsSinceEpoch}_${_db.seq++}',
        restaurantId: row.id,
        type: m.mediaType,
        url: m.mediaUrl,
        uploadedBy: currentUserId(),
        uploadedByName: currentUserName(),
        createdAt: now,
      ));
    }
    return _dto(row, null);
  }

  @override
  Future<List<RestaurantDto>> suggestedForFood(String food,
      {GeoPoint? near, int limit = 3}) async {
    await mockDelay(450);
    if (_fails(food)) throw _unavailable('tải được quán gợi ý');
    final texts = _dishTexts(_db.restaurants);
    final hits = matchFood(texts, food);
    final scores = foodMatchScores(texts, food);
    final list = _db.restaurants
        .where((r) => hits.contains(r.id))
        .map((r) => _dto(r, near))
        .toList()
      // More of the dish name mentioned first, then nearest, then best rated.
      ..sort((a, b) {
        final sa = scores[a.id] ?? 0, sb = scores[b.id] ?? 0;
        if (sa != sb) return sb.compareTo(sa);
        final da = a.distanceKm, db = b.distanceKm;
        if (da != null && db != null && da != db) return da.compareTo(db);
        if ((da == null) != (db == null)) return da == null ? 1 : -1;
        return _byRating(a, b);
      });
    return list.take(limit).toList();
  }
}

class _RestaurantRow {
  _RestaurantRow({
    required this.id,
    required this.name,
    required this.address,
    required this.certified,
    this.createdById,
    this.createdByName,
    this.lat,
    this.lng,
  });

  final String id;
  final String name;
  final String address;
  final bool certified;
  final String? createdById;
  final String? createdByName;
  final double? lat;
  final double? lng;
}

class _MediaRow {
  _MediaRow({
    required this.id,
    required this.restaurantId,
    required this.type,
    required this.url,
    required this.createdAt,
    this.uploadedBy,
    this.uploadedByName,
  });

  final String id;
  final String restaurantId;
  final RestaurantMediaType type;
  final String url;
  final String? uploadedBy;
  final String? uploadedByName;
  final DateTime createdAt;
}

class _ReviewRow {
  _ReviewRow({
    required this.id,
    required this.restaurantId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String userId;
  String userName;
  int rating;
  String comment;
  final DateTime createdAt;
  DateTime? updatedAt;

  DateTime get lastActivity => updatedAt ?? createdAt;
}

class _MockRestaurantDb {
  _MockRestaurantDb() {
    reset();
  }

  final restaurants = <_RestaurantRow>[];
  final reviews = <_ReviewRow>[];
  final media = <_MediaRow>[];
  int seq = 0;

  void reset() {
    final now = DateTime.now();
    restaurants
      ..clear()
      ..addAll(mockRestaurantSeeds.map((s) => _RestaurantRow(
            id: s.id,
            name: s.name,
            address: s.address,
            certified: s.certified,
            createdById: s.createdBy,
            createdByName: mockRestaurantPeople[s.createdBy],
            lat: s.lat,
            lng: s.lng,
          )));
    media
      ..clear()
      ..addAll([
        for (final (i, (restaurantId, type, file, by, daysAgo))
            in mockRestaurantMediaSeeds.indexed)
          _MediaRow(
            id: 'rm_${i + 1}',
            restaurantId: restaurantId,
            type: RestaurantMediaType.fromApi(type),
            url: '$mockMediaBase/${type == 'Video' ? 'video' : 'image'}'
                '/upload/v1/restaurants/$file',
            uploadedBy: by,
            createdAt: now.subtract(Duration(days: daysAgo)),
          ),
      ]);
    reviews.clear();
    for (final MapEntry(key: restaurantId, value: seeds)
        in mockReviewSeeds.entries) {
      for (final (i, (userId, rating, comment, daysAgo)) in seeds.indexed) {
        reviews.add(_ReviewRow(
          id: 'rv_${restaurantId.replaceFirst('rs_', '')}_${i + 1}',
          restaurantId: restaurantId,
          userId: userId,
          userName: mockRestaurantPeople[userId] ?? 'Thành viên',
          rating: rating,
          comment: comment,
          createdAt: now.subtract(
              Duration(minutes: (daysAgo * Duration.minutesPerDay).round())),
        ));
      }
    }
  }
}
