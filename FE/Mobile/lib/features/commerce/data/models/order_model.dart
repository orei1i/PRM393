// lib/features/commerce/data/models/order_model.dart
//
// A booking payment ("Đặt chuyên gia"): accepting an offer creates the
// contract and an `orders` row with `booking_id` (`orders.service_id`
// becomes nullable, services are deprecated). Paying it funds the escrow.
//
// OrderDto — GET /orders/{id}, POST /bookings/{id}/payments
// { "id": "ord_601", "userId": "u_me", "bookingId": "b_ma_thuha_active", "amount": 840000,
//   "status": "Pending" | "Paid" | "Cancelled" | "Refunded" | "PartiallyRefunded",
//   "createdAt": "…",
//   "booking": { "id": "b_ma_thuha_active", "chefId": "u_thu_ha", "chefName": "ThS. DD Phạm Thu Hà",
//                "bookingType": "OneShot", "planDays": 7, "startDate": "2026-10-15",
//                "endDate": "2026-10-21", "status": "Active" },
//   "payment": PaymentDto | null,          // the latest attempt
//   "escrow": EscrowHoldDto | null }       // null until paid
import '../../../../core/utils/json_helpers.dart';
import '../../../booking/data/models/booking_models.dart';
import '../../../booking/domain/booking_enums.dart';
import '../../domain/commerce_status.dart';
import 'payment_model.dart';

/// The booking an order pays for (computed by BE from chef_bookings +
/// booking_contracts + users).
class OrderBookingSummary {
  const OrderBookingSummary({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.bookingType,
    required this.planDays,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  factory OrderBookingSummary.fromJson(Map<String, dynamic> json) =>
      OrderBookingSummary(
        id: json['id']?.toString() ?? '',
        chefId: json['chefId']?.toString() ?? '',
        chefName: json['chefName'] as String? ?? '',
        bookingType: BookingType.fromApi(json['bookingType']),
        planDays: readInt(json['planDays']),
        startDate: readDate(json['startDate']),
        endDate: readDate(json['endDate']),
        status: BookingStatus.fromApi(json['status']),
      );

  final String id;
  final String chefId;
  final String chefName;
  final BookingType bookingType;
  final int planDays;
  final DateTime startDate;
  final DateTime endDate;
  final BookingStatus status;

  /// "Thực đơn 10 ngày".
  String get title => 'Thực đơn $planDays ngày';
}

class OrderDto {
  const OrderDto({
    required this.id,
    required this.userId,
    required this.bookingId,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.booking,
    this.payment,
    this.escrow,
  });

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    final booking = readMap(json['booking']);
    return OrderDto(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      bookingId:
          json['bookingId']?.toString() ?? booking['id']?.toString() ?? '',
      amount: readInt(json['amount']),
      status: OrderStatus.fromApi(json['status']),
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      booking: OrderBookingSummary.fromJson(booking),
      payment: PaymentDto.fromJsonValue(json['payment']),
      escrow: EscrowHoldDto.fromJsonValue(json['escrow']),
    );
  }

  final String id;
  final String userId;
  final String bookingId;

  /// = contract price (VND).
  final int amount;
  final OrderStatus status;
  final DateTime createdAt;
  final OrderBookingSummary booking;

  /// The latest payment attempt (a new QR replaces an expired/failed one).
  final PaymentDto? payment;

  /// The escrow hold this order funded; null until paid.
  final EscrowHoldDto? escrow;
}
