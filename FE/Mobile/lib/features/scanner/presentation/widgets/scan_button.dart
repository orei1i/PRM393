// lib/features/scanner/presentation/widgets/scan_button.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/scan_mode.dart';
import '../controllers/scan_mode_controller.dart';

IconData scanModeIcon(ScanMode mode) => switch (mode) {
      ScanMode.camera => Icons.photo_camera_rounded,
      ScanMode.gallery => Icons.photo_library_rounded,
      ScanMode.manual => Icons.keyboard_alt_rounded,
    };

/// The big round "Quét" button in the middle of the bottom bar. A tap opens
/// the remembered scan mode (Chụp hình at first); a long press offers all
/// three and remembers the pick. The icon shows what a tap will do.
class ScanButton extends ConsumerWidget {
  const ScanButton({super.key, required this.onScan, this.size = 64});

  /// Opens the scanner in the given mode.
  final ValueChanged<ScanMode> onScan;
  final double size;

  Future<void> _chooseMode(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    final current = ref.read(scanModeProvider);
    final picked = await ScanModeSheet.show(context, current);
    if (picked == null) return;
    ref.read(scanModeProvider.notifier).remember(picked);
    onScan(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(scanModeProvider);
    final cs = context.colors;
    return Semantics(
      button: true,
      label: 'Quét tủ lạnh, ${mode.label.toLowerCase()}',
      hint: 'Chạm hai lần để quét. Giữ để chọn cách quét khác.',
      onLongPressHint: 'Chọn cách quét',
      excludeSemantics: true,
      child: Material(
        color: cs.primary,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: CircleBorder(
          // Separates the button from the bar it rises out of.
          side: BorderSide(
              color: NavigationBarTheme.of(context).backgroundColor ??
                  cs.surfaceContainer,
              width: 4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onScan(mode),
          onLongPress: () => _chooseMode(context, ref),
          child: SizedBox.square(
            dimension: size,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(scanModeIcon(mode),
                  key: ValueKey(mode), size: size * 0.44, color: cs.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Long-press menu: Chụp hình / Chọn ảnh / Nhập tay. Pops the picked mode.
class ScanModeSheet extends StatelessWidget {
  const ScanModeSheet({super.key, required this.current});

  final ScanMode current;

  static Future<ScanMode?> show(BuildContext context, ScanMode current) =>
      showModalBottomSheet<ScanMode>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ScanModeSheet(current: current),
      );

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final vl = context.vl;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quét tủ lạnh bằng cách nào?',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Cách bạn chọn sẽ được nhớ cho lần chạm nút Quét sau.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
            ),
            const SizedBox(height: 12),
            for (final mode in ScanMode.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  selected: mode == current,
                  child: Material(
                    color: mode == current
                        ? cs.secondaryContainer
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: mode == current ? cs.primary : vl.border,
                          width: mode == current ? 2 : 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              child: Icon(scanModeIcon(mode), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(mode.label,
                                      style: context.textStyles.titleSmall),
                                  Text(mode.description,
                                      style: context.textStyles.bodySmall
                                          ?.copyWith(color: vl.muted)),
                                ],
                              ),
                            ),
                            if (mode == current) ...[
                              const SizedBox(width: 8),
                              Text('Đang dùng',
                                  style: context.textStyles.labelMedium
                                      ?.copyWith(color: cs.primary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
