// lib/features/commerce/domain/commerce_status.dart
//
// Wire values are exactly `apiValue` (D5). Parsers ignore case, spaces and
// underscores (`in_progress`, legacy lowercase `pending`) and fall back to
// the first value.

T _fromApi<T extends Enum>(
    List<T> values, String Function(T) wire, Object? value) {
  String fold(Object? v) =>
      (v?.toString() ?? '').replaceAll(RegExp(r'[\s_]'), '').toLowerCase();
  final raw = fold(value);
  return values.firstWhere((e) => fold(wire(e)) == raw,
      orElse: () => values.first);
}

/// `orders.status`.
enum OrderStatus {
  pending('Pending', 'Chờ thanh toán'),
  paid('Paid', 'Đã thanh toán'),
  cancelled('Cancelled', 'Đã huỷ'),
  refunded('Refunded', 'Đã hoàn tiền');

  const OrderStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static OrderStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `payments.status`.
enum PaymentStatus {
  pending('Pending', 'Chờ thanh toán'),
  paid('Paid', 'Đã thanh toán'),
  failed('Failed', 'Thất bại'),
  expired('Expired', 'Hết hạn'),
  refunded('Refunded', 'Đã hoàn tiền');

  const PaymentStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static PaymentStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `access_grants.status`.
enum GrantStatus {
  active('Active', 'Đang hiệu lực'),
  expired('Expired', 'Hết hạn'),
  revoked('Revoked', 'Đã thu hồi');

  const GrantStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static GrantStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}

/// `consultations.status`. A consult order creates its consultation in
/// [awaitingPayment], which holds the slot until the payment succeeds,
/// expires or the order is cancelled.
enum ConsultationStatus {
  awaitingPayment('AwaitingPayment', 'Chờ thanh toán'),
  pending('Pending', 'Chờ chuyên gia xác nhận'),
  confirmed('Confirmed', 'Đã xác nhận'),
  inProgress('InProgress', 'Đang tư vấn'),
  completed('Completed', 'Đã hoàn thành'),
  declined('Declined', 'Chuyên gia từ chối'),
  cancelled('Cancelled', 'Đã huỷ');

  const ConsultationStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Still on the calendar (paid or being paid, not finished).
  bool get isOpen =>
      this == awaitingPayment ||
      this == pending ||
      this == confirmed ||
      this == inProgress;

  static ConsultationStatus fromApi(Object? value) =>
      _fromApi(values, (e) => e.apiValue, value);
}
