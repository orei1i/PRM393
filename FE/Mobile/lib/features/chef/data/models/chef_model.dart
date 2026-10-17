// lib/features/chef/data/models/chef_model.dart
//
// GET /chefs?q=&specialty=   → [ChefDto]   (list omits bio / certificates)
// GET /chefs/{id}            → ChefDto
// { "id": 3, "userId": 12, "fullName": "Lê Quang Tâm", "headline": "…",
//   "specialty": "Ẩm thực chay Việt",                // SQL keeps one; a list is accepted too
//   "rating": 4.9, "reviewCount": 212, "yearsExperience": 15, "city": "TP. Hồ Chí Minh",
//   "consultCount": 640,
//   "pricePerDay": 150000, "feedbackPricePerDay": 180000,   // proposed chef_profiles columns
//   "minPlanDays": 3, "maxPlanDays": 30, "acceptingBookings": true,
//   "bio": "…", "certificates": ["…"] }
// Services and time slots are gone (plan D15a); legacy `services`,
// `availableSlots` and `startingPriceVnd` are ignored.
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/chef.dart';

class ChefDto {
  const ChefDto({
    required this.id,
    required this.fullName,
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

  factory ChefDto.fromJson(Map<String, dynamic> json) {
    final specialty = json['specialty'];
    int orDefault(Object? value, int fallback) {
      final n = readInt(value);
      return n > 0 ? n : fallback;
    }

    final pricePerDay = orDefault(json['pricePerDay'], 0);
    return ChefDto(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString(),
      fullName: (json['fullName'] ?? json['name']) as String? ?? '',
      headline: json['headline'] as String? ?? '',
      specialties: json['specialties'] is List<Object?>
          ? readStringList(json['specialties'])
          : [if (specialty is String && specialty.isNotEmpty) specialty],
      rating: readDouble(json['rating']),
      reviewCount: readInt(json['reviewCount']),
      yearsExperience: readInt(json['yearsExperience']),
      city: json['city'] as String? ?? '',
      pricePerDay: pricePerDay,
      feedbackPricePerDay: orDefault(json['feedbackPricePerDay'], pricePerDay),
      minPlanDays: orDefault(json['minPlanDays'], 3),
      maxPlanDays: orDefault(json['maxPlanDays'], 30),
      acceptingBookings: json['acceptingBookings'] as bool? ?? true,
      bio: json['bio'] as String? ?? '',
      consultCount: readInt(json['consultCount']),
      certificates: readStringList(json['certificates']),
    );
  }

  final String id;
  final String? userId;
  final String fullName;
  final String headline;
  final List<String> specialties;
  final double rating;
  final int reviewCount;
  final int yearsExperience;
  final String city;
  final int pricePerDay;
  final int feedbackPricePerDay;
  final int minPlanDays;
  final int maxPlanDays;
  final bool acceptingBookings;
  final String bio;
  final int consultCount;
  final List<String> certificates;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (userId != null) 'userId': userId,
        'fullName': fullName,
        'headline': headline,
        'specialties': specialties,
        'rating': rating,
        'reviewCount': reviewCount,
        'yearsExperience': yearsExperience,
        'city': city,
        'pricePerDay': pricePerDay,
        'feedbackPricePerDay': feedbackPricePerDay,
        'minPlanDays': minPlanDays,
        'maxPlanDays': maxPlanDays,
        'acceptingBookings': acceptingBookings,
        'bio': bio,
        'consultCount': consultCount,
        'certificates': certificates,
      };

  Chef toEntity() => Chef(
        id: id,
        userId: userId,
        name: fullName,
        headline: headline,
        specialties: specialties,
        rating: rating,
        reviewCount: reviewCount,
        yearsExperience: yearsExperience,
        city: city,
        pricePerDay: pricePerDay,
        feedbackPricePerDay: feedbackPricePerDay,
        minPlanDays: minPlanDays,
        maxPlanDays: maxPlanDays,
        acceptingBookings: acceptingBookings,
        bio: bio,
        consultCount: consultCount,
        certificates: certificates,
      );
}
