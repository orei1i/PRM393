// lib/features/restaurant/presentation/widgets/restaurant_filter_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';

/// Opens "Bộ lọc"; resolves to the applied filters, or `null` when closed.
Future<RestaurantFilters?> showRestaurantFilterSheet(
        BuildContext context, RestaurantFilters current) =>
    showModalBottomSheet<RestaurantFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => RestaurantFilterSheet(initial: current),
    );

/// "Bộ lọc": certified-only switch, "Sắp xếp" and "Bán kính", with "Đặt lại"
/// and "Áp dụng". Nothing changes until "Áp dụng".
class RestaurantFilterSheet extends StatefulWidget {
  const RestaurantFilterSheet({super.key, required this.initial});

  final RestaurantFilters initial;

  @override
  State<RestaurantFilterSheet> createState() => _RestaurantFilterSheetState();
}

class _RestaurantFilterSheetState extends State<RestaurantFilterSheet> {
  late RestaurantFilters _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bộ lọc', style: context.textStyles.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _value.certifiedOnly,
            onChanged: (v) =>
                setState(() => _value = _value.copyWith(certifiedOnly: v)),
            secondary: Icon(Icons.verified_outlined, color: context.vl.success),
            title: const Text('Chỉ quán đã chứng nhận thuần chay'),
          ),
          const SizedBox(height: 8),
          Text('Sắp xếp', style: context.textStyles.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<RestaurantSort>(
            segments: [
              for (final s in RestaurantSort.values)
                ButtonSegment(
                  value: s,
                  label: Text(s.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {_value.sort},
            showSelectedIcon: false,
            expandedInsets: EdgeInsets.zero,
            onSelectionChanged: (selection) =>
                setState(() => _value = _value.copyWith(sort: selection.first)),
          ),
          const SizedBox(height: 16),
          Text('Bán kính', style: context.textStyles.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final km in restaurantRadiusChoicesKm)
                ChoiceChip(
                  label: Text(radiusLabel(km)),
                  selected: _value.radiusKm == km,
                  onSelected: (_) => setState(
                      () => _value = _value.copyWith(radiusKm: () => km)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Quán chưa có vị trí trên bản đồ chỉ hiện khi chọn Không giới hạn.',
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _value == RestaurantFilters.defaults
                      ? null
                      : () =>
                          setState(() => _value = RestaurantFilters.defaults),
                  child: const Text('Đặt lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_value),
                  child: const Text('Áp dụng'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
