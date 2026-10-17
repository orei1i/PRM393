// lib/features/chef_studio/data/models/chef_studio_models.dart
//
// GET/PUT /chefs/me/profile          ChefProfileDto (chef_profiles; 404 when none)
// { "id": 3, "userId": 12, "specialty": "Ẩm thực chay Việt", "bio": "…",
//   "pricePerDay": 150000, "feedbackPricePerDay": 180000,      // "Hồ sơ & bảng giá"
//   "minPlanDays": 3, "maxPlanDays": 30, "acceptingBookings": true }
// Proposed chef_profiles columns: price_per_day, feedback_price_per_day,
// min_plan_days (3), max_plan_days (30), accepting_bookings BIT.
// GET/POST /chefs/me/knowledge-docs  KnowledgeDocDto (knowledge_docs + proposed
//                                    status / review_note columns; chunkCount computed by BE)
// { "id": 40, "chefId": 3, "title": "…", "source": "Chef", "fileUrl": "https://…pdf",
//   "createdAt": "2026-10-10T02:00:00Z", "status": "Pending", "reviewNote": null, "chunkCount": 0 }
// POST body: { "title": "…", "fileUrl": "https://…" }   (source is set by the server)
import '../../../../core/utils/json_helpers.dart';

class ChefProfileDto {
  const ChefProfileDto({
    required this.id,
    required this.userId,
    required this.specialty,
    required this.bio,
    this.pricePerDay = 120000,
    this.feedbackPricePerDay = 180000,
    this.minPlanDays = 3,
    this.maxPlanDays = 30,
    this.acceptingBookings = true,
  });

  factory ChefProfileDto.fromJson(Map<String, dynamic> json) {
    int orDefault(Object? value, int fallback) {
      final n = readInt(value);
      return n > 0 ? n : fallback;
    }

    return ChefProfileDto(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      specialty: json['specialty'] as String? ??
          readStringList(json['specialties']).firstOrNull ??
          '',
      bio: json['bio'] as String? ?? '',
      pricePerDay: orDefault(json['pricePerDay'], 120000),
      feedbackPricePerDay: orDefault(json['feedbackPricePerDay'], 180000),
      minPlanDays: orDefault(json['minPlanDays'], 3),
      maxPlanDays: orDefault(json['maxPlanDays'], 30),
      acceptingBookings: json['acceptingBookings'] as bool? ?? true,
    );
  }

  final String id;
  final String userId;
  final String specialty;
  final String bio;

  /// "Giá mỗi ngày" (one-shot plans).
  final int pricePerDay;

  /// "Giá có phản hồi mỗi ngày".
  final int feedbackPricePerDay;
  final int minPlanDays;
  final int maxPlanDays;

  /// "Đang nhận yêu cầu".
  final bool acceptingBookings;
}

/// PUT /chefs/me/profile (upsert).
class ChefProfileRequestDto {
  const ChefProfileRequestDto({
    required this.specialty,
    required this.bio,
    this.pricePerDay = 120000,
    this.feedbackPricePerDay = 180000,
    this.minPlanDays = 3,
    this.maxPlanDays = 30,
    this.acceptingBookings = true,
  });

  final String specialty;
  final String bio;
  final int pricePerDay;
  final int feedbackPricePerDay;
  final int minPlanDays;
  final int maxPlanDays;
  final bool acceptingBookings;

  Map<String, dynamic> toJson() => {
        'specialty': specialty,
        'bio': bio,
        'pricePerDay': pricePerDay,
        'feedbackPricePerDay': feedbackPricePerDay,
        'minPlanDays': minPlanDays,
        'maxPlanDays': maxPlanDays,
        'acceptingBookings': acceptingBookings,
      };
}

/// `knowledge_docs.status` (proposed). WHO uploads start Approved.
enum KnowledgeDocStatus {
  pending('Pending', 'Chờ duyệt'),
  approved('Approved', 'Đã duyệt'),
  rejected('Rejected', 'Bị từ chối');

  const KnowledgeDocStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static KnowledgeDocStatus fromApi(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return values.firstWhere((s) => s.apiValue.toLowerCase() == raw,
        orElse: () => pending);
  }
}

class KnowledgeDocDto {
  const KnowledgeDocDto({
    required this.id,
    required this.title,
    required this.fileUrl,
    required this.createdAt,
    required this.status,
    this.chefId,
    this.source = 'Chef',
    this.reviewNote,
    this.chunkCount = 0,
  });

  factory KnowledgeDocDto.fromJson(Map<String, dynamic> json) =>
      KnowledgeDocDto(
        id: json['id']?.toString() ?? '',
        chefId: json['chefId']?.toString(),
        title: json['title'] as String? ?? '',
        source: json['source'] as String? ?? 'Chef',
        fileUrl: json['fileUrl'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        status: KnowledgeDocStatus.fromApi(json['status']),
        reviewNote: json['reviewNote'] as String?,
        chunkCount: readInt(json['chunkCount']),
      );

  final String id;
  final String? chefId;
  final String title;

  /// `WHO` | `Chef`.
  final String source;
  final String fileUrl;
  final DateTime createdAt;
  final KnowledgeDocStatus status;
  final String? reviewNote;
  final int chunkCount;
}

class KnowledgeDocRequestDto {
  const KnowledgeDocRequestDto({required this.title, required this.fileUrl});

  final String title;
  final String fileUrl;

  Map<String, dynamic> toJson() => {'title': title, 'fileUrl': fileUrl};
}
