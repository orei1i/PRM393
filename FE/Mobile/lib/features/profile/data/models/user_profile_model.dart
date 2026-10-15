// lib/features/profile/data/models/user_profile_model.dart
//
// Matches the backend `UserResponse` (ApplicationLayer.DTOs.Users) plus
// profile extras the mobile app needs from GET /users/me:
// { "id", "email", "fullName", "phone", "role", "status": 0, "authType": 1, "createdAt",
//   "stats": { "posts": 2, "likesReceived": 20, "saved": 2 },
//   "chefApplication": { "status": "pending", "rejectReason": null } }
//
// ASP.NET serialises enums as numbers unless JsonStringEnumConverter is
// registered, so `status`/`authType` accept both forms.
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/user_profile.dart';

class UserProfileDto {
  const UserProfileDto(this.json);

  factory UserProfileDto.fromJson(Map<String, dynamic> json) =>
      UserProfileDto(Map.of(json));

  final Map<String, dynamic> json;

  Map<String, dynamic> toJson() => json;

  static UserStatus _status(Object? value) => switch (value) {
        final num n when n >= 0 && n < UserStatus.values.length =>
          UserStatus.values[n.toInt()],
        final String s => UserStatus.values.firstWhere(
            (e) => e.name.toLowerCase() == s.toLowerCase(),
            orElse: () => UserStatus.active,
          ),
        _ => UserStatus.active,
      };

  static bool _isGoogle(Object? value) =>
      value == 1 || (value is String && value.toLowerCase() == 'google');

  UserProfile toEntity() {
    final stats = readMap(json['stats']);
    final chef = readMap(json['chefApplication']);
    return UserProfile(
      id: json['id']?.toString() ?? '',
      email: json['email'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: json['role'] as String? ?? 'Member',
      status: _status(json['status']),
      signedInWithGoogle: _isGoogle(json['authType']),
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      postCount: readInt(stats['posts']),
      likesReceived: readInt(stats['likesReceived']),
      savedCount: readInt(stats['saved']),
      chefApplication: ChefApplicationStatus.fromApi(chef['status'] as String?),
      chefRejectReason: chef['rejectReason'] as String?,
    );
  }
}

/// PUT /users/{id} — same shape as the backend `UpdateUserRequest`.
class UpdateUserRequestDto {
  const UpdateUserRequestDto({required this.fullName, this.phone});

  final String fullName;
  final String? phone;

  Map<String, dynamic> toJson() => {'fullName': fullName, 'phone': phone};
}
