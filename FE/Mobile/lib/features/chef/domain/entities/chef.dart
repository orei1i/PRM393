// lib/features/chef/domain/entities/chef.dart

/// `services.type`. Wire values are exactly [apiValue]; the parser ignores
/// case, spaces and underscores, so `VipMenu` and `VIP_MENU` both read as
/// [vipMenu]. Unknown values read as [consult].
enum ServiceType {
  consult('Consult', 'Tư vấn 1–1'),
  course('Course', 'Khoá học'),
  vipMenu('VIP Menu', 'Thực đơn VIP');

  const ServiceType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Course / VIP Menu: bought once, then opened as content.
  bool get isPackage => this != consult;

  /// How long a paid package stays open (access-grant rule, mirrored from
  /// the BE). Consults expire 24 h after the appointment instead.
  int? get accessDays => switch (this) {
        consult => null,
        course => 180,
        vipMenu => 30,
      };

  static String _fold(Object? value) =>
      (value?.toString() ?? '').replaceAll(RegExp(r'[\s_]'), '').toLowerCase();

  static ServiceType fromApi(Object? value) {
    final raw = _fold(value);
    return values.firstWhere((t) => _fold(t.apiValue) == raw,
        orElse: () => consult);
  }
}

/// A row of `services`: what a chef sells (1–1 consult, course, VIP menu).
class ChefService {
  const ChefService({
    required this.id,
    required this.chefId,
    required this.title,
    required this.type,
    required this.price,
    this.description = '',
    this.durationMinutes,
    this.contentUrl,
  });

  final String id;
  final String chefId;
  final String title;
  final ServiceType type;

  /// Integer VND.
  final int price;
  final String description;

  /// Consult only.
  final int? durationMinutes;

  /// Course / VIP Menu only; sent to the owner and to buyers with access.
  final String? contentUrl;
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
    this.userId,
    this.bio = '',
    this.consultCount = 0,
    this.certificates = const [],
    this.services = const [],
    this.availableSlots = const [],
    this.bookedSlots = const [],
  });

  /// `chef_profiles.id`.
  final String id;

  /// `chef_profiles.user_id`: the account that owns this profile.
  final String? userId;
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
  final List<ChefService> services;
  final List<DateTime> availableSlots;

  /// Slots of the chef's calendar someone already holds: shown greyed out
  /// ("Đã kín") next to [availableSlots].
  final List<DateTime> bookedSlots;

  List<ChefService> get consultServices =>
      services.where((s) => s.type == ServiceType.consult).toList();
}
