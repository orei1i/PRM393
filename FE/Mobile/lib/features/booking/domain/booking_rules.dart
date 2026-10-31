// lib/features/booking/domain/booking_rules.dart
//
// Business rules of the chef meal-plan booking (plan D15, P5 "Rules"). The
// forms show these messages inline, the mock server enforces the same ones
// (400 / 409) and the web console uses the same numbers
// (FE/Web src/types/bookings.ts, src/types/payouts.ts).
import '../../../core/utils/formatters.dart';
import '../../chef_studio/domain/wallet_rules.dart';
import 'booking_enums.dart';

/// Asia/Ho_Chi_Minh is UTC+7 all year (no DST).
const vnOffset = Duration(hours: 7);

/// The VN wall clock of [instant]: a UTC [DateTime] whose fields read as
/// the time in Vietnam ("23:59, 22/10"), whatever the device time zone.
DateTime vnWall(DateTime instant) => instant.toUtc().add(vnOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// "23:59, 22/10/2026" in Vietnam time, whatever the device time zone.
String formatVnStamp(DateTime instant) {
  final w = vnWall(instant);
  return '${_two(w.hour)}:${_two(w.minute)}, ${_two(w.day)}/${_two(w.month)}/${w.year}';
}

/// "06:00 Thứ Sáu 24/10" in Vietnam time.
String formatVnDeadline(DateTime instant) {
  final w = vnWall(instant);
  final date = DateTime(w.year, w.month, w.day);
  return '${_two(w.hour)}:${_two(w.minute)} ${weekdayLong(date)} ${formatDayMonth(date)}';
}

/// The VN calendar day of [instant], as a date-only [DateTime].
DateTime vnDateOf(DateTime instant) {
  final w = vnWall(instant);
  return DateTime(w.year, w.month, w.day);
}

/// The instant of a VN wall-clock time on [date] (only its y/m/d are read):
/// `vnTime(20/10, 6, 0)` → 2026-10-19T23:00:00Z.
DateTime vnTime(DateTime date, int hour, int minute) =>
    DateTime.utc(date.year, date.month, date.day, hour, minute)
        .subtract(vnOffset);

/// Date-only arithmetic that crosses month and year ends.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// endDate = startDate + planDays − 1.
DateTime planEndDate(DateTime startDate, int planDays) =>
    addDays(startDate, planDays - 1);

/// releaseAt = endDate 23:59 (Asia/Ho_Chi_Minh) + [holdDays] days.
DateTime escrowReleaseAt(DateTime endDate,
        {int holdDays = BookingRules.holdDays}) =>
    vnTime(addDays(endDate, holdDays), 23, 59);

/// The member pays within [window] of accepting an offer, and before the plan
/// starts: min(acceptedAt + window, startDate 00:00 VN).
DateTime paymentDeadline(DateTime acceptedAt, DateTime startDate,
    {Duration window = BookingRules.paymentWindow}) {
  final afterWindow = acceptedAt.toUtc().add(window);
  final start = vnTime(startDate, 0, 0);
  return afterWindow.isAfter(start) ? start : afterWindow;
}

/// OneShot: max(startDate 00:00, paidAt + 24 h). DailyFeedback: day 1 is due
/// at the daily send cutoff (06:00) of the start date.
DateTime deliveryDueAt(BookingType type, DateTime startDate, DateTime paidAt) {
  if (type == BookingType.dailyFeedback) {
    return vnTime(startDate, BookingRules.sendCutoffHour, 0);
  }
  final start = vnTime(startDate, 0, 0);
  final afterPayment = paidAt.toUtc().add(const Duration(hours: 24));
  return afterPayment.isAfter(start) ? afterPayment : start;
}

/// When day [dayIndex] (1-based) of a DailyFeedback plan is due: 06:00 VN on
/// that day.
DateTime dailySendDeadline(DateTime startDate, int dayIndex) =>
    vnTime(addDays(startDate, dayIndex - 1), BookingRules.sendCutoffHour, 0);

/// Day [dayIndex] of a DailyFeedback plan is past its send deadline.
bool dailySendOverdue(DateTime startDate, int dayIndex, DateTime now) =>
    now.isAfter(dailySendDeadline(startDate, dayIndex));

/// A plan day the member can give feedback on: it has started (VN calendar).
bool planDayStarted(DateTime date, DateTime now) =>
    !dateOnly(date).isAfter(vnDateOf(now));

/// "Thực đơn 10 ngày · Có phản hồi mỗi ngày" (wallet rows, cards).
String planTitle(int planDays, BookingType type) =>
    'Thực đơn $planDays ngày · ${type.label}';

/// "10 ngày · Có phản hồi mỗi ngày".
String planSummary(int planDays, BookingType type) =>
    '$planDays ngày · ${type.label}';

/// The money split of an admin decision on web `/disputes` (same rounding as
/// the wallet: the fee is rounded to whole đồng).
({int refund, int chefGross, int fee, int chefNet}) decisionOutcome(
    int price, ComplaintDecision decision,
    [int? refundAmount]) {
  final refund = switch (decision) {
    ComplaintDecision.refundMember => price,
    ComplaintDecision.split => (refundAmount ?? 0).clamp(0, price),
    ComplaintDecision.releaseToChef => 0,
  };
  final chefGross = price - refund;
  final fee = platformFee(chefGross);
  return (
    refund: refund,
    chefGross: chefGross,
    fee: fee,
    chefNet: chefGross - fee
  );
}

abstract final class BookingRules {
  static const minPlanDays = 3;
  static const maxPlanDays = 30;

  /// Chips on the booking form and the offer sheet.
  static const dayPresets = [3, 7, 10, 14, 30];
  static const minPrice = 100000;
  static const maxPrice = 50000000;
  static const maxOfferNote = 300;
  static const maxMessage = 1000;
  static const minNeeds = 20;
  static const maxNeeds = 2000;
  static const minDeclineReason = 10;
  static const minCancelReason = 5;
  static const minComplaintDescription = 30;
  static const maxComplaintDescription = 3000;
  static const maxEvidenceImages = 5;
  static const minChefResponse = 20;
  static const maxFeedbackBody = 500;
  static const maxDishName = 120;

  /// Smallest partial refund; it must also stay below the contract price.
  static const minPartialRefund = 1000;

  /// The member pays within this window after accepting an offer (and before
  /// the plan starts, see [paymentDeadline]), otherwise the booking expires.
  static const paymentWindow = Duration(hours: 48);

  /// `#expire` in the needs (mock): the payment window is 30 s.
  static const fastPaymentWindow = Duration(seconds: 30);

  /// Escrow is held until the plan's end date 23:59 + this many days.
  static const holdDays = 3;
  static const feeRate = kPlatformFeeRate;

  /// DailyFeedback: day N is due at 06:00 on day N; the member's feedback
  /// for day N is expected before 21:00.
  static const sendCutoffHour = 6;
  static const feedbackCutoffHour = 21;
  static const dailySendCutoff = '06:00';
  static const feedbackCutoff = '21:00';

  static String? planDays(int? value) =>
      value == null || value < minPlanDays || value > maxPlanDays
          ? 'Số ngày từ $minPlanDays đến $maxPlanDays.'
          : null;

  static String? price(int? value) =>
      value == null || value < minPrice || value > maxPrice
          ? 'Giá từ ${formatVnd(minPrice)} đến ${formatVnd(maxPrice)}.'
          : null;

  /// [today] is the VN calendar day; the plan starts tomorrow at the earliest.
  static String? startDate(DateTime? value, DateTime today) =>
      value == null || !dateOnly(value).isAfter(dateOnly(today))
          ? 'Ngày bắt đầu từ ngày mai trở đi.'
          : null;

  static String? needs(String value) {
    final n = value.trim().length;
    if (n < minNeeds) {
      return 'Mô tả nhu cầu ít nhất $minNeeds ký tự để chuyên gia hiểu bạn.';
    }
    return n > maxNeeds ? 'Tối đa ${formatInt(maxNeeds)} ký tự.' : null;
  }

  static String? budget(int? value) =>
      value != null && value < 0 ? 'Ngân sách không hợp lệ.' : null;

  static String? offerNote(String value) => value.trim().length > maxOfferNote
      ? 'Lời nhắn tối đa $maxOfferNote ký tự.'
      : null;

  static String? message(String value) {
    final n = value.trim().length;
    if (n == 0) return 'Nhập tin nhắn.';
    return n > maxMessage
        ? 'Tin nhắn tối đa ${formatInt(maxMessage)} ký tự.'
        : null;
  }

  static String? declineReason(String value) =>
      value.trim().length < minDeclineReason
          ? 'Lý do cần ít nhất $minDeclineReason ký tự.'
          : null;

  static String? cancelReason(String value) =>
      value.trim().length < minCancelReason
          ? 'Cho chuyên gia biết lý do (ít nhất $minCancelReason ký tự).'
          : null;

  static String? complaintDescription(String value) {
    final n = value.trim().length;
    if (n < minComplaintDescription) {
      return 'Mô tả chi tiết ít nhất $minComplaintDescription ký tự.';
    }
    return n > maxComplaintDescription
        ? 'Tối đa ${formatInt(maxComplaintDescription)} ký tự.'
        : null;
  }

  /// Evidence: at least one item; "Có nội dung ảnh hưởng sức khoẻ" needs at
  /// least one source link; at most [maxEvidenceImages] images.
  static String? evidence(
      ComplaintReason reason, Iterable<EvidenceKind> kinds) {
    final list = kinds.toList();
    if (reason == ComplaintReason.healthRisk &&
        !list.contains(EvidenceKind.link)) {
      return 'Hãy đính kèm nguồn (bài báo, tài liệu y khoa) chứng minh';
    }
    if (list.isEmpty) {
      return 'Thêm ít nhất 1 bằng chứng (liên kết nguồn hoặc ảnh).';
    }
    if (list.where((k) => k == EvidenceKind.image).length > maxEvidenceImages) {
      return 'Tối đa $maxEvidenceImages ảnh.';
    }
    return null;
  }

  /// Partial refund: 1.000đ ≤ amount < price.
  static String? partialRefund(int? amount, int price) {
    if (amount == null || amount < minPartialRefund) {
      return 'Nhập số tiền muốn hoàn (từ ${formatVnd(minPartialRefund)}).';
    }
    return amount >= price
        ? 'Phải nhỏ hơn giá hợp đồng ${formatVnd(price)} — muốn hoàn hết thì chọn "Hoàn toàn bộ".'
        : null;
  }

  static String? chefResponse(String value) =>
      value.trim().length < minChefResponse
          ? 'Phản hồi cần ít nhất $minChefResponse ký tự.'
          : null;

  static String? dishName(String value) {
    final n = value.trim().length;
    return n < 3 || n > maxDishName
        ? 'Tên món từ 3 đến $maxDishName ký tự.'
        : null;
  }

  static bool isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.contains('.');
  }

  static final _offPlatform = RegExp(
    r'zalo|sđt|sdt|số điện thoại|so dien thoai|chuyển khoản riêng|chuyen khoan rieng|'
    r'ck riêng|momo|(?:\+?84|0)\d{9}\b',
    caseSensitive: false,
  );

  /// Off-platform contact or payment ("zalo", "sđt", "chuyển khoản riêng",
  /// a phone number): the chat shows "Giao dịch ngoài VeganLife không được
  /// bảo vệ…".
  static bool mentionsOffPlatform(String text) => _offPlatform.hasMatch(text);
}
