// lib/features/meal_planner/presentation/widgets/health_header_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/energy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/health_profile.dart';
import 'bmi_gauge.dart';

/// Health Hub: BMI gauge, body stats, goal, restrictions and wearable sync.
/// With [onEdit] the whole card opens the editor and shows a "Sửa" hint.
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
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (onEdit != null)
                        Semantics(
                          button: true,
                          label: 'Sửa hồ sơ sức khoẻ',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined,
                                  size: 16, color: context.colors.primary),
                              const SizedBox(width: 4),
                              Text('Sửa',
                                  style: context.textStyles.labelLarge
                                      ?.copyWith(
                                          color: context.colors.primary)),
                            ],
                          ),
                        ),
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
          _EnergyLine(profile: profile),
          const SizedBox(height: 8),
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

/// "Nhu cầu ≈ 1.960 kcal/ngày · Nữ, 29 tuổi", or what to add for it.
class _EnergyLine extends StatelessWidget {
  const _EnergyLine({required this.profile});

  final HealthProfile profile;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final tdee = profile.tdee;
    if (tdee == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: vl.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Thêm giới tính và năm sinh để tính nhu cầu năng lượng chính xác hơn',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
            ),
          ),
        ],
      );
    }
    final who = [
      if (profile.gender case final g?) g.label,
      if (profile.age case final a?) '$a tuổi',
    ].join(', ');
    return Row(
      children: [
        Icon(Icons.local_fire_department_outlined,
            size: 18, color: context.colors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Nhu cầu ≈ ${Energy.formatKcal(tdee)} kcal/ngày',
                style: context.textStyles.labelLarge,
              ),
              if (who.isNotEmpty)
                TextSpan(
                  text: ' · $who',
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

/// Instead of [HealthHeaderCard] while the member has no health profile (a
/// new account): what it is for and "Thiết lập hồ sơ".
class HealthProfileSetupCard extends StatelessWidget {
  const HealthProfileSetupCard({super.key, required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      onTap: onSetUp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Thiết lập hồ sơ sức khoẻ',
                    style: context.textStyles.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Bạn chưa có hồ sơ sức khoẻ. Thêm chiều cao, cân nặng, mục tiêu và '
            'dị ứng để AI tính nhu cầu năng lượng và lên thực đơn phù hợp.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.muted),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onSetUp,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Thiết lập hồ sơ'),
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
              Flexible(
                child: Text(text,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelMedium?.copyWith(color: fg)),
              ),
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
