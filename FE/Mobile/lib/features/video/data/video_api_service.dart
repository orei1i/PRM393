// lib/features/video/data/video_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/mock_delay.dart';
import 'mock/mock_video_store.dart';
import 'models/video_model.dart';

abstract interface class VideoApiService {
  Future<VideoRecipeDto> getVideo(String id);

  /// Re-runs speech-to-text + extraction for a failed video.
  Future<void> retryExtraction(String id);
}

class RemoteVideoApiService implements VideoApiService {
  RemoteVideoApiService(this._dio);

  final Dio _dio;

  @override
  Future<VideoRecipeDto> getVideo(String id) => guardApi(() async {
        final res =
            await _dio.get<Map<String, dynamic>>(ApiEndpoints.video(id));
        return VideoRecipeDto.fromJson(res.data!);
      });

  @override
  Future<void> retryExtraction(String id) => guardApi(() async {
        await _dio.post<void>(ApiEndpoints.videoRetryExtraction(id));
      });
}

class MockVideoRepository implements VideoApiService {
  final _store = MockVideoStore.instance;

  @override
  Future<VideoRecipeDto> getVideo(String id) async {
    await mockDelay(400);
    final video = _store.get(id);
    if (video == null) {
      throw const ApiException(
          message: 'Video không còn tồn tại.', statusCode: 404);
    }
    return video;
  }

  @override
  Future<void> retryExtraction(String id) async {
    await mockDelay(500);
    _store.retry(id);
  }
}

final videoApiProvider = Provider<VideoApiService>((ref) {
  if (Env.useMockData) return MockVideoRepository();
  return RemoteVideoApiService(ref.watch(dioProvider));
});
