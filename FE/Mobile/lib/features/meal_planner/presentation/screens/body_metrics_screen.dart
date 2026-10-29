// lib/features/meal_planner/presentation/screens/body_metrics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_nav.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../data/meal_planner_api_service.dart';
import '../../domain/body_progress.dart';
import '../../domain/entities/body_measurement.dart';
import '../../domain/entities/health_profile.dart';
import '../controllers/body_metrics_controller.dart';
import '../widgets/check_in_sheet.dart';
import '../widgets/progress_review_sheet.dart';
import '../widgets/weight_chart.dart';
import 'health_profile_edit_screen.dart';

/// "Theo dõi cân nặng": current weight and BMI, the healthy weight range, a
/// weight/BMI chart over a week, a month or everything, the reminder
/// cadence and the weigh-in history. Opened from Thực đơn (health card,
/// progress review) and Tôi (Hồ sơ sức khoẻ).
class BodyMetricsScreen extends StatelessWidget {
  const BodyMetricsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.bodyMetrics),
        builder: (_) => const BodyMetricsScreen(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theo dõi cân nặng'),
        actions: const [_UpdateAction()],
      ),
      body: const GuestGate(
        icon: Icons.monitor_weight_outlined,
        title: 'Theo dõi cân nặng',
        message: 'Đăng nhập để ghi cân nặng, xem BMI và tiến độ theo Thực đơn.',
        benefits: [
          'Biểu đồ cân nặng và BMI theo tuần, tháng',
          'Nhắc cập nhật cân nặng định kỳ',
          'Mục tiêu năng lượng tự cập nhật theo cân nặng mới',
        ],
        child: _Body(),
      ),
    );
  }
}

/// Opens "Cập nhật cân nặng" over the screen; the review then says "Xong".
Future<void> _checkIn(BuildContext context, WidgetRef ref,
    {required HealthProfile profile}) {
  return CheckInSheet.open(
    context,
    heightCm: profile.heightCm,
    last: ref.read(bodyMeasurementsProvider).valueOrNull?.firstOrNull,
    origin: ReviewOrigin.metricsScreen,
  );
}

/// App bar "Cập nhật" once there is a profile to log against.
class _UpdateAction extends ConsumerWidget {
  const _UpdateAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(plannerUserIdProvider) == null) {
      return const SizedBox.shrink();
    }
    final profile = ref.watch(profileHealthProvider).valueOrNull;
    if (profile == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: () => _checkIn(context, ref, profile: profile),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Cập nhật'),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  MetricsSeries _series = MetricsSeries.weight;
  MetricsRange _range = MetricsRange.month;

  void _retry() => ref
    ..invalidate(profileHealthProvider)
    ..invalidate(bodyMeasurementsProvider);

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileHealthProvider);
    final historyAsync = ref.watch(bodyMeasurementsProvider);
    if ((profileAsync.hasError && !profileAsync.hasValue) ||
        (historyAsync.hasError && !historyAsync.hasValue)) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
            error: profileAsync.error ?? historyAsync.error!,
            onRetry: _retry,
          ),
        ),
      );
    }
    if (!profileAsync.hasValue || !historyAsync.hasValue) {
      return const _Skeleton();
    }
    final profile = profileAsync.requireValue;
    final history = historyAsync.requireValue;
    if (profile == null) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.monitor_heart_outlined,
            title: 'Thiết lập hồ sơ sức khoẻ để theo dõi BMI',
            message:
                'Thêm chiều cao và cân nặng của bạn để bắt đầu theo dõi tiến độ.',
            actionLabel: 'Thiết lập hồ sơ',
            onAction: () async {
              final saved = await Navigator.of(context)
                  .push(HealthProfileEditScreen.route());
              if (saved == true) _retry();
            },
          ),
        ),
      );
    }
    if (history.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.monitor_weight_outlined,
            title: 'Chưa có lần cân nào',
            message: 'Ghi cân nặng hôm nay để bắt đầu theo dõi BMI và tiến độ.',
            actionLabel: 'Cập nhật cân nặng',
            onAction: () => _checkIn(context, ref, profile: profile),
          ),
        ),
      );
    }

    final now = ref.watch(plannerClockProvider)();
    return RefreshIndicator(
      onRefresh: () async {
        _retry();
        try {
          await ref.read(bodyMeasurementsProvider.future);
        } catch (_) {
          // Shown by the error state.
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SummaryCard(profile: profile, history: history, now: now),
          const SizedBox(height: 12),
          _ChartCard(
            profile: profile,
            history: history,
            now: now,
            series: _series,
            range: _range,
            onSeries: (s) => setState(() => _series = s),
            onRange: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: 12),
          const _ReminderCard(),
          const SizedBox(height: 20),
          Text('Lịch sử', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          _HistoryList(history: history, now: now),
          const SizedBox(height: 16),
          Text(
            BodyProgress.disclaimer,
            textAlign: TextAlign.center,
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.profile, required this.history, required this.now});

  final HealthProfile profile;
  final List<BodyMeasurement> history;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final muted =
        context.textStyles.bodyMedium?.copyWith(color: context.vl.muted);
    final month = BodyProgress.series(history,
        range: MetricsRange.month, of: MetricsSeries.weight, now: now);
    final band = BodyProgress.healthyWeightRange(profile.heightCm);
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hiện tại ${BodyProgress.formatKg(profile.weightKg)} kg · '
            'BMI ${formatDecimal(profile.bmi)} '
            '(${profile.bmiCategory().label})',
            style: context.textStyles.titleMedium,
          ),
          if (month.length >= 2) ...[
            const SizedBox(height: 6),
            Text(
              '30 ngày qua: '
              '${BodyProgress.formatSignedKg(month.last.value - month.first.value)}',
              style: context.textStyles.bodyMedium,
            ),
          ],
          const SizedBox(height: 6),
          Text('Mục tiêu: ${profile.goal.label}',
              style: context.textStyles.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'Khoảng cân nặng có BMI bình thường: '
            '${formatDecimal(band.min)} – ${formatDecimal(band.max)} kg '
            '(chuẩn châu Á)',
            style: muted,
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.profile,
    required this.history,
    required this.now,
    required this.series,
    required this.range,
    required this.onSeries,
    required this.onRange,
  });

  final HealthProfile profile;
  final List<BodyMeasurement> history;
  final DateTime now;
  final MetricsSeries series;
  final MetricsRange range;
  final ValueChanged<MetricsSeries> onSeries;
  final ValueChanged<MetricsRange> onRange;

  /// "Cân nặng từ 65,0 đến 66,0 kg trong 30 ngày".
  static String semanticsFor(
      MetricsSeries series, MetricsRange range, List<ChartPoint> points) {
    final values = points.map((p) => p.value);
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final unit = series.unit.isEmpty ? '' : ' ${series.unit}';
    final when = switch (range.days) {
      final n? => 'trong $n ngày',
      null => 'từ ${formatDayMonth(points.first.day)} '
          'đến ${formatDayMonth(points.last.day)}',
    };
    return '${series.label} từ ${formatDecimal(lo)} đến '
        '${formatDecimal(hi)}$unit $when';
  }

  @override
  Widget build(BuildContext context) {
    final points =
        BodyProgress.series(history, range: range, of: series, now: now);
    final band = series == MetricsSeries.weight
        ? BodyProgress.healthyWeightRange(profile.heightCm)
        : BodyProgress.bmiBand;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<MetricsSeries>(
              showSelectedIcon: false,
              segments: [
                for (final s in MetricsSeries.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {series},
              onSelectionChanged: (s) => onSeries(s.first),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final r in MetricsRange.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: r == range,
                  onSelected: (_) => onRange(r),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (points.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa đủ dữ liệu để vẽ biểu đồ — cần ít nhất 2 lần cân trong '
                'khoảng này.',
                textAlign: TextAlign.center,
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              ),
            )
          else
            WeightChart(
              points: points,
              band: band,
              series: series,
              semanticsLabel: semanticsFor(series, range, points),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 14,
                height: 10,
                decoration: BoxDecoration(
                  color: context.vl.successContainer,
                  border: Border.all(color: context.vl.success),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  series == MetricsSeries.weight
                      ? 'Vùng xanh: cân nặng có BMI bình thường '
                          '(${formatDecimal(band.min)} – '
                          '${formatDecimal(band.max)} kg)'
                      : 'Vùng xanh: BMI bình thường '
                          '(${formatDecimal(band.min)} – '
                          '${formatDecimal(band.max)})',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends ConsumerWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cadence = ref.watch(checkInPrefsProvider).cadence;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nhắc cập nhật cân nặng', style: context.textStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Thực đơn nhắc bạn cân lại khi đến hạn.',
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<CheckInCadence>(
              showSelectedIcon: false,
              segments: [
                for (final c in CheckInCadence.values)
                  ButtonSegment(value: c, label: Text(c.label)),
              ],
              selected: {cadence},
              onSelectionChanged: (s) =>
                  ref.read(checkInPrefsProvider.notifier).setCadence(s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.history, required this.now});

  /// Newest first.
  final List<BodyMeasurement> history;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (final (i, m) in history.indexed) ...[
            if (i > 0) const Divider(height: 1),
            _HistoryRow(
              measurement: m,
              previous: i + 1 < history.length ? history[i + 1] : null,
              now: now,
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(
      {required this.measurement, required this.previous, required this.now});

  final BodyMeasurement measurement;
  final BodyMeasurement? previous;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final day = m.loggedAt;
    final date = day.year == now.year
        ? formatLongDate(day)
        : '${formatLongDate(day)}/${day.year}';
    final ratio = m.waistToHeight;
    final p = previous;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date, style: context.textStyles.titleSmall),
                    const SizedBox(height: 2),
                    Text('BMI ${formatDecimal(m.bmi)}', style: muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${BodyProgress.formatKg(m.weightKg)} kg',
                      style: context.textStyles.titleSmall),
                  if (p != null) ...[
                    const SizedBox(height: 2),
                    Text(BodyProgress.formatSignedKg(m.weightKg - p.weightKg),
                        style: muted),
                  ],
                ],
              ),
            ],
          ),
          if (m.waistCm != null ||
              m.bodyFatPct != null ||
              m.source == MeasurementSource.profile) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (m.waistCm case final waist? when ratio != null)
                  BodyProgress.whtrNeedsCaution(ratio)
                      ? MetricPill.tone(
                          context,
                          'Eo ${BodyProgress.formatTrim(waist)} cm · '
                          'WHtR ${BodyProgress.formatWhtr(ratio)}',
                          VerdictTone.caution)
                      : MetricPill.neutral(
                          context,
                          'Eo ${BodyProgress.formatTrim(waist)} cm · '
                          'WHtR ${BodyProgress.formatWhtr(ratio)}'),
                if (m.bodyFatPct case final fat?)
                  MetricPill.neutral(
                      context, 'Mỡ ${BodyProgress.formatTrim(fat)} %'),
                if (m.source == MeasurementSource.profile)
                  MetricPill.neutral(context, 'Từ Hồ sơ sức khoẻ'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 96, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(height: 260, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(height: 72, radius: 16),
          ],
        ),
      ),
    );
  }
}
