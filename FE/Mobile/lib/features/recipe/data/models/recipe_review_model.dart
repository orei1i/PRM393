// lib/features/recipe/data/models/recipe_review_model.dart
//
// GET /recipes/{id}/reviews?cursor=&limit=10 (AllowAnonymous; with a token
// also `myReview`, which is not repeated in `items`; newest first):
// { "recipeId": "l5", "averageRating": 4.6, "ratingCount": 5,
//   "distribution": { "5": 3, "4": 2, "3": 0, "2": 0, "1": 0 },
//   "myReview": null,
//   "items": [ { "id": "rv_l5_1", "rating": 5, "content": "…",
//                "author": { "id": "u_chef_tam", "fullName": "Lê Quang Tâm", "isVerifiedChef": true },
//                "createdAt": "2026-10-20T03:00:00Z", "updatedAt": null } ],
//   "nextCursor": null }
// PUT /recipes/{id}/reviews/me { "rating": 4, "content": "…" }
//   → { "review": {…}, "averageRating": 4.5, "ratingCount": 6 }
// DELETE /recipes/{id}/reviews/me → { "averageRating": 4.5, "ratingCount": 4 }
// GET|PUT /recipes/{id}/notes/me { "content": "…" }
//   → { "recipeId": "l5", "content": "…", "updatedAt": "…" } (PUT empty → data null)
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/recipe_review.dart';

class RecipeReviewDto {
  const RecipeReviewDto(this.entity);

  factory RecipeReviewDto.fromJson(Map<String, dynamic> json) {
    final author = readMap(json['author']);
    final content = json['content']?.toString().trim();
    return RecipeReviewDto(RecipeReview(
      id: json['id']?.toString() ?? '',
      rating: readInt(json['rating']),
      content: content == null || content.isEmpty ? null : content,
      authorId: author['id']?.toString() ?? '',
      authorName: author['fullName']?.toString() ?? 'Thành viên VeganLife',
      isVerifiedChef: author['isVerifiedChef'] == true,
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      updatedAt: readDateTime(json['updatedAt']),
    ));
  }

  final RecipeReview entity;

  RecipeReview toEntity() => entity;
}

Map<String, Object?> recipeReviewToJson(RecipeReview r) => {
      'id': r.id,
      'rating': r.rating,
      'content': r.content,
      'author': {
        'id': r.authorId,
        'fullName': r.authorName,
        'isVerifiedChef': r.isVerifiedChef,
      },
      'createdAt': r.createdAt.toUtc().toIso8601String(),
      'updatedAt': r.updatedAt?.toUtc().toIso8601String(),
    };

double? _optDouble(Object? v) => v == null ? null : readDouble(v);

RatingSummary _summary(Map<String, dynamic> json) {
  final raw = readMap(json['distribution']);
  return RatingSummary(
    average: _optDouble(json['averageRating']),
    count: json['ratingCount'] == null ? 0 : readInt(json['ratingCount']),
    distribution: {
      for (var s = 1; s <= 5; s++) s: readInt(raw['$s']),
    },
  );
}

class RecipeReviewsPageDto {
  const RecipeReviewsPageDto({
    required this.recipeId,
    required this.summary,
    this.myReview,
    this.items = const [],
    this.nextCursor,
  });

  factory RecipeReviewsPageDto.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final mine = json['myReview'];
    return RecipeReviewsPageDto(
      recipeId: json['recipeId']?.toString() ?? '',
      summary: _summary(json),
      myReview: mine is Map<String, dynamic>
          ? RecipeReviewDto.fromJson(mine).entity
          : null,
      items: items is List<Object?>
          ? items
              .whereType<Map<String, dynamic>>()
              .map((j) => RecipeReviewDto.fromJson(j).entity)
              .toList()
          : const [],
      nextCursor: json['nextCursor']?.toString(),
    );
  }

  final String recipeId;
  final RatingSummary summary;
  final RecipeReview? myReview;
  final List<RecipeReview> items;

  /// `null` → no more pages.
  final String? nextCursor;
}

/// PUT result: the saved review and the recipe's new average / count.
class ReviewWriteResultDto {
  const ReviewWriteResultDto(
      {required this.review, this.averageRating, required this.ratingCount});

  factory ReviewWriteResultDto.fromJson(Map<String, dynamic> json) =>
      ReviewWriteResultDto(
        review: RecipeReviewDto.fromJson(readMap(json['review'])).entity,
        averageRating: _optDouble(json['averageRating']),
        ratingCount: readInt(json['ratingCount']),
      );

  final RecipeReview review;
  final double? averageRating;
  final int ratingCount;
}

/// DELETE result: the recipe's new average / count.
class RatingTotalsDto {
  const RatingTotalsDto({this.averageRating, required this.ratingCount});

  factory RatingTotalsDto.fromJson(Map<String, dynamic> json) =>
      RatingTotalsDto(
        averageRating: _optDouble(json['averageRating']),
        ratingCount: readInt(json['ratingCount']),
      );

  final double? averageRating;
  final int ratingCount;
}

class UpsertReviewRequestDto {
  const UpsertReviewRequestDto({required this.rating, this.content});

  final int rating;

  /// Trimmed; `null` / empty → no text.
  final String? content;

  Map<String, dynamic> toJson() => {
        'rating': rating,
        'content': (content?.trim().isEmpty ?? true) ? null : content!.trim(),
      };
}

class RecipeNoteDto {
  const RecipeNoteDto(this.entity);

  factory RecipeNoteDto.fromJson(Map<String, dynamic> json) =>
      RecipeNoteDto(RecipeNote(
        recipeId: json['recipeId']?.toString() ?? '',
        content: json['content']?.toString() ?? '',
        updatedAt: readDateTime(json['updatedAt']) ?? DateTime.now(),
      ));

  final RecipeNote entity;

  RecipeNote toEntity() => entity;
}
