// lib/features/recipe/domain/entities/recipe_review.dart
import '../../../../core/utils/formatters.dart';

/// "Rất tệ" … "Tuyệt vời" for 1–5 stars.
const reviewRatingLabels = [
  'Rất tệ',
  'Chưa ổn',
  'Tạm được',
  'Ngon',
  'Tuyệt vời'
];

/// Bounds of a review's optional text and of a private note.
const reviewContentMin = 10;
const reviewContentMax = 500;
const noteContentMax = 2000;

/// Same rules as the server (and the restaurant reviews); `null` when valid.
String? validateReviewRating(int? rating) =>
    rating == null || rating < 1 || rating > 5 ? 'Chọn từ 1 đến 5 sao.' : null;

/// Optional text: when given, 10–500 characters (trimmed).
String? validateReviewContent(String? content) {
  final n = content?.trim().length ?? 0;
  if (n == 0) return null;
  if (n < reviewContentMin) return 'Nhận xét cần ít nhất 10 ký tự';
  if (n > reviewContentMax) return 'Tối đa 500 ký tự';
  return null;
}

/// A note is at most 2000 characters (trimmed); empty means "delete".
String? validateNoteContent(String content) =>
    content.trim().length > noteContentMax ? 'Ghi chú tối đa 2000 ký tự' : null;

/// One member's rating of a public recipe (`recipe_reviews`).
class RecipeReview {
  const RecipeReview({
    required this.id,
    required this.rating,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
    this.content,
    this.isVerifiedChef = false,
    this.updatedAt,
  });

  final String id;

  /// 1–5.
  final int rating;
  final String? content;
  final String authorId;
  final String authorName;

  /// ✓ next to the name.
  final bool isVerifiedChef;
  final DateTime createdAt;

  /// Set once edited ("(đã sửa)").
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null;
}

/// Average, count and 5→1 distribution of a recipe's ratings.
class RatingSummary {
  const RatingSummary({
    this.average,
    this.count = 0,
    this.distribution = const {},
  });

  static const empty = RatingSummary();

  /// `null` when there is no rating yet.
  final double? average;
  final int count;

  /// Stars (1–5) → number of reviews.
  final Map<int, int> distribution;

  bool get isEmpty => count == 0;

  /// "4,6".
  String get averageLabel => formatDecimal(average ?? 0);

  /// "★ 4,6 · 5 đánh giá" or "Chưa có đánh giá".
  String get headline => isEmpty
      ? 'Chưa có đánh giá'
      : '★ $averageLabel · ${formatInt(count)} đánh giá';

  int countOf(int stars) => distribution[stars] ?? 0;

  /// After the member's own rating changed from [before] to [after]
  /// (either may be `null`): the server's new average and count, the
  /// distribution adjusted locally.
  RatingSummary apply(
      {int? before, int? after, double? average, required int count}) {
    final d = {for (var s = 1; s <= 5; s++) s: countOf(s)};
    if (before != null) d[before] = (d[before]! - 1).clamp(0, 1 << 30);
    if (after != null) d[after] = d[after]! + 1;
    return RatingSummary(
        average: count == 0 ? null : average, count: count, distribution: d);
  }
}

/// A member's private note on a recipe (`recipe_notes`): only they see it.
class RecipeNote {
  const RecipeNote({
    required this.recipeId,
    required this.content,
    required this.updatedAt,
  });

  final String recipeId;
  final String content;
  final DateTime updatedAt;
}
