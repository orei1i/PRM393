// lib/features/booking/presentation/widgets/booking_contract_tab.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/utils/open_url.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../../domain/booking_views.dart';
import 'booking_ui.dart';

/// "Hợp đồng": the contract snapshot ("Hồ sơ hợp đồng"), the money stages
/// (amount, who holds it, the release date), the original request and the
/// complaint, if any.
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
                  b.isAdminResolved
                      ? 'Ban quản trị đã xử lý khoản tiền này, VeganLife không còn giữ.'
                      : b.escrow?.releaseAt == null
                          ? 'Tiền được VeganLife giữ đến ${contract.holdDays} ngày sau khi hợp đồng hoàn thành.'
                          : 'Tiền được VeganLife giữ đến ${formatVnStamp(b.escrow!.releaseAt!)} '
                              '(${contract.holdDays} ngày sau khi hợp đồng hoàn thành).',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        if (contract != null) ...[
          const BookingSectionTitle('Tiền của hợp đồng'),
          EscrowTimeline(booking: b, party: party),
        ],
        if (b.isAdminResolved) ...[
          const BookingSectionTitle('Ban quản trị xử lý'),
          AdminResolutionSummary(booking: b, party: party),
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
              InfoRow(label: 'Đặt cho', value: b.audienceLabel),
              // A family request carries nothing personal.
              if (!b.isFamily)
                InfoRow(
                    label: 'Mục tiêu',
                    value: b.goal == null
                        ? 'Không chia sẻ'
                        : bookingGoalLabel(b.goal!)),
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
              if (!b.isFamily)
                InfoRow(
                    label: 'Hồ sơ sức khoẻ',
                    value: !b.shareHealthProfile
                        ? 'Không chia sẻ'
                        : b.memberHealth?.summary.isNotEmpty ?? false
                            ? b.memberHealth!.summary
                            : 'Đã chia sẻ'),
              const SizedBox(height: 6),
              Text(b.isFamily ? 'Ghi chú' : 'Nhu cầu & ghi chú', style: muted),
              const SizedBox(height: 2),
              Text(b.needs.isEmpty ? 'Không có' : b.needs,
                  style: context.textStyles.bodyMedium),
            ],
          ),
        ),
        if (b.declineReason != null) ...[
          const SizedBox(height: 12),
          Text('Lý do từ chối: ${b.declineReason}',
              style: context.textStyles.bodyMedium),
        ],
        // An admin's refund: the same text is the note above, not a member's reason.
        if (b.cancelReason != null && !b.isAdminResolved) ...[
          const SizedBox(height: 12),
          Text('Lý do huỷ: ${b.cancelReason}',
              style: context.textStyles.bodyMedium),
        ],
      ],
    );
  }
}

/// Who holds the money right now, in one line.
String moneyHolder(BookingDto b) {
  final escrow = b.escrow;
  if (escrow == null) return 'Chưa thanh toán';
  return switch (escrow.status) {
    EscrowStatus.held => 'VeganLife đang giữ',
    EscrowStatus.frozen => 'VeganLife tạm giữ do khiếu nại',
    EscrowStatus.released => 'Đã vào ví chuyên gia',
    EscrowStatus.refunded => 'Đã hoàn vào ví thành viên',
    EscrowStatus.partiallyRefunded => 'Đã chia cho ví hai bên',
  };
}

/// "Đã thanh toán → Chuyên gia xác nhận hoàn thành → Giữ 7 ngày để khiếu nại →
/// Chuyển vào ví chuyên gia" (or the complaint and its decision), under the
/// amount, who holds it and the release date. Both parties see the same stages.
class EscrowTimeline extends StatelessWidget {
  const EscrowTimeline(
      {super.key,
      required this.booking,
      this.party = BookingParty.member,
      this.now});

  final BookingDto booking;
  final BookingParty party;

  /// Defaults to the device clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final contract = b.contract!;
    final escrow = b.escrow;
    final at = now ?? DateTime.now();
    final releaseAt = escrow?.releaseAt;
    final completedAt = b.completedAt;
    final complaint = b.complaint;
    // Nobody confirmed: an admin decided, and that is the step to show.
    final adminResolved = b.isAdminResolved;
    // Cancelled after paying: the money came back, the work never started.
    final cancelledPaid =
        b.status == BookingStatus.cancelled && escrow != null && !adminResolved;
    final steps = <(String, String?, bool)>[
      (
        escrow == null
            ? 'Chờ thanh toán'
            : 'Đã thanh toán · VeganLife giữ tiền',
        escrow == null
            ? 'Hạn ${formatVnStamp(contract.paymentDueAt)}'
            : '${formatVnd(escrow.amount)} · ${formatVnStamp(escrow.heldAt)}',
        escrow != null,
      ),
      if (!cancelledPaid && !adminResolved)
        (
          b.autoCompleted
              ? autoCompletedNote
              : 'Chuyên gia xác nhận hoàn thành',
          completedAt != null
              ? formatVnStamp(completedAt)
              : b.overdueUndelivered(at)
                  ? 'Đã giao ${b.deliveredDays}/${b.planDays} ngày · chưa đủ nên không tự hoàn tất, tiền vẫn được giữ'
                  : b.deliveredAfterAutoComplete(at)
                      ? 'Đã giao ${b.deliveredDays}/${b.planDays} ngày · giao đủ sau ${formatVnStamp(autoCompleteAt(b.endDate))} nên không tự hoàn tất, tiền vẫn được giữ'
                      : b.fullyDelivered
                          ? 'Đã giao ${b.deliveredDays}/${b.planDays} ngày · chưa xác nhận, hệ thống tự hoàn tất lúc ${formatVnStamp(autoCompleteAt(b.endDate))}'
                          : 'Đã giao ${b.deliveredDays}/${b.planDays} ngày · chưa xác nhận',
          completedAt != null,
        ),
      if (adminResolved)
        (
          'Ban quản trị xử lý',
          'Đã giao ${b.deliveredDays}/${b.planDays} ngày · ${formatVnStamp(escrow!.releasedAt ?? escrow.refundedAt ?? escrow.heldAt)}',
          true,
        )
      else if (complaint != null)
        (
          'Khiếu nại · tạm giữ tiền',
          formatVnStamp(complaint.createdAt),
          true,
        )
      else if (!cancelledPaid)
        (
          'Giữ ${contract.holdDays} ngày để khiếu nại',
          releaseAt != null
              ? 'Đến ${formatVnStamp(releaseAt)}'
              : 'Bắt đầu tính từ lúc hợp đồng hoàn thành',
          releaseAt != null && !at.isBefore(releaseAt),
        ),
      (
        switch (escrow?.status) {
          EscrowStatus.refunded =>
            'Đã hoàn ${formatVnd(escrow!.refundedAmount)} vào ví thành viên',
          EscrowStatus.partiallyRefunded =>
            'Hoàn ${formatVnd(escrow!.refundedAmount)} · chuyên gia nhận ${formatVnd(escrow.releasedAmount - escrow.feeAmount)}',
          EscrowStatus.frozen => 'Chờ Ban quản trị quyết định',
          _ => 'Chuyển vào ví chuyên gia',
        },
        switch (escrow?.status) {
          EscrowStatus.released =>
            '${formatVnd(escrow!.releasedAmount - escrow.feeAmount)} sau phí · ${formatVnStamp(escrow.releasedAt ?? escrow.heldAt)}',
          EscrowStatus.frozen => 'Không tự giải ngân khi đang khiếu nại',
          EscrowStatus.held =>
            '≈ ${formatVnd(escrow!.amount - (escrow.amount * contract.feeRate).round())} sau phí',
          _ => null,
        },
        escrow != null && !escrow.status.isActive,
      ),
      if (party == BookingParty.chef &&
          (escrow?.status == EscrowStatus.released ||
              escrow?.status == EscrowStatus.partiallyRefunded))
        (
          'Rút về ngân hàng',
          'Gửi yêu cầu trong Ví của tôi, Ban quản trị duyệt',
          false,
        ),
    ];
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow(label: 'Số tiền', value: formatVnd(contract.price)),
          InfoRow(label: 'Tiền đang ở', value: moneyHolder(b)),
          InfoRow(
              label: 'Ngày chuyển vào ví chuyên gia',
              value: escrow?.releasedAt != null
                  ? formatVnStamp(escrow!.releasedAt!)
                  : adminResolved
                      ? 'Không chuyển'
                      : releaseAt != null
                          ? formatVnStamp(releaseAt)
                          : 'Chưa có ngày'),
          const SizedBox(height: 8),
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

/// An admin's decision on a stuck hold, as both parties see it: why it came to
/// an admin, what it paid, and the note.
class AdminResolutionSummary extends StatelessWidget {
  const AdminResolutionSummary(
      {super.key, required this.booking, required this.party});

  final BookingDto booking;
  final BookingParty party;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final note = b.escrow?.resolutionNote;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(adminResolutionOutcome(b, party),
              style: context.textStyles.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              'Hợp đồng không tự hoàn tất được, chuyên gia chưa xác nhận và '
              'không có khiếu nại nên Ban quản trị quyết định.',
              style: context.textStyles.bodyMedium),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('"$note"', style: muted),
          ],
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
              Text('Hoàn ${formatVnd(c.refundAmount!)} vào ví của thành viên',
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
      onTap: onRemove != null ? null : () => openExternalUrl(e.url),
    );
  }
}
