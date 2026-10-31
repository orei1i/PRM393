// lib/features/meal_planner/data/pantry_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../ingredient/data/ingredient_api_service.dart';
import '../../scanner/domain/vegan_check.dart';
import 'meal_planner_api_service.dart';
import 'models/pantry_model.dart';

/// The member's fridge ("Nguyên liệu trong tủ"), `user_ingredients`: vegan
/// foods only.
///
/// A food that isn't vegan is refused by the app on both sides: the real BE
/// would store it as vegan.
abstract interface class PantryApiService {
  Future<List<PantryItemDto>> getPantry();

  /// Adds or refreshes (same name) several items; returns the whole list.
  /// A food that isn't vegan is refused (422 `not_vegan`).
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items);

  Future<void> removeItem(String id);

  /// "Sửa số lượng & hạn dùng"; returns the updated row.
  Future<PantryItemDto> updateItem(String id, UpdatePantryItemDto request);

  /// "Hoàn tác" after [removeItem]: saves [item] again (same name and scan
  /// time) and returns the whole list. [index] is where the member saw it
  /// in that list, so it comes back there rather than on top like a new
  /// item.
  Future<List<PantryItemDto>> restoreItem(AddPantryItemDto item,
      {required int index});

  Future<void> clear();
}

/// Same check and same message as the scanner, on both sides.
void _refuseNonVegan(List<AddPantryItemDto> items) {
  for (final item in items) {
    if (!classifyVegan(item.ingredient).isVegan) {
      throw ApiException(
        message:
            '${item.ingredient.trim()} không thuần chay nên không lưu vào tủ.',
        statusCode: 422,
        code: 'not_vegan',
      );
    }
  }
}

class RemotePantryApiService implements PantryApiService {
  RemotePantryApiService(this._dio);

  final Dio _dio;

  List<PantryItemDto> _items(Object? data) => data is List<Object?>
      ? data
          .whereType<Map<String, dynamic>>()
          .map(PantryItemDto.fromJson)
          .toList()
      : const [];

  @override
  Future<List<PantryItemDto>> getPantry() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myIngredients);
        return _items(res.data);
      });

  /// The BE answers with the touched rows only, so the list is read again.
  @override
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items) =>
      guardApi(() async {
        _refuseNonVegan(items);
        await _dio.post<List<dynamic>>(ApiEndpoints.myIngredients,
            data: {'items': items.map((i) => i.toJson()).toList()});
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myIngredients);
        return _items(res.data);
      });

  @override
  Future<void> removeItem(String id) => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.myIngredient(id));
      });

  @override
  Future<PantryItemDto> updateItem(String id, UpdatePantryItemDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
            ApiEndpoints.myIngredient(id),
            data: request.toJson());
        return PantryItemDto.fromJson(res.data!);
      });

  /// Same request as [addItems]: the API lists the fridge in its own order,
  /// so `PantryController.restore` puts the row back at [index] on screen.
  @override
  Future<List<PantryItemDto>> restoreItem(AddPantryItemDto item,
          {required int index}) =>
      addItems([item]);

  @override
  Future<void> clear() => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.myIngredients);
      });
}

/// Per-account fridge kept for the app session. `#fail` in a name → 503; a
/// non-vegan name (same check as the scanner) → 422, like the server. Names
/// found in the nutrition DB carry its id, category and kcal per 100 g.
class MockPantryRepository implements PantryApiService {
  MockPantryRepository({this.userId});

  final String? userId;

  static final Map<String, List<PantryItemDto>> _pantries = {};
  static int _seq = 0;

  /// Back to the seeds (tests, via `MockMealPlannerRepository.reset`).
  static void reset() => _pantries.clear();

  /// Synchronous read for the mock planner ("Tạo thực đơn từ tủ lạnh").
  static List<PantryItemDto> itemsOf(String? userId) =>
      List.of(_pantryOf(userId));

  static List<PantryItemDto> _pantryOf(String? userId) =>
      _pantries[userId ?? 'guest'] ??= _seed(userId);

  static List<PantryItemDto> _seed(String? userId) {
    if (userId != 'u_me') return [];
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return [
      _row('pi_seed_dau_hu', 'Đậu hũ', yesterday),
      _row('pi_seed_ca_chua', 'Cà chua', yesterday),
      _row('pi_seed_nam_rom', 'Nấm rơm', yesterday),
      _row('pi_seed_gao_lut', 'Gạo lứt', null),
    ];
  }

  /// A fridge row joined with the nutrition DB, like the server returns it.
  static PantryItemDto _row(String id, String name, DateTime? scannedAt) {
    final match = MockIngredientRepository.match(name);
    return PantryItemDto(
      id: id,
      ingredient: name,
      scannedAt: scannedAt,
      ingredientId: match?.id,
      category: match?.category?.apiValue,
      caloriesPer100g: match?.caloriesPer100g,
    );
  }

  void _requireMember() {
    if (userId == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
  }

  @override
  Future<List<PantryItemDto>> getPantry() async {
    await mockDelay(400);
    if (userId == null) return const [];
    return List.of(_pantryOf(userId));
  }

  /// `#fail` → 503; anything not vegan → 422 `not_vegan`.
  static void _check(List<AddPantryItemDto> items) {
    if (items.any((i) => i.ingredient.toLowerCase().contains('#fail'))) {
      throw const ApiException(
          message: 'Chưa lưu được vào tủ lạnh. Thử lại nhé.', statusCode: 503);
    }
    _refuseNonVegan(items);
  }

  static String _newId() =>
      'pi_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';

  @override
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items) async {
    await mockDelay(500);
    _requireMember();
    _check(items);
    final pantry = _pantryOf(userId);
    for (final item in items) {
      final name = item.ingredient.trim();
      if (name.isEmpty) continue;
      final key = foldVietnamese(name);
      final i = pantry.indexWhere((p) => foldVietnamese(p.ingredient) == key);
      final row = _row(
        i >= 0 ? pantry[i].id : _newId(),
        i >= 0 ? pantry[i].ingredient : name,
        item.scannedAt ?? (i >= 0 ? pantry[i].scannedAt : null),
      );
      if (i >= 0) {
        pantry[i] = row;
      } else {
        pantry.insert(0, row);
      }
    }
    return List.of(pantry);
  }

  @override
  Future<void> removeItem(String id) async {
    await mockDelay(300);
    _requireMember();
    _pantryOf(userId).removeWhere((p) => p.id == id);
  }

  @override
  Future<PantryItemDto> updateItem(
      String id, UpdatePantryItemDto request) async {
    await mockDelay(300);
    _requireMember();
    final pantry = _pantryOf(userId);
    final i = pantry.indexWhere((p) => p.id == id);
    if (i < 0) {
      throw const ApiException(
          message: 'Không tìm thấy nguyên liệu.', statusCode: 404);
    }
    final old = pantry[i];
    return pantry[i] = PantryItemDto(
      id: old.id,
      ingredient: old.ingredient,
      scannedAt: old.scannedAt,
      ingredientId: old.ingredientId,
      category: old.category,
      caloriesPer100g: old.caloriesPer100g,
      quantity: request.quantity,
      unit: request.unit,
      expiryDate: request.expiryDate ?? old.expiryDate,
    );
  }

  /// Back at [index] (clamped). Already there again (scanned or typed in
  /// meanwhile) → that row stays where it is.
  @override
  Future<List<PantryItemDto>> restoreItem(AddPantryItemDto item,
      {required int index}) async {
    await mockDelay(400);
    _requireMember();
    _check([item]);
    final pantry = _pantryOf(userId);
    final name = item.ingredient.trim();
    final key = foldVietnamese(name);
    if (name.isNotEmpty &&
        !pantry.any((p) => foldVietnamese(p.ingredient) == key)) {
      pantry.insert(
          index.clamp(0, pantry.length), _row(_newId(), name, item.scannedAt));
    }
    return List.of(pantry);
  }

  @override
  Future<void> clear() async {
    await mockDelay(400);
    _requireMember();
    _pantryOf(userId).clear();
  }
}

final pantryApiProvider = Provider<PantryApiService>((ref) {
  final userId = ref.watch(plannerPersonaIdProvider);
  if (BackendModules.isMock(BackendModule.pantry)) {
    return MockPantryRepository(userId: userId);
  }
  return RemotePantryApiService(ref.watch(dioProvider));
});
