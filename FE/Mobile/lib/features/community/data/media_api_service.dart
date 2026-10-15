// lib/features/community/data/media_api_service.dart
//
// POST /media/videos   multipart: file   (progress from Dio onSendProgress)
// → { "mediaUrl": "https://res.cloudinary.com/veganlife/video/upload/v1/abc.mp4",
//     "durationSeconds": 486, "sizeBytes": 50331648 }
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'video_picker.dart';

class UploadedVideoDto {
  const UploadedVideoDto({
    required this.mediaUrl,
    required this.durationSeconds,
    required this.sizeBytes,
  });

  factory UploadedVideoDto.fromJson(Map<String, dynamic> json) =>
      UploadedVideoDto(
        mediaUrl: json['mediaUrl'] as String? ?? '',
        durationSeconds: readInt(json['durationSeconds']),
        sizeBytes: readInt(json['sizeBytes']),
      );

  final String mediaUrl;
  final int durationSeconds;
  final int sizeBytes;
}

abstract interface class MediaApiService {
  /// Uploads [video]; [onProgress] receives 0…1. Cancelling [cancelToken]
  /// throws an [ApiException] with code `cancelled`.
  Future<UploadedVideoDto> uploadVideo(
    PickedVideo video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });
}

class RemoteMediaApiService implements MediaApiService {
  RemoteMediaApiService(this._dio);

  final Dio _dio;

  @override
  Future<UploadedVideoDto> uploadVideo(
    PickedVideo video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      guardApi(() async {
        final path = video.path;
        if (path == null) {
          throw const ApiException(
              message: 'Không đọc được tệp video trên máy.', code: 'no_file');
        }
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.uploadVideo,
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(path, filename: video.name),
          }),
          cancelToken: cancelToken,
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
          // Large files on slow networks.
          options: Options(sendTimeout: const Duration(minutes: 10)),
        );
        return UploadedVideoDto.fromJson(res.data!);
      });
}

/// Simulated upload: progress ticks 10 % every [tick]. `mat_ket_noi.mp4`
/// loses the connection at 60 %; files over 200 MB or with another format
/// are refused like the server would (413 / 415).
class MockMediaRepository implements MediaApiService {
  MockMediaRepository({this.tick = const Duration(milliseconds: 300)});

  final Duration tick;

  /// Uploaded URL → duration, so the mock feed knows the clip length.
  static final Map<String, int> _durations = {};

  static int? durationOf(String url) => _durations[url];

  @override
  Future<UploadedVideoDto> uploadVideo(
    PickedVideo video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final invalid = VideoUploadRules.validate(video);
    if (invalid != null) {
      throw ApiException(
        message: invalid,
        statusCode: video.sizeBytes > VideoUploadRules.maxBytes ? 413 : 415,
      );
    }
    onProgress?.call(0);
    for (var step = 1; step <= 10; step++) {
      await Future<void>.delayed(tick);
      if (cancelToken?.isCancelled ?? false) {
        throw const ApiException(message: 'Đã huỷ tải lên.', code: 'cancelled');
      }
      if (video.name == 'mat_ket_noi.mp4' && step == 6) {
        onProgress?.call(0.6);
        throw const ApiException(
          message: 'Mất kết nối khi đang tải video lên. Thử lại nhé.',
          code: 'network',
        );
      }
      onProgress?.call(step / 10);
    }
    final url = 'https://res.cloudinary.com/veganlife/video/upload/v1/mock/'
        '${DateTime.now().millisecondsSinceEpoch}_${video.name}';
    _durations[url] = video.durationSeconds;
    return UploadedVideoDto(
      mediaUrl: url,
      durationSeconds: video.durationSeconds,
      sizeBytes: video.sizeBytes,
    );
  }
}

final mediaApiProvider = Provider<MediaApiService>((ref) {
  if (Env.useMockData) return MockMediaRepository();
  return RemoteMediaApiService(ref.watch(dioProvider));
});
