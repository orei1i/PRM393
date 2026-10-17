// lib/features/booking/presentation/widgets/booking_contract_tab.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import 'booking_ui.dart';

/// "Hợp đồng": the contract snapshot ("Hồ sơ hợp đồng"), the escrow
/// timeline, the original request and the complaint, if any.
class BookingContractTab extends StatelessWidget {
  const BookingContractTab(
      {super.key, required this.booking, required this.party});

  final BookingDto booking;
  final BookingParty party;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final contract = b.contract;
    final complaint = b.complaint;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        const BookingSectionTitle('Hồ sơ hợp đồng'),
        if (contract == null)
          Text('Hồ sơ hợp đồng được tạo khi hai bên đồng ý một đề xuất giá.',
              style: muted)
        else
          VLCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(contract.scopeText, style: context.textStyles.bodyMedium),
                const SizedBox(height: 8),
                InfoRow(label: 'Số ngày', value: '${contract.planDays} ngày'),
                InfoRow(label: 'Hình thức', value: contract.bookingType.label),
                InfoRow(
                    label: 'Thời gian',
                    value:
                        '${formatDayMonth(contract.startDate)}/${contract.startDate.year} – ${formatDayMonth(contract.endDate)}/${contract.endDate.year}'),
                InfoRow(label: 'Giá', value: formatVnd(contract.price)),
                InfoRow(
                    label: 'Phí nền tảng ${(contract.feeRate * 100).round()} %',
                    value: formatVnd(contract.fee)),
                if (party == BookingParty.chef)
                  InfoRow(
                      label: 'Bạn nhận sau phí',
                      value: formatVnd(contract.price - contract.fee)),
                InfoRow(
                  label: 'Giao kế hoạch',
                  value: contract.bookingType == BookingType.oneShot
                      ? 'trước ${formatVnStamp(contract.deliveryDueAt)}'
                      : 'mỗi ngày trước ${contract.dailySendCutoff}, phản hồi trước ${contract.feedbackCutoff}',
                ),
                if (b.status == BookingStatus.awaitingPayment)
                  InfoRow(
                      label: 'Hạn thanh toán',
                      value: formatVnStamp(contract.paymentDueAt)),
                const SizedBox(height: 8),
                Text(
                  'Tiền được VeganLife giữ đến ${formatVnStamp(b.escrow?.releaseAt ?? contract.releaseAt)} '
                  '(${contract.holdDays} ngày sau khi kết thúc kế hoạch).',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        if (contract != null) ...[
          const BookingSectionTitle('Tiền đặt cọc'),
          EscrowTimeline(booking: b),
        ],
        if (complaint != null) ...[
          const BookingSectionTitle('Khiếu nại'),
          ComplaintSummary(complaint: complaint, price: b.price ?? 0),
        ],
        const BookingSectionTitle('Yêu cầu ban đầu'),
        VLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(label: 'Mục tiêu', value: bookingGoalLabel(b.goal)),
              InfoRow(
                  label: 'Dị ứng',
                  value: b.allergies.isEmpty
                      ? 'Không'
                      : b.allergies.map(allergenLabel).join(', ')),
              InfoRow(
                  label: 'Các bữa trong ngày',
                  value: b.mealPattern.map((s) => s.label).join(', ')),
              InfoRow(
                  label: 'Ngân sách đi chợ',
                  value: b.budgetPerDay == null
                      ? 'Không nêu'
                      : '${formatVnd(b.budgetPerDay!)}/ngày'),
              InfoRow(
                  label: 'Hồ sơ sức khoẻ',
                  value: !b.shareHealthProfile
                      ? 'Không chia sẻ'
                      : b.memberHealth?.summary.isNotEmpty ?? false
                          ? b.memberHealth!.summary
                          : 'Đã chia sẻ'),
              const SizedBox(height: 6),
              Text('Nhu cầu & ghi chú', style: muted),
              const SizedBox(height: 2),
              Text(b.needs, style: context.textStyles.bodyMedium),
            ],
          ),
        ),
        if (b.declineReason != null) ...[
          const SizedBox(height: 12),
          Text('Lý do từ chối: ${b.declineReason}',
              style: context.textStyles.bodyMedium),
        ],
        if (b.cancelReason != null) ...[
          const SizedBox(height: 12),
          Text('Lý do huỷ: ${b.cancelReason}',
              style: context.textStyles.bodyMedium),
        ],
      ],
    );
  }
}

/// "Đã thanh toán · Đang giữ → Kết thúc kế hoạch → Hết hạn khiếu nại →
/// Chuyển cho chuyên gia" (or the complaint and its decision).
class EscrowTimeline extends StatelessWidget {
  const EscrowTimeline({super.key, required this.booking, this.now});

  final BookingDto booking;

  /// Defaults to the device clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final contract = b.contract!;
    final escrow = b.escrow;
    final at = now ?? DateTime.now();
    final planEnd = vnTime(contract.endDate, 23, 59);
    final releaseAt = escrow?.releaseAt ?? contract.releaseAt;
    final complaint = b.complaint;
    final steps = <(String, String?, bool)>[
      (
        escrow == null ? 'Chờ thanh toán' : 'Đã thanh toán · Đang giữ',
        escrow == null
            ? 'Hạn ${formatVnStamp(contract.paymentDueAt)}'
            : '${formatVnd(escrow.amount)} · ${formatVnStamp(escrow.heldAt)}',
        escrow != null,
      ),
      ('Kết thúc kế hoạch', formatVnStamp(planEnd), !at.isBefore(planEnd)),
      if (complaint != null)
        (
          'Khiếu nại · tạm giữ tiền',
          formatVnStamp(complaint.createdAt),
          true,
        )
      else
        (
          'Hết hạn khiếu nại',
          formatVnStamp(releaseAt),
          !at.isBefore(releaseAt)
        ),
      (
        switch (escrow?.status) {
          EscrowStatus.refunded =>
            'Đã hoàn ${formatVnd(escrow!.refundedAmount)} cho thành viên',
          EscrowStatus.partiallyRefunded =>
            'Hoàn ${formatVnd(escrow!.refundedAmount)} · chuyên gia nhận ${formatVnd(escrow.releasedAmount - escrow.feeAmount)}',
          EscrowStatus.frozen => 'Chờ Ban quản trị quyết định',
          _ => 'Chuyển cho chuyên gia',
        },
        switch (escrow?.status) {
          EscrowStatus.released =>
            '${formatVnd(escrow!.releasedAmount - escrow.feeAmount)} sau phí · ${formatVnStamp(escrow.releasedAt ?? releaseAt)}',
          EscrowStatus.frozen => 'Không tự giải ngân khi đang khiếu nại',
          EscrowStatus.held =>
            '≈ ${formatVnd(escrow!.amount - (escrow.amount * contract.feeRate).round())} sau phí',
          _ => null,
        },
        escrow != null && !escrow.status.isActive,
      ),
    ];
    return VLCard(
      child: Column(
        children: [
          for (final (i, (title, detail, done)) in steps.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: done ? context.vl.success : context.vl.muted,
                    ),
                    if (i < steps.length - 1)
                      Container(width: 2, height: 28, color: context.vl.border),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: context.textStyles.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        if (detail != null)
                          Text(detail,
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: context.vl.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (escrow != null)
            Align(
                alignment: Alignment.centerLeft,
                child: escrowStatusTag(context, escrow.status)),
        ],
      ),
    );
  }
}

/// The complaint as both parties see it: reason, description, evidence,
/// the chef's answer and the admin decision.
class ComplaintSummary extends StatelessWidget {
  const ComplaintSummary(
      {super.key, required this.complaint, required this.price});

  final ComplaintDto complaint;
  final int price;

  @override
  Widget build(BuildContext context) {
    final c = complaint;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final decision = c.decision;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(c.reason.label,
                  style: context.textStyles.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              StatusPill(
                label: c.status.label,
                background: c.isOpen
                    ? context.vl.cautionContainer
                    : context.vl.successContainer,
                foreground: c.isOpen
                    ? context.vl.onCautionContainer
                    : context.vl.onSuccessContainer,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(c.description, style: context.textStyles.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'Yêu cầu: ${c.requestedOutcome.label}'
            '${c.requestedOutcome == RequestedOutcome.partialRefund ? ' ${formatVnd(c.requestedAmount)}' : ''}'
            ' · gửi ${formatVnStamp(c.createdAt)}',
            style: muted,
          ),
          if (c.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Bằng chứng', style: context.textStyles.labelLarge),
            for (final e in c.evidence) EvidenceTile(evidence: e),
          ],
          if (c.chefResponse != null) ...[
            const SizedBox(height: 8),
            Text('Phản hồi của chuyên gia',
                style: context.textStyles.labelLarge),
            const SizedBox(height: 2),
            Text(c.chefResponse!, style: context.textStyles.bodyMedium),
          ],
          if (decision != null) ...[
            const SizedBox(height: 8),
            Text('Quyết định của Ban quản trị: ${decision.label}',
                style: context.textStyles.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (c.refundAmount != null && c.refundAmount! > 0)
              Text(
                  'Hoàn ${formatVnd(c.refundAmount!)} về phương thức thanh toán ban đầu',
                  style: context.textStyles.bodyMedium),
            if (c.adminNote != null) Text('"${c.adminNote}"', style: muted),
          ],
        ],
      ),
    );
  }
}

/// A link (opens in the browser) or an uploaded image (opens its URL).
class EvidenceTile extends StatelessWidget {
  const EvidenceTile({super.key, required this.evidence, this.onRemove});

  final EvidenceDto evidence;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    final isLink = e.kind == EvidenceKind.link;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(isLink ? Icons.link_rounded : Icons.image_outlined),
      title: Text(
        e.caption?.isNotEmpty ?? false ? e.caption! : (isLink ? e.url : 'Ảnh'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (e.submittedBy == BookingParty.chef) 'Chuyên gia',
          isLink ? Uri.tryParse(e.url)?.host ?? e.url : 'Ảnh đính kèm',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onRemove == null
          ? const Icon(Icons.open_in_new_rounded, size: 18)
          : IconButton(
              tooltip: 'Bỏ bằng chứng',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
      onTap: onRemove != null
          ? null
          : () =>
              launchUrl(Uri.parse(e.url), mode: LaunchMode.externalApplication),
    );
  }
}
