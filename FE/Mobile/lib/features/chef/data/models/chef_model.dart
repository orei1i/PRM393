// lib/features/chef/data/models/chef_model.dart
//
// GET /chefs?q=&specialty=   → [ChefDto]   (list omits bio/packages/slots)
// GET /chefs/{id}            → ChefDto with "packages" and "availableSlots" (ISO-8601, UTC)
// POST /consultations        ← ConsultationRequestDto → ConsultationDto
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/chef.dart';

class ConsultPackageDto {
  const ConsultPackageDto({
    required this.id,
    required this.name,
    required this.description,
    required this.durationMinutes,
    required this.priceVnd,
    required this.mode,
  });

  factory ConsultPackageDto.fromJson(Map<String, dynamic> json) =>
      ConsultPackageDto(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        durationMinutes: readInt(json['durationMinutes']),
        priceVnd: readInt(json['priceVnd']),
        mode: json['mode'] as String? ?? 'online',
      );

  final String id;
  final String name;
  final String description;
  final int durationMinutes;
  final int priceVnd;
  final String mode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'durationMinutes': durationMinutes,
        'priceVnd': priceVnd,
        'mode': mode,
      };

  ConsultPackage toEntity() => ConsultPackage(
        id: id,
        name: name,
        description: description,
        durationMinutes: durationMinutes,
        priceVnd: priceVnd,
        mode: ConsultMode.fromApi(mode),
      );
}

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
    this.bio = '',
    this.consultCount = 0,
    this.certificates = const [],
    this.packages = const [],
    this.availableSlots = const [],
  });

  factory ChefDto.fromJson(Map<String, dynamic> json) => ChefDto(
        id: json['id']?.toString() ?? '',
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String? ?? '',
        specialties: readStringList(json['specialties']),
        rating: readDouble(json['rating']),
        reviewCount: readInt(json['reviewCount']),
        yearsExperience: readInt(json['yearsExperience']),
        city: json['city'] as String? ?? '',
        startingPriceVnd: readInt(json['startingPriceVnd']),
        bio: json['bio'] as String? ?? '',
        consultCount: readInt(json['consultCount']),
        certificates: readStringList(json['certificates']),
        packages: json['packages'] is List<Object?>
            ? (json['packages'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(ConsultPackageDto.fromJson)
                .toList()
            : const [],
        availableSlots: json['availableSlots'] is List<Object?>
            ? (json['availableSlots'] as List<Object?>)
                .map(readDateTime)
                .whereType<DateTime>()
                .toList()
            : const [],
      );

  final String id;
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
  final List<ConsultPackageDto> packages;
  final List<DateTime> availableSlots;

  Map<String, dynamic> toJson() => {
        'id': id,
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
        'packages': packages.map((p) => p.toJson()).toList(),
        'availableSlots':
            availableSlots.map((d) => d.toUtc().toIso8601String()).toList(),
      };

  Chef toEntity() => Chef(
        id: id,
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
        packages: packages.map((p) => p.toEntity()).toList(),
        availableSlots: availableSlots,
      );
}

class ConsultationRequestDto {
  const ConsultationRequestDto({
    required this.chefId,
    required this.packageId,
    required this.scheduledAt,
    this.note,
  });

  final String chefId;
  final String packageId;
  final DateTime scheduledAt;
  final String? note;

  Map<String, dynamic> toJson() => {
        'chefId': chefId,
        'packageId': packageId,
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

class ConsultationDto {
  const ConsultationDto({
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

  factory ConsultationDto.fromJson(Map<String, dynamic> json) =>
      ConsultationDto(
        id: json['id']?.toString() ?? '',
        chefId: json['chefId']?.toString() ?? '',
        chefName: json['chefName'] as String? ?? '',
        packageName: json['packageName'] as String? ?? '',
        priceVnd: readInt(json['priceVnd']),
        durationMinutes: readInt(json['durationMinutes']),
        mode: json['mode'] as String? ?? 'online',
        scheduledAt: readDateTime(json['scheduledAt']) ?? DateTime.now(),
        status: json['status'] as String? ?? 'pending',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        note: json['note'] as String?,
      );

  final String id;
  final String chefId;
  final String chefName;
  final String packageName;
  final int priceVnd;
  final int durationMinutes;
  final String mode;
  final DateTime scheduledAt;
  final String status;
  final DateTime createdAt;
  final String? note;

  ConsultationDto copyWith({String? status}) => ConsultationDto(
        id: id,
        chefId: chefId,
        chefName: chefName,
        packageName: packageName,
        priceVnd: priceVnd,
        durationMinutes: durationMinutes,
        mode: mode,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        createdAt: createdAt,
        note: note,
      );

  Consultation toEntity() => Consultation(
        id: id,
        chefId: chefId,
        chefName: chefName,
        packageName: packageName,
        priceVnd: priceVnd,
        durationMinutes: durationMinutes,
        mode: ConsultMode.fromApi(mode),
        scheduledAt: scheduledAt,
        status: ConsultationStatus.fromApi(status),
        createdAt: createdAt,
        note: note,
      );
}
