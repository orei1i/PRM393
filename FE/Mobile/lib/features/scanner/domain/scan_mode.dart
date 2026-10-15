// lib/features/scanner/domain/scan_mode.dart

/// How the centre "Quét" button starts a fridge scan. A plain tap opens the
/// last mode picked from the long-press menu (Chụp hình until then).
enum ScanMode {
  camera('camera', 'Chụp hình', 'Chụp tủ lạnh bằng camera'),
  gallery('gallery', 'Chọn ảnh', 'Nhận diện từ một ảnh có sẵn trong máy'),
  manual('manual', 'Nhập tay', 'Gõ tên các nguyên liệu bạn đang có');

  const ScanMode(this.storageValue, this.label, this.description);

  /// Value kept in SharedPreferences (`vl.scan_mode`).
  final String storageValue;
  final String label;
  final String description;

  static ScanMode fromStorage(String? value) =>
      values.firstWhere((m) => m.storageValue == value,
          orElse: () => ScanMode.camera);
}

/// What the scanner asks the screen below to do when it closes.
enum ScannerExit {
  /// "Xem trong Thực đơn" / after "Tạo thực đơn từ tủ lạnh": show the
  /// Thực đơn tab.
  openPlanner,
}
