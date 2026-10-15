// lib/features/chef/domain/entities/chef.dart

enum ConsultMode {
  online('online', 'Online qua video'),
  atHome('at_home', 'Tại nhà bạn');

  const ConsultMode(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static ConsultMode fromApi(String? value) => values
      .firstWhere((m) => m.apiValue == value, orElse: () => ConsultMode.online);
}

class ConsultPackage {
  const ConsultPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.priceVnd,
    required this.mode,
  });

  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final int priceVnd;
  final ConsultMode mode;
}

/// A member verified by an admin (web console › Duyệt chuyên gia).
class Chef {
  const Chef({
    required this.id,
    required this.name,
    required this.headline,
    required this.specialties,
    required this.rating,
    required this.reviewCount,
    required this.yearsExperience,
    required this.city,
    required this.startingPriceVnd,
    this.bio = '',
    this.consultCount = 0,
    this.certificates = const [],
    this.packages = const [],
    this.availableSlots = const [],
  });

  final String id;
  final String name;
  final String headline;
  final List<String> specialties;
  final double rating;
  final int reviewCount;
  final int yearsExperience;
  final String city;
  final int startingPriceVnd;

  // Detail-only fields (empty in the directory list).
  final String bio;
  final int consultCount;
  final List<String> certificates;
  final List<ConsultPackage> packages;
  final List<DateTime> availableSlots;
}

enum ConsultationStatus {
  pending('pending', 'Chờ chuyên gia xác nhận'),
  confirmed('confirmed', 'Đã xác nhận'),
  completed('completed', 'Đã hoàn thành'),
  cancelled('cancelled', 'Đã huỷ');

  const ConsultationStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get isUpcoming => this == pending || this == confirmed;

  static ConsultationStatus fromApi(String? value) =>
      values.firstWhere((s) => s.apiValue == value,
          orElse: () => ConsultationStatus.pending);
}

class Consultation {
  const Consultation({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.packageName,
    required this.priceVnd,
    required this.durationMinutes,
    required this.mode,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
    this.note,
  });

  final String id;
  final String chefId;
  final String chefName;
  final String packageName;
  final int priceVnd;
  final int durationMinutes;
  final ConsultMode mode;
  final DateTime scheduledAt;
  final ConsultationStatus status;
  final DateTime createdAt;
  final String? note;
}
