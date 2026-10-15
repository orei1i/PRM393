// lib/features/meal_planner/presentation/widgets/health_header_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/health_profile.dart';
import 'bmi_gauge.dart';

/// Health Hub: BMI gauge, body stats, goal, restrictions and wearable sync.
class HealthHeaderCard extends StatelessWidget {
  const HealthHeaderCard({super.key, required this.profile, this.onEdit});

  final HealthProfile profile;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BmiGauge(bmi: profile.bmi, width: 132),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    children: [
                      _StatRow(
                          label: 'Chiều cao',
                          value: '${profile.heightCm.round()} cm'),
                      _StatRow(
                          label: 'Cân nặng',
                          value: '${formatDecimal(profile.weightKg)} kg'),
                      _StatRow(
                          label: 'Mục tiêu',
                          value: profile.goal.label,
                          mono: false),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in profile.allergies)
                VLTag.caution(context, 'Dị ứng: ${allergenLabel(a)}'),
              for (final r in profile.dietaryRestrictions)
                VLTag.neutral(context, dietTagLabel(r)),
              HealthSyncBadge(sync: profile.healthSync),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.mono = true});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
          const Spacer(),
          Text(
            value,
            style: mono
                ? AppTypography.mono(size: 14, color: context.colors.onSurface)
                : context.textStyles.labelLarge,
          ),
        ],
      ),
    );
  }
}

/// Apple Health / Health Connect status pill.
class HealthSyncBadge extends StatelessWidget {
  const HealthSyncBadge({super.key, required this.sync, this.onReconnect});

  final HealthSync sync;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    if (sync.provider == HealthSyncProvider.none) {
      return VLTag.neutral(context, 'Chưa kết nối thiết bị sức khoẻ');
    }

    final (String text, Color bg, Color fg, Widget leading) =
        switch (sync.state) {
      HealthSyncState.synced => (
          '${sync.provider.label} · ${sync.lastSyncedAt == null ? 'đã đồng bộ' : relativeTime(sync.lastSyncedAt!)}',
          context.colors.secondaryContainer,
          context.colors.onSecondaryContainer,
          _Dot(color: vl.success),
        ),
      HealthSyncState.syncing => (
          'Đang đồng bộ ${sync.provider.label}…',
          context.colors.secondaryContainer,
          context.colors.onSecondaryContainer,
          const SizedBox.square(
              dimension: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5)),
        ),
      HealthSyncState.paused => (
          '${sync.provider.label} tạm dừng · chạm để kết nối',
          vl.cautionContainer,
          vl.onCautionContainer,
          _Dot(color: vl.caution),
        ),
    };

    return Semantics(
      label: text,
      button: sync.state == HealthSyncState.paused,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: sync.state == HealthSyncState.paused ? onReconnect : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Text(text,
                  style: context.textStyles.labelMedium?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
