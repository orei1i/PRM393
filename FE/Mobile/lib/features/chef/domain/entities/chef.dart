// lib/features/chef/domain/entities/chef.dart

/// A member verified by an admin (web console › Duyệt chuyên gia). Members
/// book a chef to design an N-day meal plan ("Thiết kế thực đơn theo yêu
/// cầu"); the listed prices are a starting point, the final price is agreed
/// in the booking chat.
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
    required this.pricePerDay,
    required this.feedbackPricePerDay,
    this.userId,
    this.minPlanDays = 3,
    this.maxPlanDays = 30,
    this.acceptingBookings = true,
    this.bio = '',
    this.consultCount = 0,
    this.certificates = const [],
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

  /// `chef_profiles.price_per_day`: one-shot plans ("Giao trọn một lần").
  final int pricePerDay;

  /// `chef_profiles.feedback_price_per_day`: plans with daily feedback.
  final int feedbackPricePerDay;
  final int minPlanDays;
  final int maxPlanDays;

  /// `chef_profiles.accepting_bookings`.
  final bool acceptingBookings;

  // Detail-only fields (empty in the directory list).
  final String bio;

  /// Plans designed so far.
  final int consultCount;
  final List<String> certificates;

  /// The lowest listed price per day ("Từ 120.000đ/ngày").
  int get startingPriceVnd =>
      pricePerDay < feedbackPricePerDay ? pricePerDay : feedbackPricePerDay;

  /// The listed price per day for a plan type.
  int priceFor({required bool dailyFeedback}) =>
      dailyFeedback ? feedbackPricePerDay : pricePerDay;
}
