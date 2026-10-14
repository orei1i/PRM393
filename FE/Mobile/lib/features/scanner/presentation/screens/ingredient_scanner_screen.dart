// lib/features/scanner/presentation/screens/ingredient_scanner_screen.dart
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../controllers/scanner_controller.dart';
import '../widgets/bounding_box_overlay.dart';
import '../widgets/mock_fridge_preview.dart';
import '../widgets/scanned_ingredients_sheet.dart';

/// Full-screen Smart Kitchen scanner (pushed as a fullscreen dialog route).
class IngredientScannerScreen extends StatelessWidget {
  const IngredientScannerScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const IngredientScannerScreen(),
      );

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: GuestGate(
        icon: Icons.document_scanner_outlined,
        title: 'Quét tủ lạnh, ra thực đơn',
        message: 'Đăng nhập để AI nhận diện nguyên liệu trong tủ và gợi ý món chay phù hợp.',
        benefits: [
          'Nhận diện rau củ, đậu hũ, nấm… ngay trên camera',
          'Ưu tiên nguyên liệu sắp hết hạn để không lãng phí',
          'Tự loại trừ món chứa chất bạn dị ứng',
        ],
        child: _ScannerView(),
      ),
    );
  }
}

enum _CameraIssue { permissionDenied, unavailable }

class _ScannerView extends ConsumerStatefulWidget {
  const _ScannerView();

  @override
  ConsumerState<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends ConsumerState<_ScannerView> with WidgetsBindingObserver {
  static const _permissionCodes = {
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'cameraPermission',
  };

  CameraController? _camera;
  _CameraIssue? _issue;
  bool _pausedByLifecycle = false;
  bool _torchOn = false;
  bool _useMockPreview = false;
  bool _manualEntry = false;
  Uint8List? _frozenFrame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start from a clean scan each time the screen opens.
    Future.microtask(() => ref.read(scannerControllerProvider.notifier).reset());
    _initCamera();
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (camera == null) return;
      _camera = null;
      _pausedByLifecycle = true;
      camera.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_useMockPreview) return;
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
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _torchOn = false;
      });
    } on CameraException catch (e) {
      _setIssue(_permissionCodes.contains(e.code) ? _CameraIssue.permissionDenied : _CameraIssue.unavailable);
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
      if (issue == _CameraIssue.unavailable) _useMockPreview = true;
    });
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

  Future<void> _capture() async {
    final notifier = ref.read(scannerControllerProvider.notifier);
    var bytes = Uint8List(0);
    final camera = _camera;
    if (camera != null && camera.value.isInitialized && !camera.value.isTakingPicture) {
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
    HapticFeedback.mediumImpact();
    setState(() {
      _frozenFrame = bytes.isEmpty ? null : bytes;
      _manualEntry = false;
    });
    await notifier.analyze(bytes);
    if (!mounted) return;
    if (ref.read(scannerControllerProvider).status == ScanStatus.detected) {
      HapticFeedback.lightImpact();
    }
  }

  void _rescan() {
    setState(() {
      _frozenFrame = null;
      _manualEntry = false;
    });
    ref.read(scannerControllerProvider.notifier).resumeLive();
  }

  void _openManualEntry() => setState(() => _manualEntry = true);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final showTray = state.status == ScanStatus.detected || _manualEntry;

    if (_issue == _CameraIssue.permissionDenied && !_useMockPreview) {
      return _PermissionDeniedView(
        onRetry: _initCamera,
        onUseMock: () => setState(() => _useMockPreview = true),
        onManual: () => setState(() {
          _useMockPreview = true;
          _manualEntry = true;
        }),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _Viewport(
          camera: _camera,
          frozenFrame: _frozenFrame,
          useMockPreview: _useMockPreview,
          items: state.status == ScanStatus.detected ? state.items : const [],
          onTapItem: (item) {
            if (!item.confirmed) ScannedIngredientsSheet.reviewItem(context, ref, item);
          },
        ),
        if (state.status == ScanStatus.analyzing) const _AnalyzingOverlay(),
        _TopBar(
          status: state.status,
          itemCount: state.items.length,
          isMock: _useMockPreview,
          torchOn: _torchOn,
          canTorch: _camera != null,
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
                    busy: state.isBusy,
                    trayCount: state.items.length,
                    onCapture: _capture,
                    onManual: _openManualEntry,
                    onOpenTray: () => ref.read(scannerControllerProvider.notifier).showTray(),
                  ),
                ],
              ),
            ),
          ),
        if (showTray) ScannedIngredientsSheet(onRescan: _rescan),
      ],
    );
  }
}

// ---------------------------------------------------------------- viewport --

class _Viewport extends StatelessWidget {
  const _Viewport({
    required this.camera,
    required this.frozenFrame,
    required this.useMockPreview,
    required this.items,
    required this.onTapItem,
  });

  final CameraController? camera;
  final Uint8List? frozenFrame;
  final bool useMockPreview;
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

    if (useMockPreview) {
      frame = MockFridgePreview.frameSize;
      background = const MockFridgePreview();
    } else if (cam != null && cam.value.isInitialized) {
      frame = _portrait(cam.value.previewSize);
      background = frozenFrame != null
          ? Image.memory(frozenFrame!, fit: BoxFit.cover, gaplessPlayback: true)
          : CameraPreview(cam);
    } else {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('Đang mở camera…', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: frame.width, height: frame.height, child: background),
          ),
        ),
        BoundingBoxOverlay(items: items, frameSize: frame, onTapItem: onTapItem),
      ],
    );
  }
}

// ------------------------------------------------------------------ chrome --

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.itemCount,
    required this.isMock,
    required this.torchOn,
    required this.canTorch,
    required this.onClose,
    required this.onTorch,
  });

  final ScanStatus status;
  final int itemCount;
  final bool isMock;
  final bool torchOn;
  final bool canTorch;
  final VoidCallback onClose;
  final VoidCallback onTorch;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ScanStatus.idle => isMock ? 'Chế độ mô phỏng · sẵn sàng' : 'Hướng camera vào tủ lạnh',
      ScanStatus.analyzing => 'Đang nhận diện…',
      ScanStatus.detected => 'Tìm thấy $itemCount nguyên liệu',
      ScanStatus.empty => 'Không tìm thấy nguyên liệu',
      ScanStatus.error => 'Lỗi nhận diện',
    };

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
              _RoundButton(icon: Icons.close_rounded, tooltip: 'Đóng', onPressed: onClose),
              Expanded(
                child: Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x8C000000),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),
              _RoundButton(
                icon: torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
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
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed, this.active = false});

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

class _ShutterRow extends StatelessWidget {
  const _ShutterRow({
    required this.busy,
    required this.trayCount,
    required this.onCapture,
    required this.onManual,
    required this.onOpenTray,
  });

  final bool busy;
  final int trayCount;
  final VoidCallback onCapture;
  final VoidCallback onManual;
  final VoidCallback onOpenTray;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundButton(icon: Icons.keyboard_alt_outlined, tooltip: 'Nhập tay', onPressed: busy ? null : onManual),
          Semantics(
            button: true,
            label: 'Chụp và nhận diện',
            child: GestureDetector(
              onTap: busy ? null : onCapture,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: busy ? 0.5 : 1,
                child: Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
          ),
          Badge.count(
            count: trayCount,
            isLabelVisible: trayCount > 0,
            child: _RoundButton(
              icon: Icons.list_alt_rounded,
              tooltip: 'Danh sách nguyên liệu',
              onPressed: trayCount > 0 ? onOpenTray : null,
            ),
          ),
        ],
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
              Expanded(child: Text(title, style: context.textStyles.titleMedium)),
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
                  Expanded(child: Text(line, style: context.textStyles.bodyMedium)),
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

class _AnalyzingOverlayState extends State<_AnalyzingOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

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
                    boxShadow: [BoxShadow(color: aiColor.withValues(alpha: 0.6), blurRadius: 16)],
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
  const _PermissionDeniedView({required this.onRetry, required this.onUseMock, required this.onManual});

  final VoidCallback onRetry;
  final VoidCallback onUseMock;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              Icon(Icons.no_photography_outlined, size: 48, color: context.colors.primary),
              const SizedBox(height: 16),
              Text('VeganLife cần quyền camera', style: context.textStyles.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Camera chỉ dùng để nhận diện nguyên liệu trong tủ lạnh. Ảnh không được lưu nếu bạn không lưu lần quét. '
                'Hãy bật quyền Camera cho VeganLife trong Cài đặt rồi thử lại.',
                style: context.textStyles.bodyLarge?.copyWith(color: context.vl.muted),
              ),
              const Spacer(),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onManual, child: const Text('Nhập nguyên liệu bằng tay')),
              TextButton(onPressed: onUseMock, child: const Text('Dùng ảnh mô phỏng')),
            ],
          ),
        ),
      ),
    );
  }
}
