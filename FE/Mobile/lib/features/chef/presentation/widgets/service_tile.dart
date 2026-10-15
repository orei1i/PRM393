// lib/features/chef/presentation/widgets/service_tile.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../domain/entities/chef.dart';

/// A chef's service: title, type chip, price, duration (consult) or access
/// length (course / VIP menu), plus an optional action button.
class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.service,
    this.onTap,
    this.selected = false,
    this.action,
  });

  final ChefService service;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final days = service.type.accessDays;
    return VLCard(
      onTap: onTap,
      borderColor: selected ? context.colors.primary : null,
      color: selected ? context.colors.secondaryContainer : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(service.title,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Text(
                formatVnd(service.price),
                style: context.textStyles.titleSmall?.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (service.description.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(service.description,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              serviceTypeTag(context, service.type),
              if (service.durationMinutes != null)
                VLTag.neutral(context, '${service.durationMinutes} phút'),
              if (days != null) VLTag.neutral(context, 'Truy cập $days ngày'),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    size: 20, color: context.colors.primary),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}
