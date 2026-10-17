// lib/features/restaurant/presentation/widgets/location_chip.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../data/location_service.dart';
import '../screens/location_picker_screen.dart';

/// "📍 Gần: {label} ▾": where distances are measured from. Tapping opens
/// "Chọn vị trí"; the choice applies to every "gần bạn" list.
class LocationChip extends ConsumerWidget {
  const LocationChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(userLocationProvider).valueOrNull;
    final fg = context.colors.onSecondaryContainer;
    return Semantics(
      button: true,
      label: location == null
          ? 'Chọn vị trí'
          : 'Vị trí: ${location.label}. Chạm để đổi',
      excludeSemantics: true,
      child: Material(
        color: context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => pickUserLocation(context, ref),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_rounded, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      location == null
                          ? 'Đang xác định vị trí…'
                          : 'Gần: ${location.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelLarge?.copyWith(color: fg),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down_rounded, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
