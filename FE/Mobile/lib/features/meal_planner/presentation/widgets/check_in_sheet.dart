// lib/features/meal_planner/presentation/widgets/check_in_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/body_progress.dart';
import '../../domain/entities/body_measurement.dart';
import '../controllers/body_metrics_controller.dart';
import 'progress_review_sheet.dart';

/// "Cập nhật cân nặng": weight (required), waist and body fat (optional) at
/// the saved height, with a live BMI preview. On success it closes and the
/// progress review opens; a failure stays in the sheet with the input kept.
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
  final _waist = TextEditingController();
  final _fat = TextEditingController();
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
    _waist.dispose();
    _fat.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// "BMI mới ≈ 22,1 · Bình thường" for a valid weight.
  String? get _preview {
    if (BodyProgress.validateWeight(_weight.text) != null) return null;
    final bmi = BodyProgress.bmiOf(
        heightCm: widget.heightCm, weightKg: BodyProgress.parse(_weight.text)!);
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
            waistCm: BodyProgress.parse(_waist.text),
            bodyFatPct: BodyProgress.parse(_fat.text),
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
    final numbers = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      LengthLimitingTextInputFormatter(6),
    ];
    const keyboard = TextInputType.numberWithOptions(decimal: true);
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
                  keyboardType: keyboard,
                  inputFormatters: numbers,
                  textInputAction: TextInputAction.next,
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
                TextFormField(
                  controller: _waist,
                  keyboardType: keyboard,
                  inputFormatters: numbers,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                      labelText: 'Vòng eo (cm) — không bắt buộc'),
                  validator: BodyProgress.validateWaist,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _fat,
                  keyboardType: keyboard,
                  inputFormatters: numbers,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                      labelText: 'Tỉ lệ mỡ cơ thể (%) — không bắt buộc'),
                  validator: BodyProgress.validateBodyFat,
                  onFieldSubmitted: (_) => _save(),
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
