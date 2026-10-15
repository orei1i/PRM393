// lib/features/commerce/data/models/order_model.dart
//
// POST /orders  CreateOrderRequestDto (startAt / note: Consult only)
// { "serviceId": 12, "startAt": "2026-10-17T12:30:00Z", "note": "…" }
// OrderDto (orders + joins):
// { "id": 501, "userId": 7, "serviceId": 12, "amount": 350000, "status": "Pending", "createdAt": "…",
//   "service": { "id": 12, "title": "…", "type": "Consult", "chefId": 3, "chefName": "Lê Quang Tâm" },
//   "buyer": { "id": 7, "fullName": "Minh Anh" },            // chef views
//   "payment": PaymentDto | null, "accessGrant": AccessGrantDto | null,
//   "consultation": ConsultationDto | null }
// GET /services/{id}/content  ServiceContentDto (403 `no_access` without an Active grant)
// { "serviceId": 13, "title": "…", "type": "Course", "chefName": "…", "summary": "markdown…",
//   "contentUrl": "https://…", "accessExpiresAt": "…" }
import '../../../../core/utils/json_helpers.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../domain/commerce_status.dart';
import 'consultation_model.dart';
import 'payment_model.dart';

/// The ordered service as it was when bought (`orders.amount` is a snapshot,
/// and the service may have been edited or deleted since).
class OrderServiceSummary {
  const OrderServiceSummary({
    required this.id,
    required this.title,
    required this.type,
    required this.chefId,
    required this.chefName,
  });

  factory OrderServiceSummary.fromJson(Map<String, dynamic> json) =>
      OrderServiceSummary(
        id: json['id']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        type: ServiceType.fromApi(json['type']),
        chefId: json['chefId']?.toString() ?? '',
        chefName: json['chefName'] as String? ?? '',
      );

  final String id;
  final String title;
  final ServiceType type;
  final String chefId;
  final String chefName;
}

class OrderDto {
  const OrderDto({
    required this.id,
    required this.userId,
    required this.serviceId,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.service,
    this.buyer,
    this.payment,
    this.accessGrant,
    this.consultation,
  });

  factory OrderDto.fromJson(Map<String, dynamic> json) {
    final service = readMap(json['service']);
    return OrderDto(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      serviceId:
          json['serviceId']?.toString() ?? service['id']?.toString() ?? '',
      amount: readInt(json['amount']),
      status: OrderStatus.fromApi(json['status']),
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      service: OrderServiceSummary.fromJson(service),
      buyer: PersonSummary.fromJsonValue(json['buyer']),
      payment: PaymentDto.fromJsonValue(json['payment']),
      accessGrant: AccessGrantDto.fromJsonValue(json['accessGrant']),
      consultation: json['consultation'] is Map<String, dynamic>
          ? ConsultationDto.fromJson(
              json['consultation'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String userId;
  final String serviceId;
  final int amount;
  final OrderStatus status;
  final DateTime createdAt;
  final OrderServiceSummary service;
  final PersonSummary? buyer;

  /// The latest payment attempt (a new QR replaces an expired/failed one).
  final PaymentDto? payment;
  final AccessGrantDto? accessGrant;
  final ConsultationDto? consultation;

  ServiceType get type => service.type;

  /// Paid package whose content can be opened right now.
  bool canOpenContent(DateTime now) =>
      status == OrderStatus.paid &&
      type.isPackage &&
      accessGrant?.statusAt(now) == GrantStatus.active;
}

class CreateOrderRequestDto {
  const CreateOrderRequestDto(
      {required this.serviceId, this.startAt, this.note});

  final String serviceId;
  final DateTime? startAt;
  final String? note;

  Map<String, dynamic> toJson() => {
        'serviceId': apiId(serviceId),
        if (startAt != null) 'startAt': startAt!.toUtc().toIso8601String(),
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
      };
}

class ServiceContentDto {
  const ServiceContentDto({
    required this.serviceId,
    required this.title,
    required this.type,
    required this.chefName,
    required this.summary,
    this.contentUrl,
    this.accessExpiresAt,
  });

  factory ServiceContentDto.fromJson(Map<String, dynamic> json) =>
      ServiceContentDto(
        serviceId: json['serviceId']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        type: ServiceType.fromApi(json['type']),
        chefName: json['chefName'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        contentUrl: json['contentUrl'] as String?,
        accessExpiresAt: readDateTime(json['accessExpiresAt']),
      );

  final String serviceId;
  final String title;
  final ServiceType type;
  final String chefName;

  /// Markdown.
  final String summary;
  final String? contentUrl;
  final DateTime? accessExpiresAt;
}
