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

/// `orders.status`. The only order left is a booking payment ("Đặt chuyên
/// gia"); "Hoàn một phần" comes from a Split complaint decision.
enum OrderStatus {
  pending('Pending', 'Chờ thanh toán'),
  paid('Paid', 'Đã thanh toán'),
  cancelled('Cancelled', 'Đã huỷ'),
  refunded('Refunded', 'Đã hoàn tiền'),
  partiallyRefunded('PartiallyRefunded', 'Hoàn một phần');

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
