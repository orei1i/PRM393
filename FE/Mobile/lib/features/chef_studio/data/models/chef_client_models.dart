// lib/features/chef_studio/data/models/chef_client_models.dart
//
// GET /chefs/me/clients?status=   → [ChefClientDto]   (role Chef only)
// GET /chefs/me/clients/{userId}  → ChefClientDto
// No table of its own: computed by BE from orders + access_grants +
// consultations for the signed-in chef's services (Paid or Refunded orders).
// {
//   "userId": 7, "fullName": "Lan Phương",
//   "status": "Active",                    // Active | ExpiringSoon | Ended
//   "packages": [ OrderDto … ],            // with accessGrant + consultation
//   "health": { "goal": "lose_weight", "bmi": 24.1, "heightCm": 158,
//               "weightKg": 60, "allergies": ["peanut"],
//               "dietaryRestrictions": ["low_sodium"] } | null,
//   "lastSuggestion": { "id": "sg_…", "dishName": "…", "slot": "dinner",
//                       "createdAt": "…" } | null
// }
// `health` is what the member shares with a chef by buying a package
// (read-only for the chef); null when they shared nothing.
import '../../../../core/utils/json_helpers.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../meal_planner/domain/entities/health_profile.dart';
import '../../domain/chef_client_rules.dart';

class ClientHealthDto {
  const ClientHealthDto({
    required this.goal,
    this.bmi,
    this.heightCm,
    this.weightKg,
    this.allergies = const [],
    this.dietaryRestrictions = const [],
  });

  factory ClientHealthDto.fromJson(Map<String, dynamic> json) =>
      ClientHealthDto(
        goal: HealthGoal.fromApi(json['goal'] as String?),
        bmi: json['bmi'] == null ? null : readDouble(json['bmi']),
        heightCm:
            json['heightCm'] == null ? null : readDouble(json['heightCm']),
        weightKg:
            json['weightKg'] == null ? null : readDouble(json['weightKg']),
        allergies: readStringList(json['allergies']),
        dietaryRestrictions: readStringList(json['dietaryRestrictions']),
      );

  static ClientHealthDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? ClientHealthDto.fromJson(value) : null;

  final HealthGoal goal;
  final double? bmi;
  final double? heightCm;
  final double? weightKg;
  final List<String> allergies;
  final List<String> dietaryRestrictions;
}

/// The newest dish this chef suggested to the client.
class LastSuggestionDto {
  const LastSuggestionDto(
      {required this.id, required this.dishName, this.createdAt, this.slot});

  factory LastSuggestionDto.fromJson(Map<String, dynamic> json) =>
      LastSuggestionDto(
        id: json['id']?.toString() ?? '',
        dishName: json['dishName'] as String? ?? '',
        slot: json['slot'] as String?,
        createdAt: readDateTime(json['createdAt']),
      );

  static LastSuggestionDto? fromJsonValue(Object? value) =>
      value is Map<String, dynamic> ? LastSuggestionDto.fromJson(value) : null;

  final String id;
  final String dishName;
  final String? slot;
  final DateTime? createdAt;
}

/// A member who bought one of the chef's services.
class ChefClientDto {
  const ChefClientDto({
    required this.userId,
    required this.fullName,
    required this.status,
    required this.packages,
    this.health,
    this.lastSuggestion,
  });

  factory ChefClientDto.fromJson(Map<String, dynamic> json) {
    final packages = json['packages'] is List<Object?>
        ? (json['packages'] as List<Object?>)
            .whereType<Map<String, dynamic>>()
            .map(OrderDto.fromJson)
            .toList()
        : const <OrderDto>[];
    return ChefClientDto(
      userId: json['userId']?.toString() ?? '',
      fullName: (json['fullName'] ?? json['name']) as String? ?? 'Khách',
      // Computed by BE; derived here when an older server leaves it out.
      status: json['status'] == null
          ? clientBucketOf(packages, DateTime.now())
          : ClientBucket.fromApi(json['status']),
      packages: packages,
      health: ClientHealthDto.fromJsonValue(json['health']),
      lastSuggestion: LastSuggestionDto.fromJsonValue(json['lastSuggestion']),
    );
  }

  final String userId;
  final String fullName;
  final ClientBucket status;

  /// Orders for this chef's services, newest first.
  final List<OrderDto> packages;
  final ClientHealthDto? health;
  final LastSuggestionDto? lastSuggestion;
}
