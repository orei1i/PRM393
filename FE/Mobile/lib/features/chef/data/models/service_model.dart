// lib/features/chef/data/models/service_model.dart
//
// ServiceDto (services; description / durationMinutes / contentUrl are
// proposed columns, all optional):
// { "id": 12, "chefId": 3, "title": "Tư vấn thực đơn gia đình 7 ngày", "type": "Consult",
//   "price": 350000, "description": "Gọi video 60 phút…", "durationMinutes": 60,
//   "contentUrl": null }
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/chef.dart';

class ServiceDto {
  const ServiceDto({
    required this.id,
    required this.chefId,
    required this.title,
    required this.type,
    required this.price,
    this.description = '',
    this.durationMinutes,
    this.contentUrl,
  });

  factory ServiceDto.fromJson(Map<String, dynamic> json) {
    final minutes = readInt(json['durationMinutes']);
    final url = json['contentUrl'] as String?;
    return ServiceDto(
      id: json['id']?.toString() ?? '',
      chefId: json['chefId']?.toString() ?? '',
      title: (json['title'] ?? json['name']) as String? ?? '',
      type: ServiceType.fromApi(json['type']),
      price: readInt(json['price'] ?? json['priceVnd']),
      description: json['description'] as String? ?? '',
      durationMinutes: minutes > 0 ? minutes : null,
      contentUrl: url == null || url.isEmpty ? null : url,
    );
  }

  final String id;
  final String chefId;
  final String title;
  final ServiceType type;
  final int price;
  final String description;
  final int? durationMinutes;
  final String? contentUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chefId': chefId,
        'title': title,
        'type': type.apiValue,
        'price': price,
        'description': description,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (contentUrl != null) 'contentUrl': contentUrl,
      };

  ChefService toEntity() => ChefService(
        id: id,
        chefId: chefId,
        title: title,
        type: type,
        price: price,
        description: description,
        durationMinutes: durationMinutes,
        contentUrl: contentUrl,
      );
}

/// POST /chefs/me/services and PUT /chefs/me/services/{id}. Changing a price
/// never touches existing orders (`orders.amount` is a snapshot).
class ServiceRequestDto {
  const ServiceRequestDto({
    required this.title,
    required this.type,
    required this.price,
    this.description,
    this.durationMinutes,
    this.contentUrl,
  });

  final String title;
  final ServiceType type;
  final int price;
  final String? description;
  final int? durationMinutes;
  final String? contentUrl;

  Map<String, dynamic> toJson() => {
        'title': title,
        'type': type.apiValue,
        'price': price,
        'description': description,
        'durationMinutes': type == ServiceType.consult ? durationMinutes : null,
        'contentUrl': type.isPackage ? contentUrl : null,
      };
}
