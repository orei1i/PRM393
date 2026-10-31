// lib/features/recipe/presentation/widgets/recipe_ingredient_row.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../domain/recipe_customization.dart';

enum RecipeTagTone { neutral, caution, success }

/// A small rounded label that wraps on narrow screens ("Thành phần chính",
/// "Chứa đậu nành — bạn đã khai báo dị ứng").
class RecipeTag extends StatelessWidget {
  const RecipeTag(this.label,
      {super.key, this.icon, this.tone = RecipeTagTone.neutral});

  final String label;
  final IconData? icon;
  final RecipeTagTone tone;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (bg, fg, border) = switch (tone) {
      RecipeTagTone.neutral => (
          context.colors.surfaceContainer,
          context.colors.onSurfaceVariant,
          null
        ),
      RecipeTagTone.caution => (
          vl.cautionContainer,
          vl.onCautionContainer,
          vl.cautionBorder
        ),
      RecipeTagTone.success => (
          vl.successContainer,
          vl.onSuccessContainer,
          null
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text.rich(
        TextSpan(children: [
          if (icon != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 13, color: fg),
            ),
            const TextSpan(text: ' '),
          ],
          TextSpan(text: label),
        ]),
        style: context.textStyles.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}

/// One "Nguyên liệu" row as cooked: name, scaled amount, tags and the
/// controls the row allows (lock for a "Thành phần chính", "Đổi" when it
/// has substitutes, ✕ when optional; "Hoàn tác" / "Thêm lại" once changed).
/// Rows found in the nutrition DB open the ingredient ([onOpen]).
class RecipeIngredientRow extends StatelessWidget {
  const RecipeIngredientRow({
    super.key,
    required this.row,
    this.conflicts = const [],
    this.onOpen,
    this.onSwap,
    this.onUndoSwap,
    this.onRemove,
    this.onRestore,
    this.onLock,
  });

  final CustomizedRow row;

  /// The member's allergy keys this row (as cooked) conflicts with.
  final List<String> conflicts;
  final VoidCallback? onOpen;
  final VoidCallback? onSwap;
  final VoidCallback? onUndoSwap;
  final VoidCallback? onRemove;
  final VoidCallback? onRestore;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final original = row.original;
    final removed = row.removed;
    final compact = TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final amount = removed ? 'Đã bỏ' : row.amount;

    final tags = <Widget>[
      if (original.isSignature)
        const RecipeTag('Thành phần chính', icon: Icons.star_rounded),
      if (original.isOptional && !removed) const RecipeTag('Không bắt buộc'),
      if (row.isSwapped) RecipeTag('Thay cho ${original.name}'),
      if (!removed)
        for (final a in conflicts)
          RecipeTag(
            'Chứa ${allergenLabel(a).toLowerCase()} — bạn đã khai báo dị ứng',
            icon: Icons.warning_amber_rounded,
            tone: RecipeTagTone.caution,
          ),
      if (!removed && conflicts.isNotEmpty && original.substitutes.isNotEmpty)
        const RecipeTag('Có thể đổi', tone: RecipeTagTone.success),
    ];
    final actions = <Widget>[
      if (original.isSignature && !removed)
        IconButton(
          tooltip: 'Thành phần chính — không bỏ được',
          visualDensity: VisualDensity.compact,
          onPressed: onLock,
          icon: Icon(Icons.lock_outline_rounded, size: 20, color: vl.muted),
        ),
      if (removed)
        TextButton(
            style: compact, onPressed: onRestore, child: const Text('Thêm lại'))
      else if (row.isSwapped)
        TextButton(
            style: compact,
            onPressed: onUndoSwap,
            child: const Text('Hoàn tác'))
      else if (original.substitutes.isNotEmpty)
        TextButton(style: compact, onPressed: onSwap, child: const Text('Đổi')),
      if (original.isOptional && !original.isSignature && !removed)
        IconButton(
          tooltip: 'Bỏ ${original.name}',
          visualDensity: VisualDensity.compact,
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
    ];

    final content = Padding(
      padding: EdgeInsets.fromLTRB(14, 10, onOpen == null ? 14 : 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  row.name,
                  style: context.textStyles.bodyLarge?.copyWith(
                    decoration: removed ? TextDecoration.lineThrough : null,
                    color: removed ? vl.muted : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Text(
                  amount,
                  textAlign: TextAlign.end,
                  style: AppTypography.mono(
                      size: 14,
                      color: removed ? vl.muted : context.colors.onSurface),
                ),
              ),
              if (onOpen != null)
                Icon(Icons.chevron_right_rounded, color: vl.muted),
            ],
          ),
          if (tags.isNotEmpty || actions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [...tags, ...actions],
            ),
          ],
        ],
      ),
    );
    if (onOpen == null) return content;
    return Semantics(
      button: true,
      hint: 'Xem dinh dưỡng',
      child: InkWell(onTap: onOpen, child: content),
    );
  }
}
