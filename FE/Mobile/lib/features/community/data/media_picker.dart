// lib/features/community/data/media_picker.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/theme/vl_colors.dart';
import '../../../core/utils/formatters.dart';

enum MediaKind { image, video }

/// A photo or video chosen on the device, before upload.
class PickedMedia {
  const PickedMedia({
    required this.name,
    required this.sizeBytes,
    required this.kind,
    this.durationSeconds = 0,
    this.path,
  });

  const PickedMedia.video({
    required this.name,
    required this.sizeBytes,
    required this.durationSeconds,
    this.path,
  }) : kind = MediaKind.video;

  const PickedMedia.image({
    required this.name,
    required this.sizeBytes,
    this.path,
  })  : kind = MediaKind.image,
        durationSeconds = 0;

  final String name;
  final int sizeBytes;
  final MediaKind kind;

  /// Videos only; 0 when unknown (the server measures it anyway).
  final int durationSeconds;

  /// Local file path; `null` for the mock samples (nothing to read).
  final String? path;

  bool get isVideo => kind == MediaKind.video;
  bool get isImage => kind == MediaKind.image;

  /// Lower-case extension without the dot ("mp4").
  String get extension => extensionOf(name);

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// "48 MB · 8:06" for a video, "2,1 MB" for a photo.
  String get summary => isVideo && durationSeconds > 0
      ? '${formatFileSize(sizeBytes)} · ${formatDuration(durationSeconds)}'
      : formatFileSize(sizeBytes);
}

/// Client-side checks, mirrored by the server (413 / 415).
abstract final class MediaUploadRules {
  /// The real BE takes 100 MB (`RequestSizeLimit` on `/media/videos`).
  static int get _maxVideoMb =>
      BackendModules.isReal(BackendModule.media) ? 100 : 200;
  static int get maxVideoBytes => _maxVideoMb * 1024 * 1024;
  static const int maxImageBytes = 10 * 1024 * 1024;
  static const videoExtensions = {'mp4', 'mov', 'webm'};
  static const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

  static const imageHint = 'Ảnh JPG, PNG, WEBP, HEIC tối đa 10 MB';
  static String get videoHint => 'Video MP4, MOV, WEBM tối đa $_maxVideoMb MB';

  /// Photos and videos: "Ảnh JPG, PNG, WEBP, HEIC tối đa 10 MB · Video MP4,
  /// MOV, WEBM tối đa 200 MB".
  static String get hint => '$imageHint · $videoHint';

  /// The formats and limits of only what [kinds] allows (a photo-only
  /// picker doesn't advertise video formats).
  static String hintFor(Set<MediaKind> kinds) => [
        if (kinds.contains(MediaKind.image)) imageHint,
        if (kinds.contains(MediaKind.video)) videoHint,
      ].join(' · ');

  /// "Chọn ảnh", "Chọn video" or "Chọn ảnh hoặc video".
  static String titleFor(Set<MediaKind> kinds) {
    final image = kinds.contains(MediaKind.image);
    final video = kinds.contains(MediaKind.video);
    if (image && video) return 'Chọn ảnh hoặc video';
    return video ? 'Chọn video' : 'Chọn ảnh';
  }

  /// `null` when [media] can be uploaded, otherwise the message to show.
  static String? validate(PickedMedia media) {
    if (media.isVideo) {
      if (!videoExtensions.contains(media.extension)) {
        return 'Định dạng video chưa hỗ trợ';
      }
      if (media.sizeBytes > maxVideoBytes) {
        return 'Video vượt quá $_maxVideoMb MB';
      }
      return null;
    }
    if (!imageExtensions.contains(media.extension)) {
      return 'Định dạng ảnh chưa hỗ trợ';
    }
    if (media.sizeBytes > maxImageBytes) return 'Ảnh vượt quá 10 MB';
    return null;
  }

  /// 413 for a file over the limit, 415 for a format the server refuses.
  static int statusFor(PickedMedia media) =>
      media.sizeBytes > (media.isVideo ? maxVideoBytes : maxImageBytes)
          ? 413
          : 415;
}

/// 50331648 → "48 MB", 2202010 → "2,1 MB", 1610612736 → "1,5 GB".
String formatFileSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${formatDecimal(bytes / (1024 * mb))} GB';
  if (bytes >= 10 * mb) return '${(bytes / mb).round()} MB';
  if (bytes >= mb) return '${formatDecimal(bytes / mb)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

abstract interface class MediaPickerService {
  /// `null` when the user closes the picker. [kinds] limits what may be
  /// picked (photos only for a complaint, for example).
  Future<PickedMedia?> pick(BuildContext context,
      {Set<MediaKind> kinds = const {MediaKind.image, MediaKind.video}});
}

/// The device gallery (`image_picker`: the system photo picker on Android,
/// so no storage permission; `NSPhotoLibraryUsageDescription` on iOS).
/// Reads the file size and, for a video the platform can play, its length.
class GalleryMediaPickerService implements MediaPickerService {
  const GalleryMediaPickerService();

  @override
  Future<PickedMedia?> pick(BuildContext context,
      {Set<MediaKind> kinds = const {MediaKind.image, MediaKind.video}}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picker = ImagePicker();
      final XFile? file;
      if (kinds.length > 1) {
        file = await picker.pickMedia();
      } else if (kinds.contains(MediaKind.video)) {
        file = await picker.pickVideo(source: ImageSource.gallery);
      } else {
        file = await picker.pickImage(source: ImageSource.gallery);
      }
      if (file == null) return null;
      final size = await file.length();
      final isVideo = _looksLikeVideo(file);
      if (!kinds.contains(isVideo ? MediaKind.video : MediaKind.image)) {
        messenger?.showSnackBar(SnackBar(
            content: Text(isVideo
                ? 'Chỉ chọn được ảnh ở đây.'
                : 'Chỉ chọn được video ở đây.')));
        return null;
      }
      if (!isVideo) {
        return PickedMedia.image(
            name: file.name, sizeBytes: size, path: file.path);
      }
      return PickedMedia.video(
        name: file.name,
        sizeBytes: size,
        durationSeconds: await _durationOf(file.path),
        path: file.path,
      );
    } catch (e) {
      final denied = e.toString().contains('access_denied');
      messenger?.showSnackBar(SnackBar(
        content: Text(denied
            ? 'VeganLife chưa được cấp quyền xem ảnh và video. Hãy bật quyền Ảnh trong Cài đặt.'
            : 'Chưa mở được thư viện ảnh trên máy này.'),
      ));
      return null;
    }
  }

  static bool _looksLikeVideo(XFile file) {
    final mime = file.mimeType;
    if (mime != null) return mime.startsWith('video/');
    return MediaUploadRules.videoExtensions
        .contains(PickedMedia.extensionOf(file.name));
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
/// `dau_hu_sot_ca.jpg`, `anh_qua_lon.png`, `banh_xeo_chay.mp4`,
/// `mat_ket_noi.mp4`, `video_4k_qua_lon.mov`).
class MockMediaPickerService implements MediaPickerService {
  const MockMediaPickerService(
      {this.gallery = const GalleryMediaPickerService()});

  /// "Chọn từ thư viện" (a real file; the mock upload only reads its name,
  /// size and length).
  final MediaPickerService gallery;

  static const imageSamples = [
    PickedMedia.image(name: 'dau_hu_sot_ca.jpg', sizeBytes: 2202010),
    // 14 MB: refused before uploading.
    PickedMedia.image(name: 'anh_qua_lon.png', sizeBytes: 14680064),
  ];

  static const videoSamples = [
    PickedMedia.video(
        name: 'banh_xeo_chay.mp4', sizeBytes: 50331648, durationSeconds: 486),
    // The mock upload loses the connection at 60 %.
    PickedMedia.video(
        name: 'mat_ket_noi.mp4', sizeBytes: 37748736, durationSeconds: 312),
    // 850 MB: refused before uploading.
    PickedMedia.video(
        name: 'video_4k_qua_lon.mov',
        sizeBytes: 891289600,
        durationSeconds: 1265),
  ];

  static const samples = [...imageSamples, ...videoSamples];

  static const _hints = {
    'anh_qua_lon.png': 'Mô phỏng ảnh quá dung lượng',
    'mat_ket_noi.mp4': 'Mô phỏng mất kết nối khi đang tải lên',
    'video_4k_qua_lon.mov': 'Mô phỏng video quá dung lượng',
  };

  /// What the samples offered for [kinds] let the tester try (photos have
  /// no lost-connection sample).
  static String samplesHintFor(Set<MediaKind> kinds) {
    final image = kinds.contains(MediaKind.image);
    final video = kinds.contains(MediaKind.video);
    if (image && video) {
      return 'Dùng để thử tải lên thành công, mất kết nối và tệp quá lớn.';
    }
    return video
        ? 'Dùng để thử tải lên thành công, mất kết nối và video quá lớn.'
        : 'Dùng để thử tải lên thành công và ảnh quá lớn.';
  }

  @override
  Future<PickedMedia?> pick(BuildContext context,
      {Set<MediaKind> kinds = const {MediaKind.image, MediaKind.video}}) async {
    final offered = samples.where((m) => kinds.contains(m.kind)).toList();
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(MediaUploadRules.titleFor(kinds),
                  style: context.textStyles.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(kinds.contains(MediaKind.image)
                    ? Icons.photo_library_outlined
                    : Icons.video_library_outlined),
                title: const Text('Chọn từ thư viện'),
                subtitle: Text(MediaUploadRules.hintFor(kinds)),
                onTap: () => Navigator.of(context).pop(_galleryChoice),
              ),
              const Divider(),
              Text('Tệp mẫu (mô phỏng)', style: context.textStyles.titleSmall),
              Text(
                samplesHintFor(kinds),
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
              const SizedBox(height: 4),
              for (final media in offered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(media.isVideo
                      ? Icons.movie_outlined
                      : Icons.image_outlined),
                  title: Text(media.name),
                  subtitle: Text(_hints[media.name] == null
                      ? media.summary
                      : '${media.summary}\n${_hints[media.name]}'),
                  isThreeLine: _hints[media.name] != null,
                  onTap: () => Navigator.of(context).pop(media),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice is PickedMedia) return choice;
    if (choice == _galleryChoice && context.mounted) {
      return gallery.pick(context, kinds: kinds);
    }
    return null;
  }

  static const _galleryChoice = 'gallery';
}

/// Mock mode keeps the sample files next to the real gallery; with the real
/// API only the gallery is offered. Shared with the restaurant suggestion
/// and complaint forms.
final mediaPickerProvider = Provider<MediaPickerService>((ref) =>
    BackendModules.isMock(BackendModule.media)
        ? const MockMediaPickerService()
        : const GalleryMediaPickerService());
