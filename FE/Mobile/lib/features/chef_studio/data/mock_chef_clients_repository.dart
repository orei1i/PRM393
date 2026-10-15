// lib/features/chef_studio/data/mock_chef_clients_repository.dart
import '../../../core/session/user_role.dart';
import '../../../core/utils/mock_delay.dart';
import '../../commerce/data/mock/mock_commerce_db.dart';
import '../../commerce/data/models/order_model.dart';
import '../../commerce/domain/commerce_status.dart';
import '../../meal_planner/data/mock/meal_planner_mock_data.dart';
import '../../meal_planner/data/mock/mock_recipe_book.dart';
import '../domain/chef_client_rules.dart';
import 'chef_clients_api_service.dart';
import 'models/chef_client_models.dart';

/// Clients computed like the BE would: every Paid or Refunded order for the
/// chef's services in the shared [MockCommerceDb], grouped by buyer, plus
/// the newest suggestion from [MockRecipeBook]. So a package Minh Anh buys
/// shows up here for Tâm after switching accounts. The empty / error
/// scenarios follow `MOCK_COMMERCE_SCENARIO`.
class MockChefClientsRepository implements ChefClientsApiService {
  MockChefClientsRepository({
    required this.currentUserId,
    required this.currentRole,
  });

  final String? Function() currentUserId;
  final UserRole Function() currentRole;

  MockCommerceDb get _db => MockCommerceDb.instance;

  /// What each seeded buyer shares with a chef through a package.
  static final Map<String, Map<String, Object?>> _healthSeeds = {
    'u_lan_phuong': {
      'goal': 'lose_weight',
      'heightCm': 158,
      'weightKg': 60,
      'bmi': 24.0,
      'allergies': ['peanut'],
      'dietaryRestrictions': ['low_sodium'],
    },
    'u_bao_tram': {
      'goal': 'maintain',
      'heightCm': 162,
      'weightKg': 52,
      'bmi': 19.8,
      'allergies': <String>[],
      'dietaryRestrictions': <String>[],
    },
    'u_gia_han': {
      'goal': 'lean_muscle',
      'heightCm': 165,
      'weightKg': 55,
      'bmi': 20.2,
      'allergies': ['soy'],
      'dietaryRestrictions': <String>[],
    },
    'u_duc_huy': {
      'goal': 'lean_muscle',
      'heightCm': 175,
      'weightKg': 70,
      'bmi': 22.9,
      'allergies': ['gluten'],
      'dietaryRestrictions': <String>[],
    },
    'u_quoc_viet': {
      'goal': 'lose_weight',
      'heightCm': 170,
      'weightKg': 78,
      'bmi': 27.0,
      'allergies': <String>[],
      'dietaryRestrictions': ['low_sodium'],
    },
    'u_hoang_nam': {
      'goal': 'maintain',
      'heightCm': 172,
      'weightKg': 68,
      'bmi': 23.0,
      'allergies': ['tree_nut'],
      'dietaryRestrictions': <String>[],
    },
    'u_thao_vy': {
      'goal': 'maintain',
      'heightCm': 160,
      'weightKg': 50,
      'bmi': 19.5,
      'allergies': ['sesame'],
      'dietaryRestrictions': <String>[],
    },
    'u_ngoc_tram': {
      'goal': 'lose_weight',
      'heightCm': 155,
      'weightKg': 58,
      'bmi': 24.1,
      'allergies': <String>[],
      'dietaryRestrictions': ['low_sodium'],
    },
  };

  static Map<String, Object?>? _healthOf(String userId) {
    if (_healthSeeds[userId] case final seed?) return seed;
    if (userId != 'u_me') return null;
    final me = mockHealthProfileJson(syncProvider: 'none');
    return {
      for (final key in const [
        'goal',
        'heightCm',
        'weightKg',
        'bmi',
        'allergies',
        'dietaryRestrictions'
      ])
        key: me[key],
    };
  }

  MockChefRow _chef() {
    final id = currentUserId();
    if (id == null) throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.');
    if (currentRole() != UserRole.chef) {
      throw mockError(403, 'Chỉ dành cho chuyên gia.', 'not_chef');
    }
    return _db.chefOfUser(id) ??
        (throw mockError(
            404, 'Bạn chưa có hồ sơ chuyên gia.', 'chef_profile_missing'));
  }

  List<ChefClientDto> _clients() {
    final chef = _chef();
    final now = _db.now;
    final byBuyer = <String, List<MockOrderRow>>{};
    final mine = _db.orders
        .where((o) =>
            o.chefId == chef.id &&
            (o.status == OrderStatus.paid || o.status == OrderStatus.refunded))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final o in mine) {
      (byBuyer[o.userId] ??= []).add(o);
    }
    return [
      for (final MapEntry(key: userId, value: orders) in byBuyer.entries)
        _client(userId, orders, chefUserId: chef.userId, now: now),
    ];
  }

  ChefClientDto _client(String userId, List<MockOrderRow> orders,
      {required String chefUserId, required DateTime now}) {
    final packages = [
      for (final o in orders) _db.orderJson(o, withBuyer: true),
    ];
    final dtos = packages.map(OrderDto.fromJson).toList();
    final last = MockRecipeBook.chefSuggestions(userId)
        .where((s) => s['chefId'] == chefUserId)
        .firstOrNull;
    final recipe = last?['recipe'];
    return ChefClientDto.fromJson({
      'userId': userId,
      'fullName': orders.first.buyerName,
      'status': clientBucketOf(dtos, now).apiValue,
      'packages': packages,
      'health': _healthOf(userId),
      'lastSuggestion': last == null
          ? null
          : {
              'id': last['id'],
              'dishName': recipe is Map<String, Object?> ? recipe['name'] : '',
              'slot': last['slot'],
              'createdAt': last['createdAt'],
            },
    });
  }

  @override
  Future<List<ChefClientDto>> myClients({ClientBucket? status}) async {
    await mockDelay(500);
    _chef();
    if (MockCommerceDb.emptyScenario()) return const [];
    return _clients()
        .where((c) => status == null || c.status == status)
        .toList();
  }

  @override
  Future<ChefClientDto> client(String userId) async {
    await mockDelay(400);
    for (final c in _clients()) {
      if (c.userId == userId) return c;
    }
    throw mockError(404, 'Khách này chưa dùng dịch vụ nào của bạn.');
  }
}
