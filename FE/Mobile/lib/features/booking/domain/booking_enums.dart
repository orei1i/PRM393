// lib/features/booking/domain/booking_enums.dart
//
// Wire values of the chef meal-plan booking (plan D15). They are exactly
// `apiValue` and match the web admin types (FE/Web src/types/bookings.ts).
// Parsers ignore case, spaces and underscores and fall back to the first
// value.

T _fromApi<T extends Enum>(
    List<T> values, String Function(T) wire, Object? value) {
  String fold(Object? v) =>
      (v?.toString() ?? '').replaceAll(RegExp(r'[\s_]'), '').toLowerCase();
  final raw = fold(value);
  return values.firstWhere((e) => fold(wire(e)) == raw,
      orElse: () => values.first);
}

/// `chef_bookings.booking_type`.
enum BookingType {
  oneShot('OneShot', 'Giao trọn kế hoạch một lần',
      'Chuyên gia gửi đủ các ngày trước khi kế hoạch bắt đầu.'),
  dailyFeedback('DailyFeedback', 'Có phản hồi mỗi ngày',
      'Mỗi tối bạn góp ý, chuyên gia chỉnh thực đơn ngày hôm sau.');

  const BookingType(this.apiValue, this.label, this.explanation);
  final String apiValue;
  final String label;
  final String explanation;

  static BookingType fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `chef_bookings.status`.
enum BookingStatus {
  requested('Requested', 'Chờ báo giá'),
  negotiating('Negotiating', 'Đang thoả thuận giá'),
  awaitingPayment('AwaitingPayment', 'Chờ thanh toán'),
  active('Active', 'Đang thực hiện'),
  ended('Ended', 'Đã kết thúc · chờ giải ngân'),
  disputed('Disputed', 'Đang khiếu nại'),
  completed('Completed', 'Hoàn tất'),
  resolved('Resolved', 'Đã xử lý khiếu nại'),
  declined('Declined', 'Chuyên gia từ chối'),
  cancelled('Cancelled', 'Đã huỷ'),
  expired('Expired', 'Quá hạn thanh toán');

  const BookingStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// "Đang diễn ra" in Lịch sử tư vấn.
  bool get isOngoing => const {
        requested,
        negotiating,
        awaitingPayment,
        active,
        ended,
        disputed,
      }.contains(this);

  /// Before the contract is paid: price can still be negotiated, the chef
  /// can decline and the member can cancel.
  bool get isBeforePayment =>
      this == requested || this == negotiating || this == awaitingPayment;

  /// Offers can be made (and answered).
  bool get canNegotiate => this == requested || this == negotiating;

  static BookingStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_offers.status`.
enum OfferStatus {
  open('Open', 'Đang chờ trả lời'),
  accepted('Accepted', 'Đã đồng ý'),
  rejected('Rejected', 'Bị từ chối'),
  superseded('Superseded', 'Đã có đề xuất mới'),
  withdrawn('Withdrawn', 'Đã rút lại');

  const OfferStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static OfferStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// Who wrote an offer, a message or a piece of evidence.
enum BookingParty {
  member('member', 'Thành viên'),
  chef('chef', 'Chuyên gia'),
  system('system', 'VeganLife');

  const BookingParty(this.apiValue, this.label);
  final String apiValue;
  final String label;

  BookingParty get other => this == member ? chef : member;

  static BookingParty fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `escrow_holds.status`.
enum EscrowStatus {
  held('Held', 'Đang giữ'),
  frozen('Frozen', 'Tạm giữ do khiếu nại'),
  released('Released', 'Đã chuyển cho chuyên gia'),
  refunded('Refunded', 'Đã hoàn cho thành viên'),
  partiallyRefunded('PartiallyRefunded', 'Hoàn một phần');

  const EscrowStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get isActive => this == held || this == frozen;

  static EscrowStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_complaints.reason`. Same wording as the web console.
enum ComplaintReason {
  notAsAgreed('not_as_agreed', 'Kế hoạch không đúng yêu cầu đã thoả thuận',
      'Không đúng thoả thuận'),
  healthRisk(
      'health_risk', 'Có nội dung ảnh hưởng sức khoẻ', 'Ảnh hưởng sức khoẻ'),
  lateOrMissing(
      'late_or_missing', 'Giao trễ hoặc thiếu ngày', 'Giao trễ / thiếu ngày'),
  allergen('allergen', 'Có món chứa chất tôi dị ứng', 'Chất gây dị ứng'),
  other('other', 'Khác', 'Khác');

  const ComplaintReason(this.apiValue, this.label, this.short);
  final String apiValue;
  final String label;
  final String short;

  static ComplaintReason fromApi(Object? value) {
    for (final r in values) {
      if (r.apiValue == value) return r;
    }
    return other;
  }
}

/// `booking_complaints.requested_outcome`.
enum RequestedOutcome {
  fullRefund('FullRefund', 'Hoàn toàn bộ'),
  partialRefund('PartialRefund', 'Hoàn một phần');

  const RequestedOutcome(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static RequestedOutcome fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_complaints.status`.
enum ComplaintStatus {
  open('Open', 'Chờ xử lý'),
  resolved('Resolved', 'Đã xử lý');

  const ComplaintStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ComplaintStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_complaints.decision` (taken by an admin on web `/disputes`).
enum ComplaintDecision {
  releaseToChef('ReleaseToChef', 'Chuyển toàn bộ cho chuyên gia'),
  refundMember('RefundMember', 'Hoàn toàn bộ cho thành viên'),
  split('Split', 'Hoàn một phần');

  const ComplaintDecision(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ComplaintDecision? fromApiOrNull(Object? value) {
    if (value == null) return null;
    return _fromApi(values, (e) => e.apiValue, value);
  }
}

/// `complaint_evidence.kind`.
enum EvidenceKind {
  link('Link', 'Liên kết'),
  image('Image', 'Ảnh');

  const EvidenceKind(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static EvidenceKind fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_plan_days.status`. A day without a row reads as "Chưa soạn".
enum PlanDayStatus {
  draft('Draft', 'Nháp'),
  sent('Sent', 'Đã gửi');

  const PlanDayStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static PlanDayStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_day_feedback.adherence` ("Bạn đã làm theo?").
enum Adherence {
  all('All', 'Đầy đủ', 'Làm theo đầy đủ'),
  partly('Partly', 'Một phần', 'Làm theo một phần'),
  none('None', 'Không', 'Không làm theo');

  const Adherence(this.apiValue, this.label, this.longLabel);
  final String apiValue;
  final String label;
  final String longLabel;

  static Adherence fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `booking_messages.kind`.
enum MessageKind {
  text('Text'),
  offer('Offer'),
  system('System'),
  attachment('Attachment');

  const MessageKind(this.apiValue);
  final String apiValue;

  static MessageKind fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// Goals a member can ask a chef for. The codes are the health-profile goal
/// codes (`lean_muscle`…); `gain_muscle` and `eat_clean` come from the web
/// seeds and read the same way.
const bookingGoalLabels = <String, String>{
  'lose_weight': 'Giảm cân',
  'maintain': 'Giữ cân',
  'lean_muscle': 'Tăng cơ',
  'gain_muscle': 'Tăng cơ',
  'gain_weight': 'Tăng cân',
  'eat_clean': 'Ăn lành mạnh',
};

/// The choices on the booking form, in display order.
const bookingGoalChoices = [
  'lose_weight',
  'maintain',
  'lean_muscle',
  'gain_weight',
  'eat_clean',
];

String bookingGoalLabel(String code) => bookingGoalLabels[code] ?? code;
