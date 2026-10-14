// lib/features/scanner/presentation/widgets/confirm_ingredient_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/detected_ingredient.dart';

sealed class IngredientDecision {
  const IngredientDecision();
}

class ConfirmAs extends IngredientDecision {
  const ConfirmAs(this.name);
  final String name;
}

class RemoveIngredient extends IngredientDecision {
  const RemoveIngredient();
}

/// "Đây có phải rau chân vịt?" — shown for detections under 70 % confidence.
class ConfirmIngredientSheet extends StatefulWidget {
  const ConfirmIngredientSheet({super.key, required this.item});

  final DetectedIngredient item;

  static Future<IngredientDecision?> show(BuildContext context, DetectedIngredient item) {
    return showModalBottomSheet<IngredientDecision>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ConfirmIngredientSheet(item: item),
    );
  }

  @override
  State<ConfirmIngredientSheet> createState() => _ConfirmIngredientSheetState();
}

class _ConfirmIngredientSheetState extends State<ConfirmIngredientSheet> {
  late String? _selected = widget.item.name;
  final _otherController = TextEditingController();
  bool _other = false;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? get _resolvedName => _other ? _otherController.text.trim() : _selected;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final vl = context.vl;
    final options = <(String, double)>[
      (item.name, item.confidence),
      for (final a in item.alternatives) (a.name, a.confidence),
    ];
    final canConfirm = (_resolvedName ?? '').isNotEmpty;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Đây có phải ${item.name.toLowerCase()}?', style: context.textStyles.titleLarge),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
              children: [
                const TextSpan(text: 'Mình chỉ chắc '),
                TextSpan(
                  text: '${(item.confidence * 100).round()}%',
                  style: AppTypography.mono(size: 14, color: context.colors.onSurface),
                ),
                const TextSpan(text: '. Nhiều nguyên liệu trông khá giống nhau nên mình hỏi lại cho chắc.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final (name, confidence) in options)
            _OptionTile(
              label: name,
              trailing: '${(confidence * 100).round()}%',
              selected: !_other && _selected == name,
              onTap: () => setState(() {
                _other = false;
                _selected = name;
              }),
            ),
          _OptionTile(
            label: 'Loại khác…',
            icon: Icons.search_rounded,
            selected: _other,
            onTap: () => setState(() => _other = true),
          ),
          if (_other) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _otherController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Tên nguyên liệu',
                hintText: 'Ví dụ: cải bó xôi',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(const RemoveIngredient()),
                child: const Text('Bỏ món này'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: canConfirm ? () => Navigator.of(context).pop(ConfirmAs(_resolvedName!)) : null,
                  child: Text(canConfirm ? 'Xác nhận ${_resolvedName!.toLowerCase()}' : 'Xác nhận'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap, this.trailing, this.icon});

  final String label;
  final String? trailing;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? cs.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? cs.primary : context.vl.border, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      icon ?? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      color: selected ? cs.primary : context.vl.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: context.textStyles.titleSmall)),
                    if (trailing != null)
                      Text(trailing!, style: AppTypography.mono(size: 12, color: context.vl.muted)),
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
