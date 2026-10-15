// lib/features/meal_planner/presentation/widgets/pantry_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../scanner/domain/vegan_check.dart';
import '../../../scanner/presentation/screens/ingredient_scanner_screen.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/pantry_controller.dart';

/// "Nguyên liệu trong tủ": the vegan foods the member has at home (saved
/// from a fridge scan or typed in), and "Tạo thực đơn từ tủ lạnh". A typed
/// food that isn't vegan is refused, with the reason and vegan swaps.
class PantrySection extends ConsumerStatefulWidget {
  const PantrySection(
      {super.key, required this.onGenerate, this.generating = false});

  /// Generates the week from the (vegan) pantry.
  final VoidCallback onGenerate;
  final bool generating;

  @override
  ConsumerState<PantrySection> createState() => _PantrySectionState();
}

class _PantrySectionState extends ConsumerState<PantrySection> {
  final _input = TextEditingController();
  bool _adding = false;

  /// Last typed food refused for not being vegan (shown under the field).
  ({String name, VeganVerdict verdict})? _refused;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Adds the typed name, or [picked] (a "Gợi ý thay thế" chip).
  Future<void> _add([String? picked]) async {
    final name = (picked ?? _input.text).trim();
    if (name.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final verdict =
          await ref.read(pantryControllerProvider.notifier).addManual(name);
      if (!mounted) return;
      setState(() =>
          _refused = verdict.isVegan ? null : (name: name, verdict: verdict));
      if (verdict.isVegan) _input.clear();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(PantryItem item) async {
    try {
      await ref.read(pantryControllerProvider.notifier).remove(item);
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá hết nguyên liệu?'),
        content: const Text(
            'Danh sách trong tủ sẽ trống. Thực đơn đã tạo không thay đổi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá hết'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(pantryControllerProvider.notifier).clear();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final async = ref.watch(pantryControllerProvider);
    final items = async.valueOrNull ?? const <PantryItem>[];
    final refused = _refused;

    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.kitchen_outlined, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Nguyên liệu trong tủ',
                    style: context.textStyles.titleMedium),
              ),
              if (items.isNotEmpty)
                TextButton(onPressed: _clear, child: const Text('Xoá hết')),
            ],
          ),
          Text(
            'Lưu từ lần quét tủ lạnh hoặc tự thêm. Chỉ lưu thực phẩm thuần chay.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 12),
          if (!async.hasValue && !async.hasError)
            const Shimmer(child: SkeletonBox(height: 32, radius: 999))
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in items)
                  InputChip(
                    // Where it came from: "Quét" (detected by a scan) or
                    // "Tự thêm" (typed in, or a vegan swap).
                    avatar: Icon(
                      switch (item.source) {
                        PantrySource.scan => Icons.document_scanner_outlined,
                        PantrySource.manual => Icons.edit_outlined,
                      },
                      size: 16,
                      color: vl.muted,
                      semanticLabel: item.source.label,
                    ),
                    label: Text(item.ingredient),
                    deleteButtonTooltipMessage: 'Bỏ ${item.ingredient}',
                    onDeleted: () => _remove(item),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    if (_refused != null) setState(() => _refused = null);
                  },
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'Thêm nguyên liệu…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Thêm vào tủ',
                onPressed: _adding ? null : _add,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (refused != null) ...[
            const SizedBox(height: 8),
            _NotVeganNotice(
              name: refused.name,
              verdict: refused.verdict,
              onPick: _adding ? null : _add,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(IngredientScannerScreen.route()),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Quét tủ lạnh'),
              ),
              FilledButton.tonalIcon(
                onPressed: items.isEmpty || widget.generating
                    ? null
                    : widget.onGenerate,
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

/// "Trứng gà không thuần chay nên không thêm vào tủ." with the reason and
/// the vegan swaps; tapping a swap adds it instead.
class _NotVeganNotice extends StatelessWidget {
  const _NotVeganNotice(
      {required this.name, required this.verdict, required this.onPick});

  final String name;
  final VeganVerdict verdict;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block_rounded, size: 18, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$name không thuần chay nên không thêm vào tủ.',
                    style: context.textStyles.bodyMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (verdict.nonVeganReason case final reason?)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(reason,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: cs.onErrorContainer)),
              ),
            if (verdict.veganAlternatives.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Gợi ý thay thế:',
                        style: context.textStyles.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w700)),
                    for (final alternative in verdict.veganAlternatives)
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: Text(alternative),
                        tooltip: 'Thêm ${alternative.toLowerCase()} vào tủ',
                        backgroundColor: cs.surface,
                        onPressed:
                            onPick == null ? null : () => onPick!(alternative),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
