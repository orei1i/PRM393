// lib/features/recipe/presentation/widgets/servings_stepper.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/recipe_scaling.dart';

/// "Nấu cho [–] N người [+]": scales the amounts only (the energy per
/// serving and the member's targets don't change).
class ServingsStepper extends StatelessWidget {
  const ServingsStepper({
    super.key,
    required this.servings,
    required this.baseServings,
    required this.onChanged,
  });

  final int servings;
  final int baseServings;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Nấu cho',
                  style: context.textStyles.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton.outlined(
              tooltip: 'Giảm số người',
              onPressed:
                  servings > minServings ? () => onChanged(servings - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Text(
                '$servings người',
                textAlign: TextAlign.center,
                style: context.textStyles.titleMedium,
              ),
            ),
            IconButton.outlined(
              tooltip: 'Tăng số người',
              onPressed:
                  servings < maxServings ? () => onChanged(servings + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Text(
          'Chỉ đổi định lượng khi nấu cho nhiều người, không đổi mục tiêu '
          'năng lượng của bạn.',
          style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
        ),
        if (servings != baseServings)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(baseServings),
              child: Text('Về $baseServings người'),
            ),
          ),
      ],
    );
  }
}
