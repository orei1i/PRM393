// lib/features/commerce/data/models/consultation_model.dart
//
// ConsultationDto (consultations + proposed note columns + joins, computed by BE):
// { "id": 31, "orderId": 501, "chefId": 3, "chefName": "Lê Quang Tâm",
//   "buyer": { "id": 7, "fullName": "Minh Anh" }, "serviceId": 12,
//   "serviceTitle": "…", "durationMinutes": 60, "amount": 350000,
//   "startAt": "…", "status": "Pending", "buyerNote": "…", "chefNotes": null,
//   "declineReason": null, "startedAt": null, "completedAt": null, "createdAt": "…" }
//
// The pre-payment fields (`scheduledAt`, `packageName`, `priceVnd`, `note`)
// are still read so an older server keeps working.
import '../../../../core/utils/json_helpers.dart';
import '../../domain/commerce_status.dart';

/// `{ id, fullName }` of a buyer (chef views) — computed by BE.
class PersonSummary {
  const PersonSummary({required this.id, required this.fullName});

  factory PersonSummary.fromJson(Map<String, dynamic> json) => PersonSummary(
        id: json['id']?.toString() ?? '',
        fullName: (json['fullName'] ?? json['name']) as String? ?? 'Khách',
      );

  static PersonSummary? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? PersonSummary.fromJson(value) : null;

  final String id;
  final String fullName;

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName};
}

class ConsultationDto {
  const ConsultationDto({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.serviceTitle,
    required this.durationMinutes,
    required this.amount,
    required this.startAt,
    required this.status,
    this.orderId,
    this.serviceId,
    this.buyer,
    this.buyerNote,
    this.chefNotes,
    this.declineReason,
    this.startedAt,
    this.completedAt,
    this.createdAt,
  });

  factory ConsultationDto.fromJson(Map<String, dynamic> json) {
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
    return ConsultationDto(
      id: json['id']?.toString() ?? '',
      orderId: json['orderId']?.toString(),
      chefId: json['chefId']?.toString() ?? '',
      chefName: json['chefName'] as String? ?? '',
      buyer: PersonSummary.fromJsonValue(json['buyer']),
      serviceId: json['serviceId']?.toString(),
      serviceTitle:
          (json['serviceTitle'] ?? json['packageName']) as String? ?? '',
      durationMinutes: readInt(json['durationMinutes']),
      amount: readInt(json['amount'] ?? json['priceVnd']),
      startAt: readDateTime(json['startAt'] ?? json['scheduledAt']) ??
          DateTime.now(),
      status: ConsultationStatus.fromApi(json['status']),
      buyerNote: text(json['buyerNote'] ?? json['note']),
      chefNotes: text(json['chefNotes']),
      declineReason: text(json['declineReason']),
      startedAt: readDateTime(json['startedAt']),
      completedAt: readDateTime(json['completedAt']),
      createdAt: readDateTime(json['createdAt']),
    );
  }

  final String id;
  final String? orderId;
  final String chefId;
  final String chefName;
  final PersonSummary? buyer;
  final String? serviceId;
  final String serviceTitle;
  final int durationMinutes;
  final int amount;
  final DateTime startAt;
  final ConsultationStatus status;
  final String? buyerNote;
  final String? chefNotes;
  final String? declineReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));

  /// Open and not over yet: "Sắp tới" for the buyer.
  bool isUpcoming(DateTime now) => status.isOpen && endAt.isAfter(now);

  /// Buyer cancel rule: while the chef hasn't confirmed, or confirmed and at
  /// least 24 h before the appointment. Unpaid ones are cancelled as orders.
  bool canBuyerCancel(DateTime now) =>
      status == ConsultationStatus.pending ||
      (status == ConsultationStatus.confirmed &&
          !startAt.isBefore(now.add(const Duration(hours: 24))));
}
