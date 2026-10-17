// lib/features/community/data/media_api_service.dart
//
// POST /media/videos   multipart: file   (progress from Dio onSendProgress)
// → { "mediaUrl": "https://res.cloudinary.com/veganlife/video/upload/v1/abc.mp4",
//     "durationSeconds": 486, "sizeBytes": 50331648 }
// POST /media/images   multipart: file   (jpg / png / webp / heic, at most 10 MB)
// → { "mediaUrl": "https://res.cloudinary.com/veganlife/image/upload/v1/abc.jpg",
//     "sizeBytes": 2202010, "width": 1280, "height": 960 }
// 413 too large, 415 unsupported format.
//
// Public contract shared with the restaurant suggestion form and the
// complaint form: `mediaApiProvider.uploadVideo / uploadImage` with a
// [PickedMedia] from `mediaPickerProvider`.
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'media_picker.dart';

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

class UploadedImageDto {
  const UploadedImageDto({
    required this.mediaUrl,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  factory UploadedImageDto.fromJson(Map<String, dynamic> json) =>
      UploadedImageDto(
        mediaUrl: json['mediaUrl'] as String? ?? '',
        sizeBytes: readInt(json['sizeBytes']),
        width: json['width'] == null ? null : readInt(json['width']),
        height: json['height'] == null ? null : readInt(json['height']),
      );

  final String mediaUrl;
  final int sizeBytes;
  final int? width;
  final int? height;
}

abstract interface class MediaApiService {
  /// Uploads [video]; [onProgress] receives 0…1. Cancelling [cancelToken]
  /// throws an [ApiException] with code `cancelled`.
  Future<UploadedVideoDto> uploadVideo(
    PickedMedia video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });

  /// Uploads [image] (jpg / png / webp / heic, at most 10 MB); same progress
  /// and cancel rules as [uploadVideo].
  Future<UploadedImageDto> uploadImage(
    PickedMedia image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });
}

class RemoteMediaApiService implements MediaApiService {
  RemoteMediaApiService(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> _upload(
    String endpoint,
    PickedMedia media, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final path = media.path;
    if (path == null) {
      throw const ApiException(
          message: 'Không đọc được tệp trên máy.', code: 'no_file');
    }
    // A cancelled request maps to code `cancelled` in [guardApi].
    final res = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(path, filename: media.name),
      }),
      cancelToken: cancelToken,
      onSendProgress: (sent, total) {
        if (total > 0) onProgress?.call(sent / total);
      },
      // Large files on slow networks.
      options: Options(sendTimeout: const Duration(minutes: 10)),
    );
    return res.data!;
  }

  @override
  Future<UploadedVideoDto> uploadVideo(
    PickedMedia video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      guardApi(() async => UploadedVideoDto.fromJson(await _upload(
          ApiEndpoints.uploadVideo, video,
          onProgress: onProgress, cancelToken: cancelToken)));

  @override
  Future<UploadedImageDto> uploadImage(
    PickedMedia image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) =>
      guardApi(() async => UploadedImageDto.fromJson(await _upload(
          ApiEndpoints.uploadImage, image,
          onProgress: onProgress, cancelToken: cancelToken)));
}

/// Simulated upload: progress ticks 10 % every [tick]. `mat_ket_noi.mp4`
/// loses the connection at 60 %; files over the limit or with another
/// format are refused like the server would (413 / 415).
class MockMediaRepository implements MediaApiService {
  MockMediaRepository({this.tick = const Duration(milliseconds: 300)});

  final Duration tick;

  /// Uploaded URL → duration, so the mock feed knows the clip length.
  static final Map<String, int> _durations = {};

  static int? durationOf(String url) => _durations[url];

  Future<void> _simulate(PickedMedia media,
      {void Function(double progress)? onProgress,
      CancelToken? cancelToken}) async {
    final invalid = MediaUploadRules.validate(media);
    if (invalid != null) {
      throw ApiException(
          message: invalid, statusCode: MediaUploadRules.statusFor(media));
    }
    onProgress?.call(0);
    for (var step = 1; step <= 10; step++) {
      await Future<void>.delayed(tick);
      if (cancelToken?.isCancelled ?? false) {
        throw const ApiException(message: 'Đã huỷ tải lên.', code: 'cancelled');
      }
      if (media.name == 'mat_ket_noi.mp4' && step == 6) {
        onProgress?.call(0.6);
        throw const ApiException(
          message: 'Mất kết nối khi đang tải lên. Thử lại nhé.',
          code: 'network',
        );
      }
      onProgress?.call(step / 10);
    }
  }

  @override
  Future<UploadedVideoDto> uploadVideo(
    PickedMedia video, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await _simulate(video, onProgress: onProgress, cancelToken: cancelToken);
    final url = 'https://res.cloudinary.com/veganlife/video/upload/v1/mock/'
        '${DateTime.now().millisecondsSinceEpoch}_${video.name}';
    _durations[url] = video.durationSeconds;
    return UploadedVideoDto(
      mediaUrl: url,
      durationSeconds: video.durationSeconds,
      sizeBytes: video.sizeBytes,
    );
  }

  @override
  Future<UploadedImageDto> uploadImage(
    PickedMedia image, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    await _simulate(image, onProgress: onProgress, cancelToken: cancelToken);
    return UploadedImageDto(
      mediaUrl: 'https://res.cloudinary.com/veganlife/image/upload/v1/mock/'
          '${DateTime.now().millisecondsSinceEpoch}_${image.name}',
      sizeBytes: image.sizeBytes,
      width: 1280,
      height: 960,
    );
  }
}

final mediaApiProvider = Provider<MediaApiService>((ref) {
  if (Env.useMockData) return MockMediaRepository();
  return RemoteMediaApiService(ref.watch(dioProvider));
});
