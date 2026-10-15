// lib/features/chef/data/models/chef_model.dart
//
// GET /chefs?q=&specialty=   → [ChefDto]   (list omits bio/services/slots)
// GET /chefs/{id}            → ChefDto with "services" and "availableSlots"
//                              (ISO-8601, UTC; slots held by unpaid orders are
//                              already left out) and, optionally,
//                              "bookedSlots": the chef's slots someone already
//                              holds (paid or an unpaid hold), shown greyed out
// SQL `chef_profiles` has a single `specialty`; the list form is accepted too.
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/chef.dart';
import 'service_model.dart';

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
    required this.startingPriceVnd,
    this.userId,
    this.bio = '',
    this.consultCount = 0,
    this.certificates = const [],
    this.services = const [],
    this.availableSlots = const [],
    this.bookedSlots = const [],
  });

  factory ChefDto.fromJson(Map<String, dynamic> json) {
    final services = json['services'] is List<Object?>
        ? (json['services'] as List<Object?>)
            .whereType<Map<String, dynamic>>()
            .map(ServiceDto.fromJson)
            .toList()
        : const <ServiceDto>[];
    List<DateTime> slots(Object? value) => value is List<Object?>
        ? value.map(readDateTime).whereType<DateTime>().toList()
        : const [];
    final specialty = json['specialty'];
    final startingPrice = readInt(json['startingPriceVnd']);
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
      startingPriceVnd: startingPrice > 0 || services.isEmpty
          ? startingPrice
          : services.map((s) => s.price).reduce((a, b) => a < b ? a : b),
      bio: json['bio'] as String? ?? '',
      consultCount: readInt(json['consultCount']),
      certificates: readStringList(json['certificates']),
      services: services,
      availableSlots: slots(json['availableSlots']),
      bookedSlots: slots(json['bookedSlots']),
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
  final int startingPriceVnd;
  final String bio;
  final int consultCount;
  final List<String> certificates;
  final List<ServiceDto> services;
  final List<DateTime> availableSlots;
  final List<DateTime> bookedSlots;

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
        'startingPriceVnd': startingPriceVnd,
        'bio': bio,
        'consultCount': consultCount,
        'certificates': certificates,
        'services': services.map((s) => s.toJson()).toList(),
        'availableSlots':
            availableSlots.map((d) => d.toUtc().toIso8601String()).toList(),
        'bookedSlots':
            bookedSlots.map((d) => d.toUtc().toIso8601String()).toList(),
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
        startingPriceVnd: startingPriceVnd,
        bio: bio,
        consultCount: consultCount,
        certificates: certificates,
        services: services.map((s) => s.toEntity()).toList(),
        availableSlots: availableSlots,
        bookedSlots: bookedSlots,
      );
}
