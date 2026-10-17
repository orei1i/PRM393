// lib/features/meal_planner/data/allergen_api_service.dart
//
// GET /catalog/allergens?q=dau → [AllergenDto], accent-insensitive.
// [ { "id": "peanut", "name": "Đậu phộng", "aliases": ["lạc"] },
//   { "id": "mushroom", "name": "Nấm", "aliases": [] } ]
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/json_helpers.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../domain/allergy_match.dart';
import 'mock/allergen_catalog_data.dart';

/// An allergen people can pick in "Dị ứng".
class AllergenDto {
  const AllergenDto(
      {required this.id, required this.name, this.aliases = const []});

  factory AllergenDto.fromJson(Map<String, dynamic> json) => AllergenDto(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        aliases: readStringList(json['aliases']),
      );

  final String id;
  final String name;
  final List<String> aliases;

  /// What the health profile stores: the id when dishes are tagged with it,
  /// the name otherwise.
  String get key => isDishAllergenId(id) ? id : name;

  bool matches(String query) =>
      [name, ...aliases].any((n) => matchesQuery(n, query));

  /// Same name or alias as [text], ignoring accents and case.
  bool isNamed(String text) {
    final t = foldVietnamese(text.trim());
    return [name, ...aliases].any((n) => foldVietnamese(n) == t);
  }
}

abstract interface class AllergenApiService {
  /// Up to [limit] catalog allergens matching [query] (all when empty).
  Future<List<AllergenDto>> search(String query, {int limit = 8});
}

class RemoteAllergenApiService implements AllergenApiService {
  RemoteAllergenApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<AllergenDto>> search(String query, {int limit = 8}) =>
      guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.allergens,
            queryParameters: {'q': query.trim(), 'limit': limit});
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AllergenDto.fromJson)
            .toList();
      });
}

/// [mockAllergenCatalog]; `#fail` → 503.
class MockAllergenRepository implements AllergenApiService {
  @override
  Future<List<AllergenDto>> search(String query, {int limit = 8}) async {
    await mockDelay(150);
    if (query.contains('#fail')) {
      throw const ApiException(
          message: 'Chưa tải được gợi ý dị ứng.', statusCode: 503);
    }
    final all = mockAllergenCatalog.map(AllergenDto.fromJson);
    final q = query.trim();
    final hits =
        q.isEmpty ? all.toList() : all.where((a) => a.matches(q)).toList();
    // Names starting with the query first ("đậu" → Đậu phộng, Đậu nành…).
    final fq = foldVietnamese(q);
    hits.sort((a, b) {
      final sa = foldVietnamese(a.name).startsWith(fq) ? 0 : 1;
      final sb = foldVietnamese(b.name).startsWith(fq) ? 0 : 1;
      return sa.compareTo(sb);
    });
    return hits.take(limit).toList();
  }
}

final allergenApiProvider = Provider<AllergenApiService>((ref) {
  if (Env.useMockData) return MockAllergenRepository();
  return RemoteAllergenApiService(ref.watch(dioProvider));
});
