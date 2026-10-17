// lib/features/commerce/data/models/payment_model.dart
//
// PaymentDto (payments; amount = orders.amount, expiresAt is a proposed column):
// { "id": 901, "orderId": 501, "provider": "PaymentOS", "transactionRef": "VL2610150001",
//   "qrCodeUrl": "https://…/qr/VL2610150001.png", "status": "Pending", "paidAt": null,
//   "amount": 1500000, "expiresAt": "…", "createdAt": "…" }
// Access grants are deprecated: a paid booking order funds an escrow hold
// instead (booking/data/models/booking_models.dart).
import '../../../../core/utils/json_helpers.dart';
import '../../domain/commerce_status.dart';

class PaymentDto {
  const PaymentDto({
    required this.id,
    required this.orderId,
    required this.transactionRef,
    required this.status,
    required this.amount,
    this.provider = 'PaymentOS',
    this.qrCodeUrl,
    this.paidAt,
    this.expiresAt,
    this.createdAt,
  });

  factory PaymentDto.fromJson(Map<String, dynamic> json) => PaymentDto(
        id: json['id']?.toString() ?? '',
        orderId: json['orderId']?.toString() ?? '',
        provider: json['provider'] as String? ?? 'PaymentOS',
        transactionRef: json['transactionRef']?.toString() ?? '',
        qrCodeUrl: json['qrCodeUrl'] as String?,
        status: PaymentStatus.fromApi(json['status']),
        paidAt: readDateTime(json['paidAt']),
        amount: readInt(json['amount']),
        expiresAt: readDateTime(json['expiresAt']),
        createdAt: readDateTime(json['createdAt']),
      );

  static PaymentDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? PaymentDto.fromJson(value) : null;

  final String id;
  final String orderId;
  final String provider;
  final String transactionRef;
  final String? qrCodeUrl;
  final PaymentStatus status;
  final DateTime? paidAt;
  final int amount;
  final DateTime? expiresAt;
  final DateTime? createdAt;
}
