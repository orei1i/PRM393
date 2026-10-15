// lib/features/chef/presentation/widgets/chef_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../domain/entities/chef.dart';

class ChefCard extends StatelessWidget {
  const ChefCard({super.key, required this.chef, required this.onTap});

  final Chef chef;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: chef.name, size: 56, verified: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chef.name,
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(chef.headline,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted)),
                const SizedBox(height: 6),
                RatingLine(chef: chef),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in chef.specialties)
                      StatusPill(
                        label: s,
                        background: context.colors.surfaceContainer,
                        foreground: context.colors.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Từ ${formatVnd(chef.startingPriceVnd)}',
                        style: context.textStyles.titleSmall?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.vl.muted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RatingLine extends StatelessWidget {
  const RatingLine({super.key, required this.chef});

  final Chef chef;

  @override
  Widget build(BuildContext context) {
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 2),
        Text(formatDecimal(chef.rating),
            style: context.textStyles.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(' (${formatInt(chef.reviewCount)})', style: muted),
        Flexible(
          child: Text(
            ' · ${chef.yearsExperience} năm · ${chef.city}',
            style: muted,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
