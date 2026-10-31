// lib/features/scanner/data/scanner_api_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../meal_planner/domain/allergy_match.dart';
import '../../recipe/data/recipe_catalog.dart';
import 'mock_scanner_repository.dart';
import 'models/scan_result_model.dart';

abstract interface class ScannerApiService {
  /// Sends a JPEG frame; returns detections with boxes, confidence and
  /// whether each food is vegan (`isVegan`).
  Future<ScanResultDto> scanImage(Uint8List jpegBytes);

  /// Menu ideas that use the confirmed vegan ingredients and avoid allergens.
  /// Never changes the member's plan.
  Future<List<MenuSuggestionDto>> generateMenu(GenerateMenuRequestDto request);
}

class RemoteScannerApiService implements ScannerApiService {
  RemoteScannerApiService(this._dio,
      {required RecipeCatalog Function() catalog})
      : _catalog = catalog;

  /// How many dishes "Gợi ý món" shows.
  static const maxSuggestions = 5;

  final Dio _dio;
  final RecipeCatalog Function() _catalog;

  @override
  Future<ScanResultDto> scanImage(Uint8List jpegBytes) => guardApi(() async {
        if (jpegBytes.isEmpty) {
          throw const ApiException(
              message: 'Chưa có ảnh để quét. Hãy chụp hoặc chọn ảnh khác.',
              statusCode: 400,
              code: 'no_image');
        }
        final form = FormData.fromMap({
          'image': MultipartFile.fromBytes(
            jpegBytes,
            filename: 'fridge.jpg',
            contentType: DioMediaType('image', 'jpeg'),
          ),
        });
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.visionScan,
          data: form,
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        return ScanResultDto.fromJson(res.data!);
      });

  /// Picked here from the recipe catalogue, by how many of the ingredients a
  /// recipe uses. The BE's own endpoint for this would overwrite the member's
  /// whole week, so it must never be called.
  @override
  Future<List<MenuSuggestionDto>> generateMenu(
      GenerateMenuRequestDto request) async {
    final names = [for (final i in request.ingredients) i.name];
    final scored = <(int, MenuSuggestionDto)>[];
    for (final recipe in await _catalog().load()) {
      final rows = [for (final i in recipe.ingredients) i.entity.name];
      final conflicts = allergyConflicts(
        tags: recipe.allergens,
        texts: [recipe.name, ...rows],
        userAllergies: request.excludeAllergens,
      );
      if (conflicts.isNotEmpty) continue;
      final used = [
        for (final row in rows)
          if (names.any((n) => sameFood(n, row))) row,
      ];
      if (used.isEmpty) continue;
      scored.add((
        used.length,
        MenuSuggestionDto(
          id: recipe.id,
          name: recipe.name,
          calories: recipe.caloriesCache ?? 0,
          prepMinutes: recipe.prepMinutes ?? 0,
          usedIngredients: used,
          missingIngredients: [
            for (final row in rows)
              if (!used.contains(row)) row,
          ],
          allergens: recipe.allergens,
        ),
      ));
    }
    // List.sort isn't stable: the catalogue's order isn't meaningful anyway.
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, dish) in scored.take(maxSuggestions)) dish];
  }
}

final scannerApiProvider = Provider<ScannerApiService>((ref) {
  if (BackendModules.isMock(BackendModule.scanner)) {
    return MockScannerRepository(scenario: Env.mockScanScenario);
  }
  return RemoteScannerApiService(ref.watch(dioProvider),
      catalog: () => ref.read(recipeCatalogProvider));
});
