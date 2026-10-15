// lib/features/scanner/data/scanner_api_service.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import 'mock_scanner_repository.dart';
import 'models/scan_result_model.dart';

abstract interface class ScannerApiService {
  /// Sends a JPEG frame; returns detections with boxes, confidence and
  /// whether each food is vegan (`isVegan`).
  Future<ScanResultDto> scanImage(Uint8List jpegBytes);

  /// AI menu ideas that use the confirmed vegan ingredients and avoid
  /// allergens.
  Future<List<MenuSuggestionDto>> generateMenu(GenerateMenuRequestDto request);
}

class RemoteScannerApiService implements ScannerApiService {
  RemoteScannerApiService(this._dio);

  final Dio _dio;

  @override
  Future<ScanResultDto> scanImage(Uint8List jpegBytes) => guardApi(() async {
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

  @override
  Future<List<MenuSuggestionDto>> generateMenu(
          GenerateMenuRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<List<dynamic>>(
          ApiEndpoints.menuFromIngredients,
          data: request.toJson(),
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuSuggestionDto.fromJson)
            .toList();
      });
}

final scannerApiProvider = Provider<ScannerApiService>((ref) {
  if (Env.useMockData) {
    return MockScannerRepository(scenario: Env.mockScanScenario);
  }
  return RemoteScannerApiService(ref.watch(dioProvider));
});
