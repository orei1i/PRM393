// lib/features/ingredient/data/ingredient_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../recipe/data/mock/recipe_mock_data.dart';
import '../domain/entities/ingredient.dart';
import 'mock/ingredient_nutrition_data.dart';
import 'models/ingredient_model.dart';

/// The ingredient nutrition DB ("Nguyên liệu trong tủ" rows and detail).
abstract interface class IngredientApiService {
  /// Vegan ingredients whose name or alias matches [query] (accents and
  /// case ignored); an empty query lists them all.
  Future<List<IngredientSummaryDto>> search(String query);

  /// 404 when the id is unknown.
  Future<IngredientDetailDto> detail(String id);
}

class RemoteIngredientApiService implements IngredientApiService {
  RemoteIngredientApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<IngredientSummaryDto>> search(String query) => guardApi(() async {
        final res = await _dio
            .get<List<dynamic>>(ApiEndpoints.ingredients, queryParameters: {
          if (query.trim().isNotEmpty) 'q': query.trim(),
          'veganOnly': true,
        });
        final data = res.data ?? const [];
        return data
            .whereType<Map<String, dynamic>>()
            .map(IngredientSummaryDto.fromJson)
            .toList();
      });

  @override
  Future<IngredientDetailDto> detail(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.ingredient(id));
        return IngredientDetailDto.fromJson(res.data!);
      });
}

/// [mockIngredientRows] plus the catalogue recipes that use each ingredient.
/// `#fail` in a query or id → 503.
class MockIngredientRepository implements IngredientApiService {
  static List<IngredientSummary>? _index;

  /// Synchronous lookup for other mocks (the fridge stores the matched row).
  static IngredientSummary? match(String name) {
    final index = _index ??= [
      for (final row in mockIngredientRows)
        IngredientSummaryDto.fromJson(row).toEntity(),
    ];
    return findIngredient(index, name: name);
  }

  @override
  Future<List<IngredientSummaryDto>> search(String query) async {
    await mockDelay(300);
    if (query.contains('#fail')) {
      throw const ApiException(
          message: 'Chưa tải được dữ liệu dinh dưỡng. Thử lại sau nhé.',
          statusCode: 503);
    }
    final rows = mockIngredientRows.map(IngredientSummaryDto.fromJson);
    if (query.trim().isEmpty) return rows.toList();
    return rows
        .where((r) => [r.name, ...r.aliases].any((n) => matchesQuery(n, query)))
        .toList();
  }

  @override
  Future<IngredientDetailDto> detail(String id) async {
    await mockDelay(400);
    if (id.contains('#fail')) {
      throw const ApiException(
          message: 'Chưa tải được dữ liệu dinh dưỡng. Thử lại sau nhé.',
          statusCode: 503);
    }
    final row = mockIngredientRows.where((r) => r['id'] == id).firstOrNull;
    if (row == null) {
      throw const ApiException(
          message: 'Chưa có dữ liệu dinh dưỡng cho nguyên liệu này.',
          statusCode: 404,
          code: 'not_found');
    }
    return IngredientDetailDto.fromJson(
        {...row, 'recipes': _recipesUsing(row)});
  }

  /// Catalogue recipes whose name or ingredient rows mention the ingredient.
  static List<Map<String, Object?>> _recipesUsing(Map<String, Object?> row) {
    // Short names keep their accents ("bơ" is not "bò", "lạc" not "lắc");
    // longer ones don't need them ("dau hu" is "đậu hũ").
    String words(String s) =>
        ' ${s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.isNotEmpty).join(' ')} ';
    String folded(String s) =>
        ' ${foldVietnamese(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
    final names = [
      row['name']! as String,
      ...(row['aliases'] as List<Object?>? ?? const []).map((a) => '$a'),
    ];
    bool mentions(String text) => names.any((n) => folded(n).trim().length <= 3
        ? words(text).contains(words(n))
        : folded(text).contains(folded(n)));

    final ids = <String>{...handWrittenRecipes.keys, ...plannerRecipeIds()};
    final found = <Map<String, Object?>>[];
    for (final id in ids) {
      final detail = mockRecipeDetail(id);
      if (detail == null) continue;
      final rows = (detail['ingredients'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map((i) => '${i['name']}');
      if (mentions('${detail['name']}') || rows.any(mentions)) {
        found.add({
          'id': detail['id'],
          'name': detail['name'],
          'calories': detail['caloriesCache'],
        });
      }
      if (found.length == 6) break;
    }
    return found;
  }
}

final ingredientApiProvider = Provider<IngredientApiService>((ref) {
  if (Env.useMockData) return MockIngredientRepository();
  return RemoteIngredientApiService(ref.watch(dioProvider));
});

/// The whole (vegan) nutrition DB, to match free-text names (fridge items,
/// recipe rows) to a row. Kept for the app session.
final ingredientIndexProvider =
    FutureProvider<List<IngredientSummary>>((ref) async {
  final rows = await ref.watch(ingredientApiProvider).search('');
  return rows.map((r) => r.toEntity()).toList();
});

/// One ingredient's detail; dropped when its screen closes.
final ingredientDetailProvider = FutureProvider.autoDispose
    .family<IngredientDetail, String>((ref, id) async {
  return (await ref.watch(ingredientApiProvider).detail(id)).toEntity();
});
