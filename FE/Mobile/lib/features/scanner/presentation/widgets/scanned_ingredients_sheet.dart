// lib/features/scanner/presentation/widgets/scanned_ingredients_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../domain/entities/detected_ingredient.dart';
import '../controllers/scanner_controller.dart';
import 'bounding_box_overlay.dart';
import 'confirm_ingredient_sheet.dart';
import 'dashed_border.dart';

/// Draggable tray over the camera: detected ingredients (confidence + freshness),
/// quick edit, manual add and the primary CTA "Tạo thực đơn từ nguyên liệu này".
class ScannedIngredientsSheet extends ConsumerStatefulWidget {
  const ScannedIngredientsSheet({super.key, required this.onRescan});

  final VoidCallback onRescan;

  /// Opens the low-confidence confirmation and applies the decision.
  static Future<void> reviewItem(
      BuildContext context, WidgetRef ref, DetectedIngredient item) async {
    final decision = await ConfirmIngredientSheet.show(context, item);
    final notifier = ref.read(scannerControllerProvider.notifier);
    switch (decision) {
      case ConfirmAs(:final name):
        notifier.confirm(item.id, name: name);
      case RemoveIngredient():
        notifier.remove(item.id);
      case null:
        break;
    }
  }

  @override
  ConsumerState<ScannedIngredientsSheet> createState() =>
      _ScannedIngredientsSheetState();
}

class _ScannedIngredientsSheetState
    extends ConsumerState<ScannedIngredientsSheet> {
  final _addController = TextEditingController();

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _add() {
    ref.read(scannerControllerProvider.notifier).addManual(_addController.text);
    _addController.clear();
  }

  void _remove(DetectedIngredient item) {
    final removed =
        ref.read(scannerControllerProvider.notifier).remove(item.id);
    if (removed == null) return;
    final (removedItem, index) = removed;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Đã bỏ ${removedItem.name.toLowerCase()}'),
        action: SnackBarAction(
          label: 'Hoàn tác',
          onPressed: () => ref
              .read(scannerControllerProvider.notifier)
              .restore(removedItem, index),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final notifier = ref.read(scannerControllerProvider.notifier);
    final vl = context.vl;
    final cs = context.colors;
    final confirmed = state.confirmedItems.length;
    final generating = state.menuStatus == MenuStatus.generating;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.24,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.5],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 32,
                  offset: Offset(0, -8))
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                      color: cs.outline,
                      borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nguyên liệu trong tủ',
                            style: context.textStyles.titleMedium),
                        Text(
                          state.items.isEmpty
                              ? 'Chưa có nguyên liệu nào'
                              : '${state.items.length} món'
                                  '${state.pendingCount > 0 ? ' · ${state.pendingCount} cần xác nhận' : ''}',
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: vl.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: state.isBusy ? null : widget.onRescan,
                    icon: const Icon(Icons.center_focus_strong_outlined,
                        size: 18),
                    label: const Text('Quét lại'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final item in state.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _IngredientTile(
                    item: item,
                    onReview: () =>
                        ScannedIngredientsSheet.reviewItem(context, ref, item),
                    onRemove: () => _remove(item),
                    onQuantity: (q) => notifier.updateQuantity(item.id, q),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _add(),
                      decoration: InputDecoration(
                        labelText: 'Thêm nguyên liệu',
                        hintText: 'Ví dụ: nấm rơm',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Thêm',
                    onPressed: _add,
                    style:
                        IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              switch (ref.watch(userAllergiesProvider)) {
                AsyncData(:final value) when value.isNotEmpty => Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Thực đơn sẽ loại trừ: ${value.map(allergenLabel).join(', ')}',
                          style: context.textStyles.bodySmall,
                        ),
                      ),
                    ],
                  ),
                _ => const SizedBox.shrink(),
              },
              if (state.menuError != null) ...[
                const SizedBox(height: 8),
                Text(state.menuError!,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.onCautionContainer)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: generating
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        notifier.generateMenu();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: cs.tertiary,
                  foregroundColor: cs.onTertiary,
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: generating
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onTertiary),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  generating
                      ? 'Đang tạo thực đơn…'
                      : 'Tạo thực đơn từ nguyên liệu này${confirmed > 0 ? ' ($confirmed)' : ''}',
                ),
              ),
              if (state.pendingCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Nguyên liệu chưa xác nhận sẽ không được dùng.',
                  textAlign: TextAlign.center,
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted),
                ),
              ],
              const SizedBox(height: 16),
              if (generating) const _MenuSkeleton(),
              if (state.menuStatus == MenuStatus.ready) ...[
                Row(
                  children: [
                    Text('Gợi ý từ AI', style: context.textStyles.titleSmall),
                    const SizedBox(width: 8),
                    const AiBadge(),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.menu.isEmpty)
                  Text(
                    'Chưa ghép được món nào từ các nguyên liệu này. Thêm 1–2 nguyên liệu rồi thử lại nhé.',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted),
                  ),
                for (final m in state.menu)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _MenuTile(suggestion: m),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({
    required this.item,
    required this.onReview,
    required this.onRemove,
    required this.onQuantity,
  });

  final DetectedIngredient item;
  final VoidCallback onReview;
  final VoidCallback onRemove;
  final ValueChanged<double> onQuantity;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final pending = !item.confirmed;
    final qty = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : formatDecimal(item.quantity);
    final step = item.unit == 'g' || item.unit == 'ml' ? 50.0 : 1.0;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: pending
                  ? Colors.transparent
                  : FreshnessBadge.dotColor(item.freshness),
              border: pending ? Border.all(color: vl.caution, width: 2) : null,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pending ? '${item.name}?' : item.name,
                    style: context.textStyles.titleSmall),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: pending
                          ? 'Chạm để xác nhận · '
                          : (item.manual
                              ? 'Thêm thủ công'
                              : '${item.freshness.label} · '),
                      style: context.textStyles.bodySmall?.copyWith(
                        color: pending ? vl.onCautionContainer : vl.muted,
                        fontWeight: pending ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (!item.manual)
                      TextSpan(
                        text: '${(item.confidence * 100).round()}%',
                        style: AppTypography.mono(size: 11, color: vl.muted),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          if (!pending) ...[
            IconButton(
              tooltip: 'Giảm',
              onPressed: item.quantity > step
                  ? () => onQuantity(item.quantity - step)
                  : null,
              icon: const Icon(Icons.remove_rounded, size: 18),
            ),
            Semantics(
              label: 'Số lượng $qty ${item.unit}',
              child: Text('$qty ${item.unit}',
                  style: AppTypography.mono(
                      size: 13, color: context.colors.onSurface)),
            ),
            IconButton(
              tooltip: 'Tăng',
              onPressed: () => onQuantity(item.quantity + step),
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
          IconButton(
            tooltip: 'Bỏ ${item.name.toLowerCase()}',
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 18, color: vl.muted),
          ),
        ],
      ),
    );

    if (pending) {
      return DashedBorder(
        color: vl.caution,
        radius: 12,
        child: Material(
          color: vl.cautionContainer,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onReview,
              child: content),
        ),
      );
    }
    return Material(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.suggestion});

  final MenuSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return VLCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(suggestion.name,
                      style: context.textStyles.titleSmall)),
              Text('${formatInt(suggestion.calories)} kcal',
                  style: AppTypography.mono(size: 12, color: vl.muted)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Dùng: ${suggestion.usedIngredients.join(', ')} · ${suggestion.prepMinutes} phút',
            style: context.textStyles.bodySmall,
          ),
          if (suggestion.missingIngredients.isNotEmpty)
            Text(
              'Cần thêm: ${suggestion.missingIngredients.join(', ')}',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              // TODO(api): POST /meal-plans/current/meals with this suggestion.
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Đã thêm "${suggestion.name}" vào thực đơn hôm nay')),
              ),
              child: const Text('Thêm vào thực đơn'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 120, height: 16),
          const SizedBox(height: 10),
          for (var i = 0; i < 3; i++) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: context.vl.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 160, height: 12),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
