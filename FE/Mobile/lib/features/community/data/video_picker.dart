// lib/features/community/data/video_picker.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/vl_colors.dart';
import '../../../core/utils/formatters.dart';

/// A video file chosen on the device, before upload.
class PickedVideo {
  const PickedVideo({
    required this.name,
    required this.sizeBytes,
    required this.durationSeconds,
    this.path,
  });

  final String name;
  final int sizeBytes;
  final int durationSeconds;

  /// Local file path; `null` for the mock samples (nothing to read).
  final String? path;

  /// Lower-case extension without the dot ("mp4").
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// "48 MB · 8:06"
  String get summary =>
      '${formatFileSize(sizeBytes)} · ${formatDuration(durationSeconds)}';
}

/// Client-side checks, mirrored by the server (413 / 415).
abstract final class VideoUploadRules {
  static const int maxBytes = 200 * 1024 * 1024;
  static const extensions = {'mp4', 'mov', 'webm'};

  /// `null` when [video] can be uploaded, otherwise the message to show.
  static String? validate(PickedVideo video) {
    if (!extensions.contains(video.extension)) return 'Định dạng chưa hỗ trợ';
    if (video.sizeBytes > maxBytes) return 'Video vượt quá 200 MB';
    return null;
  }
}

/// 50331648 → "48 MB", 891289600 → "850 MB", 1610612736 → "1,5 GB".
String formatFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${formatDecimal(bytes / (1024 * mb))} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}

abstract interface class VideoPickerService {
  /// `null` when the user closes the picker.
  Future<PickedVideo?> pick(BuildContext context);
}

/// The device gallery (`image_picker`: the system photo picker on Android,
/// so no storage permission; `NSPhotoLibraryUsageDescription` on iOS).
/// Reads the file size and, when the platform can play the file, its length.
class GalleryVideoPickerService implements VideoPickerService {
  const GalleryVideoPickerService();

  @override
  Future<PickedVideo?> pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (file == null) return null;
      final size = await file.length();
      return PickedVideo(
        name: file.name,
        sizeBytes: size,
        durationSeconds: await _durationOf(file.path),
        path: file.path,
      );
    } catch (e) {
      final denied = e.toString().contains('access_denied');
      messenger?.showSnackBar(SnackBar(
        content: Text(denied
            ? 'VeganLife chưa được cấp quyền xem video. Hãy bật quyền Ảnh trong Cài đặt.'
            : 'Chưa mở được thư viện video trên máy này.'),
      ));
      return null;
    }
  }

  /// 0 when the length can't be read (the server measures it anyway).
  static Future<int> _durationOf(String path) async {
    VideoPlayerController? controller;
    try {
      controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(path))
          : VideoPlayerController.file(File(path));
      await controller.initialize().timeout(const Duration(seconds: 5));
      return controller.value.duration.inSeconds;
    } catch (_) {
      return 0;
    } finally {
      await controller?.dispose();
    }
  }
}

/// Mock mode: the real gallery first, then sample files that exercise the
/// success, network-failure and too-large paths of the mock upload (QA:
/// `banh_xeo_chay.mp4`, `mat_ket_noi.mp4`, `video_4k_qua_lon.mov`).
class MockVideoPickerService implements VideoPickerService {
  const MockVideoPickerService(
      {this.gallery = const GalleryVideoPickerService()});

  /// "Chọn từ thư viện" (a real file; the mock upload only reads its name,
  /// size and length).
  final VideoPickerService gallery;

  static const samples = [
    PickedVideo(
        name: 'banh_xeo_chay.mp4', sizeBytes: 50331648, durationSeconds: 486),
    // The mock upload loses the connection at 60 %.
    PickedVideo(
        name: 'mat_ket_noi.mp4', sizeBytes: 37748736, durationSeconds: 312),
    // 850 MB: rejected before uploading.
    PickedVideo(
        name: 'video_4k_qua_lon.mov',
        sizeBytes: 891289600,
        durationSeconds: 1265),
  ];

  static const _hints = {
    'mat_ket_noi.mp4': 'Mô phỏng mất kết nối khi đang tải lên',
    'video_4k_qua_lon.mov': 'Mô phỏng tệp quá dung lượng',
  };

  @override
  Future<PickedVideo?> pick(BuildContext context) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chọn video', style: context.textStyles.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Chọn từ thư viện'),
                subtitle: const Text('MP4, MOV hoặc WEBM, tối đa 200 MB'),
                onTap: () => Navigator.of(context).pop(_galleryChoice),
              ),
              const Divider(),
              Text('Tệp mẫu (mô phỏng)', style: context.textStyles.titleSmall),
              Text(
                'Dùng để thử tải lên thành công, mất kết nối và tệp quá lớn.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
              const SizedBox(height: 4),
              for (final video in samples)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.movie_outlined),
                  title: Text(video.name),
                  subtitle: Text(_hints[video.name] == null
                      ? video.summary
                      : '${video.summary}\n${_hints[video.name]}'),
                  isThreeLine: _hints[video.name] != null,
                  onTap: () => Navigator.of(context).pop(video),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice is PickedVideo) return choice;
    if (choice == _galleryChoice && context.mounted) {
      return gallery.pick(context);
    }
    return null;
  }

  static const _galleryChoice = 'gallery';
}

/// Mock mode keeps the sample files next to the real gallery; with the real
/// API only the gallery is offered.
final videoPickerProvider = Provider<VideoPickerService>((ref) =>
    Env.useMockData
        ? const MockVideoPickerService()
        : const GalleryVideoPickerService());
