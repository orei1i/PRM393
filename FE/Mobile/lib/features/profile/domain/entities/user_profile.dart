// lib/features/profile/domain/entities/user_profile.dart
import '../../../../core/session/user_role.dart';

/// Mirrors `DomainLayer.Enums.GeneralEnum.UserStatusEnum` on the backend.
enum UserStatus {
  active('Đang hoạt động'),
  inactive('Chưa kích hoạt'),
  locked('Tạm khoá'),
  banned('Bị cấm');

  const UserStatus(this.label);
  final String label;
}

enum ChefApplicationStatus {
  none('none'),
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const ChefApplicationStatus(this.apiValue);
  final String apiValue;

  static ChefApplicationStatus fromApi(String? value) =>
      values.firstWhere((s) => s.apiValue == value,
          orElse: () => ChefApplicationStatus.none);
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.status,
    required this.signedInWithGoogle,
    required this.createdAt,
    this.postCount = 0,
    this.likesReceived = 0,
    this.savedCount = 0,
    this.chefApplication = ChefApplicationStatus.none,
    this.chefRejectReason,
  });

  final String id;
  final String email;
  final String fullName;
  final String phone;

  /// `users.role`: Admin / User / Chef (legacy `Member` reads as User).
  final UserRole role;
  final UserStatus status;
  final bool signedInWithGoogle;
  final DateTime createdAt;
  final int postCount;
  final int likesReceived;
  final int savedCount;
  final ChefApplicationStatus chefApplication;
  final String? chefRejectReason;

  bool get isVerifiedChef =>
      role == UserRole.chef ||
      chefApplication == ChefApplicationStatus.approved;
}

class ChefApplicationRequest {
  const ChefApplicationRequest({
    required this.specialties,
    required this.yearsExperience,
    required this.city,
    required this.bio,
    required this.certificates,
  });

  final List<String> specialties;
  final int yearsExperience;
  final String city;
  final String bio;

  /// Certificate titles; files are uploaded to Cloudinary separately.
  final List<String> certificates;

  Map<String, dynamic> toJson() => {
        'specialties': specialties,
        'yearsExperience': yearsExperience,
        'city': city,
        'bio': bio,
        'certificates': certificates,
      };
}
