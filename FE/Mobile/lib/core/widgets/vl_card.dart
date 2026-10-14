// lib/core/widgets/vl_card.dart
import 'package:flutter/material.dart';

import '../theme/vl_colors.dart';

/// Flat, bordered card (radius 16) used across features.
class VLCard extends StatelessWidget {
  const VLCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? context.colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor ?? context.vl.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small rounded label, e.g. "Chứa đậu phộng", "Không gluten".
class VLTag extends StatelessWidget {
  const VLTag({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.borderColor,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;
  final Color? borderColor;

  factory VLTag.caution(BuildContext context, String label) => VLTag(
        label: label,
        icon: Icons.warning_amber_rounded,
        background: context.vl.cautionContainer,
        foreground: context.vl.onCautionContainer,
        borderColor: context.vl.cautionBorder,
      );

  factory VLTag.neutral(BuildContext context, String label) => VLTag(
        label: label,
        background: context.colors.surfaceContainer,
        foreground: context.colors.onSurfaceVariant,
      );

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? context.colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: context.textStyles.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Lavender "AI" marker for model-generated content.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.label = 'AI'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return VLTag(
      label: label,
      icon: Icons.auto_awesome,
      background: context.vl.aiContainer,
      foreground: context.vl.onAiContainer,
    );
  }
}
