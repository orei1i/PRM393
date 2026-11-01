// lib/features/meal_planner/presentation/widgets/check_in_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/meal_planner_api_service.dart';
import '../../domain/body_progress.dart';
import '../../domain/entities/body_measurement.dart';
import '../controllers/body_metrics_controller.dart';
import 'progress_review_sheet.dart';
import 'weight_chart.dart';

/// "Cập nhật cân nặng": weight at the saved height, with a live BMI preview and
/// the member's BMI over time, the typed weight drawn as the last point. On
/// success it closes and the progress review opens; a failure stays in the
/// sheet with the input kept.
class CheckInSheet extends ConsumerStatefulWidget {
  const CheckInSheet({super.key, required this.heightCm, this.last});

  /// The saved height ("đổi trong Hồ sơ sức khoẻ").
  final double heightCm;

  /// The latest weigh-in, for "Lần trước: 66,0 kg · 21/10".
  final BodyMeasurement? last;

  /// Opens the sheet over [context]; after a save shows the review with the
  /// buttons for [origin].
  static Future<void> open(
    BuildContext context, {
    required double heightCm,
    BodyMeasurement? last,
    required ReviewOrigin origin,
  }) async {
    final result = await showModalBottomSheet<CheckInResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CheckInSheet(heightCm: heightCm, last: last),
    );
    if (result == null || !context.mounted) return;
    await ProgressReviewSheet.show(context, result.review, origin: origin);
  }

  @override
  ConsumerState<CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<CheckInSheet> {
  final _form = GlobalKey<FormState>();
  final _weight = TextEditingController();
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _weight.addListener(_changed);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The weight being typed; `null` while invalid.
  double? get _typedKg => BodyProgress.validateWeight(_weight.text) == null
      ? BodyProgress.parse(_weight.text)
      : null;

  /// "BMI mới ≈ 22,1 · Bình thường" for a valid weight.
  String? get _preview {
    final kg = _typedKg;
    if (kg == null) return null;
    final bmi = BodyProgress.bmiOf(heightCm: widget.heightCm, weightKg: kg);
    return 'BMI mới ≈ ${formatDecimal(bmi)} · ${Bmi.categorize(bmi).label}';
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final result = await ref.read(bodyMeasurementsProvider.notifier).log(
            weightKg: BodyProgress.parse(_weight.text)!,
          );
      navigator.pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final last = widget.last;
    final preview = _preview;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Form(
            key: _form,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cập nhật cân nặng', style: context.textStyles.titleLarge),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: 'Cân nặng (kg)',
                    helperText: last == null
                        ? null
                        : 'Lần trước: ${BodyProgress.formatKg(last.weightKg)} kg'
                            ' · ${formatDayMonth(last.loggedAt)}',
                  ),
                  validator: BodyProgress.validateWeight,
                ),
                const SizedBox(height: 12),
                Text(
                  'Chiều cao ${BodyProgress.formatTrim(widget.heightCm)} cm · '
                  'đổi trong Hồ sơ sức khoẻ',
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.speed_rounded,
                          size: 18, color: context.colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child:
                            Text(preview, style: context.textStyles.labelLarge),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _BmiHistory(heightCm: widget.heightCm, typedKg: _typedKg),
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(error,
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.colors.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// BMI over time inside the sheet: the healthy band, every weigh-in, and the
/// weight being typed as a filled last point. Works from a single point; with
/// no weigh-in and nothing typed it says what will appear. History that is
/// still loading or unavailable only leaves the older points out.
class _BmiHistory extends ConsumerWidget {
  const _BmiHistory({required this.heightCm, this.typedKg});

  final double heightCm;
  final double? typedKg;

  /// "BMI từ 22,0 đến 22,3 từ 03/09 đến 29/10, đang nhập 22,1".
  static String semanticsFor(List<ChartPoint> points, {required bool typing}) {
    final values = points.map((p) => p.value);
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final range = points.length == 1
        ? 'BMI ${formatDecimal(lo)} ngày ${formatDayMonth(points.last.day)}'
        : 'BMI từ ${formatDecimal(lo)} đến ${formatDecimal(hi)} '
            'từ ${formatDayMonth(points.first.day)} '
            'đến ${formatDayMonth(points.last.day)}';
    return typing
        ? '$range, đang nhập ${formatDecimal(points.last.value)}'
        : range;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final async = ref.watch(bodyMeasurementsProvider);
    final typing = typedKg != null;
    final points = BodyProgress.bmiPreviewSeries(
      async.valueOrNull ?? const [],
      heightCm: heightCm,
      now: ref.watch(plannerClockProvider)(),
      typedWeightKg: typedKg,
    );
    const band = BodyProgress.bmiBand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BMI theo thời gian', style: context.textStyles.titleSmall),
        const SizedBox(height: 8),
        if (points.isEmpty)
          Text(
              async.isLoading
                  ? 'Đang tải lịch sử cân nặng…'
                  : async.hasError
                      ? 'Chưa tải được lịch sử cân nặng.'
                      : 'Chưa có lần cân nào. Nhập cân nặng để xem BMI của bạn '
                          'trên biểu đồ.',
              style: muted)
        else ...[
          WeightChart(
            points: points,
            band: band,
            series: MetricsSeries.bmi,
            height: 120,
            previewLast: typing,
            semanticsLabel: semanticsFor(points, typing: typing),
          ),
          const SizedBox(height: 6),
          Text(
            'Vùng xanh: BMI bình thường (${formatDecimal(band.min)} – '
            '${formatDecimal(band.max)})'
            '${typing ? '. Chấm đậm: số bạn đang nhập.' : ''}',
            style: muted,
          ),
        ],
      ],
    );
  }
}
