// lib/features/ads/data/mock_ads_repository.dart
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../restaurant/domain/geo.dart';
import 'ads_api_service.dart';
import 'models/ad_feed_item.dart';

/// Mock-only switch for the sponsored cards:
/// `flutter run --dart-define=MOCK_ADS_SCENARIO=empty` (or `error`). Either
/// way the feed simply shows no ads.
const _scenarioFromEnv =
    String.fromEnvironment('MOCK_ADS_SCENARIO', defaultValue: 'normal');

/// The web admin's seeded campaigns (FE/Web `src/lib/mock_ads.ts`, same ids,
/// restaurants, copy, dates and status rule), so "Được tài trợ" shows the
/// campaigns the console lists as Running: Bún Riêu Chay Hạnh Tâm and Lẩu
/// Nấm Chay Mộc Nhiên. Ratings come from the web's review seeds
/// (`mock_restaurants.ts`). Datasets are not synced at runtime (D13).
class MockAdsRepository implements AdsApiService {
  MockAdsRepository(
      {this.scenario = _scenarioFromEnv, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final String scenario;
  final DateTime Function() _clock;

  /// Campaign dates are offsets from the first use in this app session,
  /// like the web's module-load `NOW`; [_clock] then moves "now" (tests).
  static final DateTime _seededAt = DateTime.now();

  /// Mock spend: 40đ per impression (40.000đ CPM), as on the web.
  static const _costPerImpression = 40;

  static const _restaurants = <String, Map<String, Object?>>{
    'rs_hanh_tam': {
      'id': 'rs_hanh_tam',
      'name': 'Bún Riêu Chay Hạnh Tâm',
      'address': '152 Đinh Tiên Hoàng, P.1, Q. Bình Thạnh, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.8003,
      'longitude': 106.6977,
      'averageRating': 4.75,
      'reviewCount': 4,
    },
    'rs_moc_nhien': {
      'id': 'rs_moc_nhien',
      'name': 'Lẩu Nấm Chay Mộc Nhiên',
      'address': '88 Nguyễn Trãi, P.3, Q.5, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.7578,
      'longitude': 106.6815,
      'averageRating': 4.6,
      'reviewCount': 5,
    },
    'rs_lanh': {
      'id': 'rs_lanh',
      'name': 'Sữa Hạt & Chay Lành',
      'address': '24 Nguyễn Gia Trí, P.25, Q. Bình Thạnh, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.8036,
      'longitude': 106.7155,
      'averageRating': 4.33,
      'reviewCount': 3,
    },
    'rs_van_hoa': {
      'id': 'rs_van_hoa',
      'name': 'Nhà Hàng Chay Vạn Hoa',
      'address': '61 Nguyễn Thị Thập, P. Tân Hưng, Q.7, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.738,
      'longitude': 106.716,
      'averageRating': 4.0,
      'reviewCount': 4,
    },
    'rs_bo_de': {
      'id': 'rs_bo_de',
      'name': 'Phở Chay Bồ Đề Xanh',
      'address': '17 Hải Thượng Lãn Ông, P.10, Q.5, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.7505,
      'longitude': 106.66,
      'averageRating': 4.33,
      'reviewCount': 3,
    },
    'rs_tam_nhu': {
      'id': 'rs_tam_nhu',
      'name': 'Cơm Chay Tâm Như',
      'address': '210 Lê Văn Sỹ, P.14, Q.3, TP.HCM',
      'isVeganCertified': true,
      'latitude': 10.7905,
      'longitude': 106.6788,
      'averageRating': 4.0,
      'reviewCount': 4,
    },
  };

  static const _hcm = 'TP. Hồ Chí Minh';

  /// id, restaurant, headline, message, CTA, city, start/end day offsets,
  /// paused, budget, impressions — as on the web.
  static const _seeds = <(
    String,
    String,
    String,
    String,
    AdCtaType,
    String?,
    int,
    int,
    bool,
    int,
    int
  )>[
    (
      'ad_hanh_tam',
      'rs_hanh_tam',
      'Bún riêu chay 35k — riêu đậu hũ mềm',
      'Tô đầy đặn, nước dùng ngọt từ rau củ, mắm tôm chay để riêng. Mở cửa 6:00–21:00.',
      AdCtaType.viewStore,
      _hcm,
      -10,
      20,
      false,
      3000000,
      48210,
    ),
    (
      'ad_moc_nhien',
      'rs_moc_nhien',
      'Lẩu nấm 7 loại cho nhóm bạn',
      'Giảm 15% cho bàn từ 4 người tối thứ 2–5. Có phòng riêng cho gia đình.',
      AdCtaType.book,
      _hcm,
      -5,
      25,
      false,
      5000000,
      31540,
    ),
    (
      'ad_lanh',
      'rs_lanh',
      'Sữa hạt óc chó ít ngọt, làm mỗi sáng',
      'Có chai 1 lít mang về và bánh mì chay pate nấm. Ghé quán gần cầu Thị Nghè.',
      AdCtaType.directions,
      _hcm,
      -12,
      18,
      true,
      2000000,
      12880,
    ),
    (
      'ad_van_hoa',
      'rs_van_hoa',
      'Đặt tiệc chay giỗ chạp, 8–12 món',
      'Thực đơn tiệc chay đa dạng, có chỗ đậu ô tô. Đặt trước 3 ngày để chọn món.',
      AdCtaType.book,
      _hcm,
      3,
      33,
      false,
      4000000,
      0,
    ),
    (
      'ad_bo_de',
      'rs_bo_de',
      'Phở chay đúng vị Bắc từ 6 giờ sáng',
      'Nước dùng ninh từ củ cải, bắp và nấm hương. Có bánh cuốn chay nhân nấm mèo.',
      AdCtaType.viewStore,
      _hcm,
      -40,
      -10,
      false,
      2500000,
      61200,
    ),
    (
      'ad_qa_fail',
      'rs_tam_nhu',
      'Chiến dịch thử nghiệm QA #fail',
      'Mọi thao tác trên chiến dịch này trả lỗi 503 để kiểm tra hoàn tác.',
      AdCtaType.viewStore,
      null,
      -2,
      12,
      true,
      1000000,
      0,
    ),
  ];

  /// The web's status rule: Ended after end_at or once spent ≥ budget;
  /// otherwise Paused when paused; Scheduled before start_at; else Running.
  static bool isRunning({
    required DateTime startAt,
    required DateTime endAt,
    required bool paused,
    required int budget,
    required int spent,
    required DateTime now,
  }) {
    if (endAt.isBefore(now) || spent >= budget) return false;
    if (paused) return false;
    return !startAt.isAfter(now);
  }

  @override
  Future<List<AdFeedItemDto>> getFeed({
    String? city,
    double? lat,
    double? lng,
    int limit = 3,
  }) async {
    await mockDelay(300);
    if (scenario == 'error') {
      throw const ApiException(
          message: 'Chưa tải được quảng cáo.', statusCode: 503);
    }
    if (scenario == 'empty') return const [];
    final now = _clock();
    final seed = _seededAt;
    DateTime dayStart(int offset) =>
        DateTime(seed.year, seed.month, seed.day + offset);
    DateTime dayEnd(int offset) =>
        dayStart(offset + 1).subtract(const Duration(milliseconds: 1));
    final wanted = city == null ? null : foldVietnamese(city.trim());

    final items = <AdFeedItemDto>[];
    for (final (
          id,
          restaurantId,
          headline,
          message,
          cta,
          target,
          start,
          end,
          paused,
          budget,
          impressions
        ) in _seeds) {
      final startAt = dayStart(start);
      final endAt = dayEnd(end);
      final spent = impressions * _costPerImpression;
      if (!isRunning(
          startAt: startAt,
          endAt: endAt,
          paused: paused,
          budget: budget,
          spent: spent > budget ? budget : spent,
          now: now)) {
        continue;
      }
      if (target != null &&
          wanted != null &&
          foldVietnamese(target) != wanted) {
        continue;
      }
      final r = _restaurants[restaurantId]!;
      final rLat = r['latitude'] as double?;
      final rLng = r['longitude'] as double?;
      final distance =
          lat != null && lng != null && rLat != null && rLng != null
              ? (haversineKm(GeoPoint(lat, lng), GeoPoint(rLat, rLng)) * 10)
                      .round() /
                  10
              : null;
      items.add(AdFeedItemDto.fromJson({
        'id': id,
        'restaurantId': restaurantId,
        'restaurant': r,
        'headline': headline,
        'message': message,
        'ctaType': cta.apiValue,
        'ctaLabel': cta.label,
        'targetCity': target,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        'distanceKm': distance,
      }));
    }
    items.sort((a, b) {
      final byDistance = (a.distanceKm ?? double.infinity)
          .compareTo(b.distanceKm ?? double.infinity);
      if (byDistance != 0) return byDistance;
      return (b.startAt ?? now).compareTo(a.startAt ?? now);
    });
    return items.take(limit < 1 ? 1 : limit).toList();
  }
}
