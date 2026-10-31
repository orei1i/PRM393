// lib/features/booking/domain/booking_views.dart
//
// How bookings are grouped and flagged on the member's "Lịch sử tư vấn" and
// the chef's "Yêu cầu tư vấn" (pure functions, unit-tested).
import '../../../core/utils/formatters.dart';
import '../../chef_studio/domain/wallet_rules.dart';
import '../data/models/booking_models.dart';
import 'booking_enums.dart';
import 'booking_rules.dart';

/// Tabs of the chef inbox.
enum InboxTab {
  fresh('Mới'),
  negotiating('Đang thương lượng'),
  inProgress('Đang thực hiện'),
  finished('Đã kết thúc');

  const InboxTab(this.label);
  final String label;

  static InboxTab of(BookingStatus status) => switch (status) {
        BookingStatus.requested => fresh,
        BookingStatus.negotiating ||
        BookingStatus.awaitingPayment =>
          negotiating,
        BookingStatus.active ||
        BookingStatus.ended ||
        BookingStatus.disputed =>
          inProgress,
        _ => finished,
      };
}

/// Index of the current step of "Gửi yêu cầu → Thoả thuận giá → Thanh toán
/// → Nhận kế hoạch → Hoàn tất" (5 = every step done).
int bookingStep(BookingDto b) => switch (b.status) {
      BookingStatus.requested || BookingStatus.negotiating => 1,
      BookingStatus.awaitingPayment => 2,
      BookingStatus.expired => 2,
      BookingStatus.declined ||
      BookingStatus.cancelled =>
        b.contract == null ? 1 : 2,
      BookingStatus.active ||
      BookingStatus.disputed =>
        b.deliveredDays >= b.planDays ? 4 : 3,
      BookingStatus.ended => 4,
      BookingStatus.completed || BookingStatus.resolved => 5,
    };

const bookingSteps = [
  'Gửi yêu cầu',
  'Thoả thuận giá',
  'Thanh toán',
  'Nhận kế hoạch',
  'Hoàn tất',
];

/// The 1-based plan day that falls on the VN calendar day of [now], or
/// `null` outside the plan.
int? todayIndex(BookingDto b, DateTime now) {
  final today = vnDateOf(now);
  // Rounded: a local DST switch may make a calendar day 23 or 25 hours.
  final index = (today.difference(b.startDate).inHours / 24).round() + 1;
  return index >= 1 && index <= b.planDays ? index : null;
}

/// The chef still owes a day that is due today (DailyFeedback) or the whole
/// plan whose delivery deadline is today or past (OneShot).
bool dueToday(BookingDto b, DateTime now) {
  if (b.status != BookingStatus.active) return false;
  if (b.bookingType == BookingType.dailyFeedback) {
    final index = todayIndex(b, now);
    return index != null && b.deliveredDays < index;
  }
  final due = b.contract?.deliveryDueAt;
  if (due == null || b.deliveredDays >= b.planDays) return false;
  return due.isBefore(vnTime(addDays(vnDateOf(now), 1), 0, 0));
}

/// Something waits on the chef: a new request, a member's counter-offer, a
/// day due today, or a complaint without an answer.
bool chefNeedsAction(BookingDto b, DateTime now) => switch (b.status) {
      BookingStatus.requested => true,
      BookingStatus.negotiating =>
        b.openOffer?.proposedBy == BookingParty.member,
      BookingStatus.active => dueToday(b, now),
      BookingStatus.disputed =>
        b.complaint != null && b.complaint!.chefResponse == null,
      _ => false,
    };

/// Something waits on the member: the chef's offer or the payment.
bool memberNeedsAction(BookingDto b) =>
    b.status == BookingStatus.awaitingPayment ||
    (b.status == BookingStatus.negotiating &&
        b.openOffer?.proposedBy == BookingParty.chef);

/// The money outcome of a finished booking, member's point of view.
String? memberOutcome(BookingDto b) {
  final escrow = b.escrow;
  if (escrow == null) return null;
  return switch (escrow.status) {
    EscrowStatus.released => 'Đã chuyển cho chuyên gia',
    EscrowStatus.refunded =>
      'Đã hoàn ${formatVnd(escrow.refundedAmount)} về tài khoản thanh toán',
    EscrowStatus.partiallyRefunded =>
      'Hoàn một phần ${formatVnd(escrow.refundedAmount)}',
    EscrowStatus.frozen => 'Tiền đang tạm giữ do khiếu nại',
    EscrowStatus.held => null,
  };
}

/// "Yêu cầu mới · Đang thực hiện · Đang giữ (đ)" in Tôi › Chuyên gia.
typedef ChefBookingStats = ({
  int newRequests,
  int inProgress,
  int heldNet,
  int needsAction,
});

ChefBookingStats chefBookingStats(List<BookingDto> inbox, DateTime now) => (
      newRequests:
          inbox.where((b) => b.status == BookingStatus.requested).length,
      // The same bookings as the inbox's "Đang thực hiện" tab.
      inProgress: inbox
          .where((b) => InboxTab.of(b.status) == InboxTab.inProgress)
          .length,
      heldNet: inbox.fold(0, (sum, b) {
        final e = b.escrow;
        if (e == null || e.status != EscrowStatus.held) return sum;
        return sum + e.amount - platformFee(e.amount);
      }),
      needsAction: inbox.where((b) => chefNeedsAction(b, now)).length,
    );
