// lib/features/booking/presentation/widgets/booking_form_widgets.dart
//
// Parts of "Đặt chuyên gia lên thực đơn": the card that lists what the chef
// will see, and the estimate bar fixed at the bottom with its breakdown.
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';

/// Where the member's health profile stands while the form is open.
enum ShareProfileState { loading, loaded, missing, failed }

/// "Chuyên gia sẽ thấy": exactly what the request sends about the member.
/// "Cho tôi": the health profile and the goal (under the switch) plus the
/// allergies. "Cho gia đình": the number of people and the allergies, no
/// switch because nothing personal is sent.
class SharedProfileCard extends StatelessWidget {
  const SharedProfileCard({
    super.key,
    required this.audience,
    required this.familySize,
    required this.allergies,
    required this.goal,
    required this.health,
    required this.state,
    required this.share,
    required this.onShareChanged,
    required this.onRetry,
  });

  final BookingAudience audience;
  final int familySize;
  final List<String> allergies;
  final String goal;

  /// The profile as the chef would get it; `null` until it is known.
  final MemberHealthDto? health;
  final ShareProfileState state;
  final bool share;
  final ValueChanged<bool> onShareChanged;
  final VoidCallback onRetry;

  String get _allergyText =>
      allergies.isEmpty ? 'Không có' : allergies.map(allergenLabel).join(', ');

  @override
  Widget build(BuildContext context) {
    final family = audience == BookingAudience.family;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final canShare = state == ShareProfileState.loaded;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined,
                  size: 20, color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Chuyên gia sẽ thấy',
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (family) ...[
            InfoRow(label: 'Đặt cho', value: 'Gia đình · $familySize người'),
            InfoRow(label: 'Dị ứng', value: _allergyText),
            const SizedBox(height: 4),
            Text(
                'Không gửi chiều cao, cân nặng, BMI hay mục tiêu của riêng bạn.',
                style: muted),
          ] else ...[
            if (share && canShare) ...[
              for (final (label, value)
                  in health?.rows ?? const <(String, String)>[])
                InfoRow(label: label, value: value),
              InfoRow(label: 'Mục tiêu', value: bookingGoalLabel(goal)),
            ],
            InfoRow(label: 'Dị ứng', value: _allergyText),
            const SizedBox(height: 4),
            switch (state) {
              ShareProfileState.loading =>
                Text('Đang tải hồ sơ sức khoẻ…', style: muted),
              ShareProfileState.missing => Text(
                  'Bạn chưa có hồ sơ sức khoẻ nên chuyên gia không thấy chiều '
                  'cao, cân nặng, BMI, mục tiêu. Thiết lập ở Tôi › Hồ sơ sức khoẻ để chia sẻ.',
                  style: muted),
              ShareProfileState.failed => Row(
                  children: [
                    Expanded(
                      child: Text(
                          'Chưa tải được hồ sơ sức khoẻ nên chưa có gì được chia sẻ.',
                          style: muted),
                    ),
                    TextButton(
                        onPressed: onRetry, child: const Text('Thử lại')),
                  ],
                ),
              ShareProfileState.loaded => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: share,
                  onChanged: onShareChanged,
                  title: const Text('Chia sẻ hồ sơ sức khoẻ với chuyên gia'),
                  subtitle: Text(share
                      ? 'Chỉ chuyên gia này xem được.'
                      : 'Đang tắt: chuyên gia chỉ thấy dị ứng, không thấy chiều cao, cân nặng, BMI, mục tiêu.'),
                ),
            },
          ],
          const SizedBox(height: 4),
          Text('Kèm các bữa trong ngày, ngân sách và ghi chú bạn nhập ở trên.',
              style: muted),
        ],
      ),
    );
  }
}

/// The numbers behind the estimate. [total] is `null` when it can't be told:
/// the number of days being typed is invalid, or the chef lists no price.
class BookingEstimate {
  const BookingEstimate({
    required this.days,
    required this.pricePerDay,
    required this.type,
    required this.audience,
    required this.familySize,
    required this.daysValid,
  });

  final int days;
  final int pricePerDay;
  final BookingType type;
  final BookingAudience audience;
  final int familySize;
  final bool daysValid;

  int? get total => daysValid && pricePerDay > 0 ? days * pricePerDay : null;
}

/// Fixed at the bottom of the form: the estimate large (a tap opens the
/// breakdown) next to the submit button. Stays above the keyboard.
class BookingEstimateBar extends StatelessWidget {
  const BookingEstimateBar({
    super.key,
    required this.estimate,
    required this.sending,
    required this.onSubmit,
  });

  final BookingEstimate estimate;
  final bool sending;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final total = estimate.total;
    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
          child: Row(
            children: [
              // The price keeps most of the bar at 360 dp and large text.
              Expanded(
                flex: 5,
                child: InkWell(
                  key: const ValueKey('estimate-open'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showEstimateBreakdown(context, estimate),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text('Giá ước tính',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textStyles.bodySmall
                                      ?.copyWith(color: context.vl.muted)),
                            ),
                            Icon(Icons.expand_less_rounded,
                                size: 18, color: context.vl.muted),
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            total == null ? 'Chờ báo giá' : formatVnd(total),
                            style: context.textStyles.titleLarge?.copyWith(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 4,
                child: FilledButton(
                  onPressed: sending ? null : onSubmit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  child: Text(sending ? 'Đang gửi…' : 'Gửi yêu cầu',
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the estimate is made, and that it isn't the final price.
Future<void> showEstimateBreakdown(
        BuildContext context, BookingEstimate estimate) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: _EstimateBreakdown(estimate: estimate),
      ),
    );

class _EstimateBreakdown extends StatelessWidget {
  const _EstimateBreakdown({required this.estimate});

  final BookingEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final e = estimate;
    final total = e.total;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final family = e.audience == BookingAudience.family;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Giá ước tính', style: context.textStyles.titleLarge),
        const SizedBox(height: 8),
        InfoRow(
            label: 'Số ngày',
            value: e.daysValid ? '${e.days} ngày' : 'Chưa hợp lệ'),
        InfoRow(label: 'Hình thức', value: e.type.label),
        InfoRow(
            label: 'Đặt cho',
            value: family ? 'Gia đình · ${e.familySize} người' : 'Cho tôi'),
        InfoRow(
            label: 'Giá niêm yết',
            value: e.pricePerDay > 0
                ? '${formatVnd(e.pricePerDay)}/ngày'
                : 'Chuyên gia chưa niêm yết'),
        const Divider(height: 20),
        InfoRow(
            label: 'Tổng ước tính',
            value: total == null
                ? 'Chờ báo giá'
                : '${e.days} × ${formatVnd(e.pricePerDay)} = ${formatVnd(total)}'),
        const SizedBox(height: 8),
        if (family) ...[
          Text(
              'Giá niêm yết tính theo ngày, không nhân theo số người. Chuyên gia '
              'có thể điều chỉnh theo số người khi báo giá.',
              style: muted),
          const SizedBox(height: 4),
        ],
        Text(
            'Giá cuối do hai bên thoả thuận trong chat. Bạn chưa phải trả tiền lúc này.',
            style: muted),
      ],
    );
  }
}
