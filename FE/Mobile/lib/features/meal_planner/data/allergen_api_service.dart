// lib/features/meal_planner/data/allergen_api_service.dart
//
// GET /catalog/allergens → [AllergenDto]. The real BE sends `allergenId`, no
// aliases, and ignores `q` and `limit`, so the app searches the list itself:
// [ { "allergenId": "peanut", "name": "Đậu phộng (Lạc)",
//     "description": "Dị ứng liên quan đến peanut" } ]
// The mock's rows: { "id": "peanut", "name": "Đậu phộng", "aliases": ["lạc"] }
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
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

  /// Reading `allergenId` is what keeps allergies safe: without an id a pick
  /// becomes the free text "Đậu phộng (Lạc)", and the BE then looks for that
  /// whole phrase in a recipe instead of the `peanut` tag.
  factory AllergenDto.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return AllergenDto(
      id: (json['allergenId'] ?? json['id'])?.toString() ?? '',
      name: name,
      aliases: json['aliases'] == null
          ? _namesInLabel(name)
          : readStringList(json['aliases']),
    );
  }

  /// "Đậu phộng (Lạc)" → Đậu phộng, Lạc: the BE keeps its aliases in the label,
  /// so typing "lạc" or "đậu phộng" still finds the catalog allergen.
  static List<String> _namesInLabel(String label) {
    final open = label.indexOf('(');
    if (open < 0 || !label.endsWith(')')) return const [];
    return [
      label.substring(0, open),
      ...label.substring(open + 1, label.length - 1).split(','),
    ]
        .map((n) => n.replaceAll('...', '').trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

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

  /// The BE's whole catalog, fetched once: it is small and has no search.
  List<AllergenDto>? _catalog;

  @override
  Future<List<AllergenDto>> search(String query, {int limit = 8}) =>
      guardApi(() async {
        final all = _catalog ??= await _fetch();
        return searchAllergens(all, query, limit: limit);
      });

  Future<List<AllergenDto>> _fetch() async {
    final res = await _dio.get<List<dynamic>>(ApiEndpoints.allergens);
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AllergenDto.fromJson)
        .toList();
  }
}

/// Up to [limit] of [all] matching [query], names starting with it first
/// ("đậu" → Đậu phộng, Đậu nành…). An empty query matches all.
List<AllergenDto> searchAllergens(Iterable<AllergenDto> all, String query,
    {required int limit}) {
  final q = query.trim();
  final hits =
      q.isEmpty ? all.toList() : all.where((a) => a.matches(q)).toList();
  final fq = foldVietnamese(q);
  hits.sort((a, b) {
    final sa = foldVietnamese(a.name).startsWith(fq) ? 0 : 1;
    final sb = foldVietnamese(b.name).startsWith(fq) ? 0 : 1;
    return sa.compareTo(sb);
  });
  return hits.take(limit).toList();
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
    return searchAllergens(mockAllergenCatalog.map(AllergenDto.fromJson), query,
        limit: limit);
  }
}

final allergenApiProvider = Provider<AllergenApiService>((ref) {
  if (BackendModules.isMock(BackendModule.allergens)) {
    return MockAllergenRepository();
  }
  return RemoteAllergenApiService(ref.watch(dioProvider));
});
