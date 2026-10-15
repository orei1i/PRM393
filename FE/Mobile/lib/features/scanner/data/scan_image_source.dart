// lib/features/scanner/data/scan_image_source.dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// The gallery can't be opened (no permission, no plugin on this platform).
class ScanPickerUnavailable implements Exception {
  const ScanPickerUnavailable(
      [this.message = 'Chưa mở được thư viện ảnh trên máy này.']);

  final String message;

  @override
  String toString() => message;
}

/// "Chọn ảnh": a fridge photo from the device gallery.
abstract interface class ScanImageSource {
  /// The photo's bytes, or `null` when the user closes the picker without
  /// choosing (or the gallery is empty, as on a fresh emulator). Throws
  /// [ScanPickerUnavailable] when the gallery can't be opened at all.
  Future<Uint8List?> pickFromGallery();
}

/// Android uses the system photo picker (no storage permission needed);
/// iOS asks with `NSPhotoLibraryUsageDescription`.
class GalleryScanImageSource implements ScanImageSource {
  GalleryScanImageSource([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pickFromGallery() async {
    final XFile? file;
    try {
      // Plenty for detection, and keeps the upload small.
      file = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    } catch (e) {
      final denied = e.toString().contains('access_denied');
      throw ScanPickerUnavailable(denied
          ? 'VeganLife chưa được cấp quyền xem ảnh. Hãy bật quyền Ảnh trong Cài đặt.'
          : 'Chưa mở được thư viện ảnh trên máy này.');
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }
}

final scanImageSourceProvider =
    Provider<ScanImageSource>((ref) => GalleryScanImageSource());
