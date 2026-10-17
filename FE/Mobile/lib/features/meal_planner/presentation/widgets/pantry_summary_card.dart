// lib/features/meal_planner/presentation/widgets/pantry_summary_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../ingredient/presentation/screens/pantry_screen.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/pantry_controller.dart';

/// Compact "Nguyên liệu trong tủ" on Thực đơn: how many foods are in the
/// fridge and which, "Xem tủ lạnh ›" (the full list with nutrition) and
/// "Tạo thực đơn từ tủ lạnh".
class PantrySummaryCard extends ConsumerWidget {
  const PantrySummaryCard(
      {super.key, required this.onGenerate, this.generating = false});

  /// Generates the week from the (vegan) pantry.
  final VoidCallback onGenerate;
  final bool generating;

  /// Names shown before "và N nguyên liệu khác".
  static const maxNames = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final async = ref.watch(pantryControllerProvider);
    final items = async.valueOrNull ?? const <PantryItem>[];
    void open() => Navigator.of(context).push(PantryScreen.route());

    final names = items.take(maxNames).map((i) => i.ingredient).join(', ');
    final more = items.length - maxNames;

    return VLCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.kitchen_outlined, color: context.colors.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text('Nguyên liệu trong tủ',
                    style: context.textStyles.titleMedium),
              ),
              if (async.hasValue) ...[
                Text(' · ',
                    style: context.textStyles.titleMedium
                        ?.copyWith(color: vl.muted)),
                Text('${items.length} nguyên liệu',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: vl.muted)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (!async.hasValue && !async.hasError)
            const Shimmer(child: SkeletonBox(height: 16, width: 220))
          else if (async.hasError && !async.hasValue)
            Row(
              children: [
                Expanded(
                  child: Text('Chưa tải được danh sách trong tủ.',
                      style: context.textStyles.bodyMedium),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(pantryControllerProvider),
                  child: const Text('Thử lại'),
                ),
              ],
            )
          else if (items.isEmpty)
            Text(
              'Tủ lạnh trống. Quét tủ lạnh hoặc thêm nguyên liệu để AI gợi ý món.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
            )
          else
            Text(
              more > 0 ? '$names và $more nguyên liệu khác' : names,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.bodyMedium,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: open,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Xem tủ lạnh'),
              ),
              FilledButton.tonalIcon(
                onPressed: items.isEmpty || generating ? null : onGenerate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Tạo thực đơn từ tủ lạnh'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
