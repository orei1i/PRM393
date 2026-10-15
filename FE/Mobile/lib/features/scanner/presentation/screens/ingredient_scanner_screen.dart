// lib/features/scanner/presentation/screens/ingredient_scanner_screen.dart
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../data/scan_image_source.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../../domain/scan_mode.dart';
import '../controllers/scan_mode_controller.dart';
import '../controllers/scanner_controller.dart';
import '../widgets/bounding_box_overlay.dart';
import '../widgets/mock_fridge_preview.dart';
import '../widgets/scanned_ingredients_sheet.dart';

/// Full-screen Smart Kitchen scanner (pushed as a fullscreen dialog route).
/// [mode] is how it starts: the live camera ("Chụp hình"), a photo from the
/// gallery ("Chọn ảnh") or the tray with manual entry ("Nhập tay"). Closes
/// with [ScannerExit.openPlanner] when the member asks to see the Thực đơn
/// tab.
class IngredientScannerScreen extends StatelessWidget {
  const IngredientScannerScreen({super.key, this.mode = ScanMode.camera});

  final ScanMode mode;

  static Route<ScannerExit> route({ScanMode mode = ScanMode.camera}) =>
      MaterialPageRoute<ScannerExit>(
        fullscreenDialog: true,
        builder: (_) => IngredientScannerScreen(mode: mode),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GuestGate(
        icon: Icons.document_scanner_outlined,
        title: 'Quét tủ lạnh, ra thực đơn',
        message:
            'Đăng nhập để AI nhận diện thực phẩm trong tủ, cho biết món nào thuần chay và gợi ý món chay phù hợp.',
        benefits: const [
          'Nhận diện rau củ, đậu hũ, nấm… ngay trên camera',
          'Biết ngay thực phẩm nào thuần chay, kèm gợi ý thay thế',
          'Tự loại trừ món chứa chất bạn dị ứng',
        ],
        showClose: true,
        child: _ScannerView(mode: mode),
      ),
    );
  }
}

enum _CameraIssue { permissionDenied, unavailable }

/// What fills the screen behind the tray.
enum _Feed {
  /// Live camera (or the camera starting / its permission screen).
  camera,

  /// A photo picked from the gallery.
  photo,

  /// The bundled sample fridge (emulators, no camera, no gallery photo).
  sample,

  /// Nothing yet: waiting for the gallery, or typing ingredients in.
  none,
}

/// "Không có ảnh" fallbacks.
enum _Fallback { sample, camera, manual }

class _ScannerView extends ConsumerStatefulWidget {
  const _ScannerView({required this.mode});

  final ScanMode mode;

  @override
  ConsumerState<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<_ScannerView>
    with WidgetsBindingObserver {
  static const _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'cameraPermission',
  };

  CameraController? _camera;
  _CameraIssue? _issue;
  late _Feed _feed;
  bool _pausedByLifecycle = false;
  bool _torchOn = false;
  bool _manualEntry = false;
  bool _picking = false;
  Uint8List? _frozenFrame;
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start from a clean scan each time the screen opens.
    Future.microtask(
        () => ref.read(scannerControllerProvider.notifier).reset());
    switch (widget.mode) {
      case ScanMode.camera:
        _feed = _Feed.camera;
        _initCamera();
      case ScanMode.gallery:
        _feed = _Feed.none;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _pickPhoto(initial: true));
      case ScanMode.manual:
        // No camera (and no permission prompt) just to type names in.
        _feed = _Feed.none;
        _manualEntry = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (camera == null) return;
      _camera = null;
      _pausedByLifecycle = true;
      camera.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      if (_feed == _Feed.camera) _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_feed != _Feed.camera || _camera != null) return;
    if (_issue != null) setState(() => _issue = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setIssue(_CameraIssue.unavailable);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted || _feed != _Feed.camera) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _torchOn = false;
      });
    } on CameraException catch (e) {
      _setIssue(_permissionCodes.contains(e.code)
          ? _CameraIssue.permissionDenied
          : _CameraIssue.unavailable);
    } catch (_) {
      // No camera plugin on this platform (desktop/web) or emulator without camera.
      _setIssue(_CameraIssue.unavailable);
    }
  }

  void _setIssue(_CameraIssue issue) {
    if (!mounted) return;
    setState(() {
      _issue = issue;
      // Fall back to the simulated fridge automatically when there is no camera.
      if (issue == _CameraIssue.unavailable && _feed == _Feed.camera) {
        _feed = _Feed.sample;
      }
    });
  }

  /// A way of scanning picked anywhere in the scanner (the "Chưa có ảnh nào
  /// được chọn" sheet, the shutter row, "Nhập tay" cards, the camera
  /// permission screen) becomes what the "Quét" button opens next time, like
  /// a pick from its long-press menu.
  void _remember(ScanMode mode) =>
      ref.read(scanModeProvider.notifier).remember(mode);

  /// Frees the camera while a gallery photo is on screen.
  void _releaseCamera() {
    final camera = _camera;
    _camera = null;
    _torchOn = false;
    camera?.dispose();
  }

  void _startCamera() {
    setState(() {
      _feed = _Feed.camera;
      _photo = null;
      _frozenFrame = null;
    });
    _initCamera();
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torchOn ? FlashMode.off : FlashMode.torch);
      setState(() => _torchOn = !_torchOn);
    } on CameraException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thiết bị không hỗ trợ đèn pin.')),
      );
    }
  }

  Future<void> _analyze(Uint8List bytes) async {
    HapticFeedback.mediumImpact();
    await ref.read(scannerControllerProvider.notifier).analyze(bytes);
    if (!mounted) return;
    if (ref.read(scannerControllerProvider).status == ScanStatus.detected) {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _capture() async {
    if (_feed == _Feed.photo && _photo != null) return _analyze(_photo!);
    var bytes = Uint8List(0);
    final camera = _camera;
    if (camera != null &&
        camera.value.isInitialized &&
        !camera.value.isTakingPicture) {
      try {
        final file = await camera.takePicture();
        bytes = await file.readAsBytes();
      } on CameraException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa chụp được ảnh. Thử lại nhé.')),
        );
        return;
      }
    }
    setState(() {
      _frozenFrame = bytes.isEmpty ? null : bytes;
      _manualEntry = false;
    });
    await _analyze(bytes);
  }

  /// "Chọn ảnh". With nothing picked on the first try (closed picker, empty
  /// emulator gallery) or a gallery that can't open, offers the bundled
  /// sample fridge, the camera or manual entry instead of a blank screen.
  Future<void> _pickPhoto({bool initial = false}) async {
    if (_picking) return;
    setState(() => _picking = true);
    Uint8List? bytes;
    String? problem;
    try {
      bytes = await ref.read(scanImageSourceProvider).pickFromGallery();
    } on ScanPickerUnavailable catch (e) {
      problem = e.message;
    } catch (_) {
      problem = const ScanPickerUnavailable().message;
    }
    if (!mounted) return;
    setState(() => _picking = false);

    if (bytes != null) {
      final photo = bytes;
      _remember(ScanMode.gallery);
      _releaseCamera();
      setState(() {
        _feed = _Feed.photo;
        _photo = photo;
        _frozenFrame = null;
        _manualEntry = false;
      });
      await _analyze(photo);
      return;
    }
    // Closed the picker from the live view: just stay there.
    if (!initial && problem == null) return;

    final choice = await _NoPhotoSheet.show(context, problem: problem);
    if (!mounted) return;
    switch (choice) {
      case _Fallback.sample:
        _releaseCamera();
        setState(() {
          _feed = _Feed.sample;
          _photo = null;
          _manualEntry = false;
        });
        await _analyze(Uint8List(0));
      case _Fallback.camera:
        _remember(ScanMode.camera);
        _startCamera();
      case _Fallback.manual:
        _remember(ScanMode.manual);
        setState(() => _manualEntry = true);
      case null:
        if (_feed == _Feed.none && !_manualEntry) _startCamera();
    }
  }

  /// Back to the live camera (or the sample fridge); detected items stay in
  /// the tray.
  void _rescan() {
    setState(() {
      _frozenFrame = null;
      _manualEntry = false;
    });
    if (_feed == _Feed.photo || _feed == _Feed.none) _startCamera();
    ref.read(scannerControllerProvider.notifier).resumeLive();
  }

  void _openManualEntry() {
    _remember(ScanMode.manual);
    setState(() => _manualEntry = true);
  }

  String _statusLabel(ScannerState state) => switch (state.status) {
        ScanStatus.analyzing => 'Đang nhận diện…',
        ScanStatus.detected => 'Tìm thấy ${state.items.length} thực phẩm',
        ScanStatus.empty => 'Không tìm thấy nguyên liệu',
        ScanStatus.error => 'Lỗi nhận diện',
        ScanStatus.idle => switch (_feed) {
            _Feed.camera => 'Hướng camera vào tủ lạnh',
            _Feed.sample => 'Chế độ mô phỏng · sẵn sàng',
            _Feed.photo => 'Ảnh từ thư viện',
            _Feed.none => _manualEntry
                ? 'Nhập nguyên liệu bằng tay'
                : 'Đang mở thư viện ảnh…',
          },
      };

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final showTray = state.status == ScanStatus.detected || _manualEntry;

    if (_feed == _Feed.camera && _issue == _CameraIssue.permissionDenied) {
      return _PermissionDeniedView(
        onRetry: _initCamera,
        onUseMock: () => setState(() => _feed = _Feed.sample),
        onGallery: () => _pickPhoto(initial: true),
        onManual: () {
          _remember(ScanMode.manual);
          setState(() {
            _feed = _Feed.sample;
            _manualEntry = true;
          });
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _Viewport(
          feed: _feed,
          camera: _camera,
          frozenFrame: _frozenFrame,
          photo: _photo,
          manual: _manualEntry,
          items: state.status == ScanStatus.detected ? state.items : const [],
          onTapItem: (item) {
            if (!item.confirmed) {
              ScannedIngredientsSheet.reviewItem(context, ref, item);
            }
          },
        ),
        if (state.status == ScanStatus.analyzing) const _AnalyzingOverlay(),
        _TopBar(
          label: _statusLabel(state),
          torchOn: _torchOn,
          canTorch: _camera != null && _feed == _Feed.camera,
          onClose: () => Navigator.of(context).maybePop(),
          onTorch: _toggleTorch,
        ),
        if (!showTray)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.status == ScanStatus.empty)
                    _InfoCard(
                      icon: Icons.search_off_rounded,
                      title: 'Chưa thấy nguyên liệu nào',
                      lines: const [
                        'Mở ngăn rau củ, quét từng ngăn một',
                        'Giữ máy cách 30–50 cm, bật đèn pin nếu tối',
                        'Xoay mặt nhãn của đồ đóng gói về phía camera',
                      ],
                      actionLabel: 'Nhập tay',
                      onAction: _openManualEntry,
                    ),
                  if (state.status == ScanStatus.error)
                    _InfoCard(
                      icon: Icons.cloud_off_rounded,
                      title: 'Chưa nhận diện được',
                      lines: [state.errorMessage ?? 'Vui lòng thử lại.'],
                      actionLabel: 'Nhập tay',
                      onAction: _openManualEntry,
                    ),
                  _ShutterRow(
                    busy: state.isBusy || _picking,
                    canCapture: _feed != _Feed.none,
                    trayCount: state.items.length,
                    onCapture: _capture,
                    onManual: _openManualEntry,
                    onGallery: _pickPhoto,
                    onOpenTray: () =>
                        ref.read(scannerControllerProvider.notifier).showTray(),
                  ),
                ],
              ),
            ),
          ),
        if (showTray)
          ScannedIngredientsSheet(
            onRescan: _rescan,
            // Fully dragged up, the tray stops under the top bar so "Đóng"
            // stays tappable.
            reservedTop: MediaQuery.paddingOf(context).top + _TopBar.height + 8,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- viewport --

class _Viewport extends StatelessWidget {
  const _Viewport({
    required this.feed,
    required this.camera,
    required this.frozenFrame,
    required this.photo,
    required this.manual,
    required this.items,
    required this.onTapItem,
  });

  final _Feed feed;
  final CameraController? camera;
  final Uint8List? frozenFrame;
  final Uint8List? photo;
  final bool manual;
  final List<DetectedIngredient> items;
  final ValueChanged<DetectedIngredient> onTapItem;

  static Size _portrait(Size? preview) {
    final p = preview ?? const Size(1280, 720);
    return Size(math.min(p.width, p.height), math.max(p.width, p.height));
  }

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    final Size frame;
    final Widget background;

    switch (feed) {
      case _Feed.sample:
        frame = MockFridgePreview.frameSize;
        background = const MockFridgePreview();
      case _Feed.photo when photo != null:
        // Boxes are normalised against the photo shown edge to edge.
        frame = MockFridgePreview.frameSize;
        background = Image.memory(
          photo!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFF1B2722)),
        );
      case _Feed.camera when cam != null && cam.value.isInitialized:
        frame = _portrait(cam.value.previewSize);
        background = frozenFrame != null
            ? Image.memory(frozenFrame!,
                fit: BoxFit.cover, gaplessPlayback: true)
            : CameraPreview(cam);
      case _Feed.camera:
        return const ColoredBox(
          color: Colors.black,
          child: Center(
            child: Text('Đang mở camera…',
                style: TextStyle(color: Colors.white70)),
          ),
        );
      case _Feed.photo:
      case _Feed.none:
        return _EmptyViewport(manual: manual);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
                width: frame.width, height: frame.height, child: background),
          ),
        ),
        BoundingBoxOverlay(
            items: items, frameSize: frame, onTapItem: onTapItem),
      ],
    );
  }
}

/// Behind the tray in "Nhập tay", or while the gallery is open.
class _EmptyViewport extends StatelessWidget {
  const _EmptyViewport({required this.manual});

  final bool manual;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF121A17),
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    manual
                        ? Icons.keyboard_alt_outlined
                        : Icons.photo_library_outlined,
                    size: 44,
                    color: Colors.white54),
                const SizedBox(height: 12),
                Text(
                  manual
                      ? 'Gõ tên nguyên liệu bạn có ở khay bên dưới'
                      : 'Chọn một ảnh tủ lạnh trong thư viện',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ chrome --

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.torchOn,
    required this.canTorch,
    required this.onClose,
    required this.onTorch,
  });

  final String label;
  final bool torchOn;
  final bool canTorch;
  final VoidCallback onClose;
  final VoidCallback onTorch;

  /// Below the status bar: 8 top padding + 48 round buttons.
  static const double height = 56;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _RoundButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Đóng',
                  onPressed: onClose),
              Expanded(
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x8C000000),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
              _RoundButton(
                icon:
                    torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                tooltip: torchOn ? 'Tắt đèn pin' : 'Bật đèn pin',
                onPressed: canTorch ? onTorch : null,
                active: torchOn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon,
      required this.tooltip,
      required this.onPressed,
      this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: active ? Colors.white : const Color(0x80000000),
        foregroundColor: active ? Colors.black : Colors.white,
        disabledBackgroundColor: const Color(0x40000000),
        disabledForegroundColor: Colors.white38,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(icon),
    );
  }
}

/// Nhập tay · Chọn ảnh | shutter | tray. The shutter stays centred.
class _ShutterRow extends StatelessWidget {
  const _ShutterRow({
    required this.busy,
    required this.canCapture,
    required this.trayCount,
    required this.onCapture,
    required this.onManual,
    required this.onGallery,
    required this.onOpenTray,
  });

  final bool busy;
  final bool canCapture;
  final int trayCount;
  final VoidCallback onCapture;
  final VoidCallback onManual;
  final VoidCallback onGallery;
  final VoidCallback onOpenTray;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && canCapture;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _RoundButton(
                    icon: Icons.keyboard_alt_outlined,
                    tooltip: 'Nhập tay',
                    onPressed: busy ? null : onManual),
                _RoundButton(
                    icon: Icons.photo_library_outlined,
                    tooltip: 'Chọn ảnh',
                    onPressed: busy ? null : onGallery),
              ],
            ),
          ),
          Semantics(
            button: true,
            enabled: enabled,
            label: 'Chụp và nhận diện',
            child: GestureDetector(
              onTap: enabled ? onCapture : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: enabled ? 1 : 0.5,
                child: Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Badge.count(
                count: trayCount,
                isLabelVisible: trayCount > 0,
                child: _RoundButton(
                  icon: Icons.list_alt_rounded,
                  tooltip: 'Danh sách nguyên liệu',
                  onPressed: trayCount > 0 ? onOpenTray : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// No gallery photo: offer the bundled sample fridge (emulators usually have
/// an empty gallery), the camera, or typing ingredients in.
class _NoPhotoSheet extends StatelessWidget {
  const _NoPhotoSheet({this.problem});

  final String? problem;

  static Future<_Fallback?> show(BuildContext context, {String? problem}) =>
      showModalBottomSheet<_Fallback>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _NoPhotoSheet(problem: problem),
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chưa có ảnh nào được chọn',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 6),
            Text(
              problem ??
                  'Máy ảo thường chưa có ảnh trong thư viện. Bạn có thể thử với ảnh tủ lạnh mẫu.',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.muted),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.kitchen_outlined),
              title: const Text('Dùng ảnh tủ lạnh mẫu'),
              subtitle: const Text(
                  'Bông cải, đậu hũ, cà chua, trứng, sữa, cà rốt, rau'),
              onTap: () => Navigator.of(context).pop(_Fallback.sample),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp bằng camera'),
              onTap: () => Navigator.of(context).pop(_Fallback.camera),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.keyboard_alt_outlined),
              title: const Text('Nhập tay'),
              onTap: () => Navigator.of(context).pop(_Fallback.manual),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.lines,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title, style: context.textStyles.titleMedium)),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: context.textStyles.bodyMedium),
                  Expanded(
                      child: Text(line, style: context.textStyles.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sweeping scan line while the vision model works (no blank spinner).
class _AnalyzingOverlay extends StatefulWidget {
  const _AnalyzingOverlay();

  @override
  State<_AnalyzingOverlay> createState() => _AnalyzingOverlayState();
}

class _AnalyzingOverlayState extends State<_AnalyzingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiColor = context.vl.ai;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x33000000)),
          if (!reduceMotion)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Align(
                alignment: Alignment(0, -0.7 + 1.2 * _controller.value),
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: aiColor,
                    boxShadow: [
                      BoxShadow(
                          color: aiColor.withValues(alpha: 0.6), blurRadius: 16)
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.onRetry,
    required this.onUseMock,
    required this.onGallery,
    required this.onManual,
  });

  final VoidCallback onRetry;
  final VoidCallback onUseMock;
  final VoidCallback onGallery;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.no_photography_outlined,
                        size: 48, color: context.colors.primary),
                    const SizedBox(height: 16),
                    Text('VeganLife cần quyền camera',
                        style: context.textStyles.headlineSmall),
                    const SizedBox(height: 8),
                    Text(
                      'Camera chỉ dùng để nhận diện nguyên liệu trong tủ lạnh. Ảnh không được lưu nếu bạn không lưu lần quét. '
                      'Hãy bật quyền Camera cho VeganLife trong Cài đặt rồi thử lại.',
                      style: context.textStyles.bodyLarge
                          ?.copyWith(color: context.vl.muted),
                    ),
                    const Spacer(),
                    FilledButton(
                        onPressed: onRetry, child: const Text('Thử lại')),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: onGallery,
                        child: const Text('Chọn ảnh từ thư viện')),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: onManual,
                        child: const Text('Nhập nguyên liệu bằng tay')),
                    TextButton(
                        onPressed: onUseMock,
                        child: const Text('Dùng ảnh mô phỏng')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
