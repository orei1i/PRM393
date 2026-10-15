// lib/features/meal_planner/data/pantry_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../scanner/domain/vegan_check.dart';
import 'meal_planner_api_service.dart';
import 'models/pantry_model.dart';

/// The member's fridge ("Nguyên liệu trong tủ"), `user_ingredients`: vegan
/// foods only.
abstract interface class PantryApiService {
  Future<List<PantryItemDto>> getPantry();

  /// Adds or refreshes (same name) several items; returns the whole list.
  /// A food that isn't vegan is refused (422 `not_vegan`).
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items);

  Future<void> removeItem(String id);

  Future<void> clear();
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

  @override
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items) =>
      guardApi(() async {
        final res = await _dio.post<List<dynamic>>(ApiEndpoints.myIngredients,
            data: {'items': items.map((i) => i.toJson()).toList()});
        return _items(res.data);
      });

  @override
  Future<void> removeItem(String id) => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.myIngredient(id));
      });

  @override
  Future<void> clear() => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.myIngredients);
      });
}

/// Per-account fridge kept for the app session. `#fail` in a name → 503; a
/// non-vegan name (same check as the scanner) → 422, like the server.
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
      PantryItemDto(
          id: 'pi_seed_dau_hu', ingredient: 'Đậu hũ', scannedAt: yesterday),
      PantryItemDto(
          id: 'pi_seed_ca_chua', ingredient: 'Cà chua', scannedAt: yesterday),
      PantryItemDto(
          id: 'pi_seed_nam_rom', ingredient: 'Nấm rơm', scannedAt: yesterday),
      const PantryItemDto(id: 'pi_seed_gao_lut', ingredient: 'Gạo lứt'),
    ];
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

  @override
  Future<List<PantryItemDto>> addItems(List<AddPantryItemDto> items) async {
    await mockDelay(500);
    _requireMember();
    if (items.any((i) => i.ingredient.toLowerCase().contains('#fail'))) {
      throw const ApiException(
          message: 'Chưa lưu được vào tủ lạnh. Thử lại nhé.', statusCode: 503);
    }
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
    final pantry = _pantryOf(userId);
    for (final item in items) {
      final name = item.ingredient.trim();
      if (name.isEmpty) continue;
      final key = foldVietnamese(name);
      final i = pantry.indexWhere((p) => foldVietnamese(p.ingredient) == key);
      final row = PantryItemDto(
        id: i >= 0
            ? pantry[i].id
            : 'pi_${DateTime.now().millisecondsSinceEpoch}_${_seq++}',
        ingredient: i >= 0 ? pantry[i].ingredient : name,
        scannedAt: item.scannedAt ?? (i >= 0 ? pantry[i].scannedAt : null),
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
  Future<void> clear() async {
    await mockDelay(400);
    _requireMember();
    _pantryOf(userId).clear();
  }
}

final pantryApiProvider = Provider<PantryApiService>((ref) {
  final userId = ref.watch(plannerUserIdProvider);
  if (Env.useMockData) return MockPantryRepository(userId: userId);
  return RemotePantryApiService(ref.watch(dioProvider));
});
