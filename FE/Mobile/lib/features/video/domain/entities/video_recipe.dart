// lib/features/video/domain/entities/video_recipe.dart
import '../../../../core/models/author_summary.dart';

/// Server pipeline for an uploaded cooking video:
/// queued → transcribing (speech-to-text) → extracting (LLM) → ready | failed.
enum VideoAiStatus {
  queued('queued', 'Đang chờ xử lý'),
  transcribing('transcribing', 'Đang nhận dạng giọng nói'),
  extracting('extracting', 'AI đang trích xuất công thức'),
  ready('ready', 'Đã có tóm tắt AI'),
  failed('failed', 'Chưa trích xuất được');

  const VideoAiStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  bool get isProcessing =>
      this == queued || this == transcribing || this == extracting;

  static VideoAiStatus fromApi(String? value) =>
      values.firstWhere((s) => s.apiValue == value,
          orElse: () => VideoAiStatus.queued);
}

class VideoIngredient {
  const VideoIngredient({
    required this.name,
    required this.quantity,
    this.atSecond,
    this.uncertain = false,
  });

  final String name;
  final String quantity;

  /// Where the ingredient is mentioned in the video (tap to seek).
  final int? atSecond;

  /// Low speech-to-text confidence → shown in ochre, user should double-check.
  final bool uncertain;
}

class VideoStep {
  const VideoStep(
      {required this.index, required this.text, required this.atSecond});

  final int index;
  final String text;
  final int atSecond;
}

class TranscriptSegment {
  const TranscriptSegment({required this.atSecond, required this.text});

  final int atSecond;
  final String text;
}

class VideoRecipe {
  const VideoRecipe({
    required this.id,
    required this.title,
    required this.author,
    required this.coverSeed,
    required this.durationSeconds,
    required this.status,
    this.videoUrl,
    this.summary,
    this.servings,
    this.totalMinutes,
    this.kcalPerServing,
    this.ingredients = const [],
    this.steps = const [],
    this.transcript = const [],
    this.failureReason,
  });

  final String id;
  final String title;
  final AuthorSummary author;
  final String coverSeed;
  final int durationSeconds;
  final VideoAiStatus status;
  final String? videoUrl;
  final String? summary;
  final int? servings;
  final int? totalMinutes;
  final int? kcalPerServing;
  final List<VideoIngredient> ingredients;
  final List<VideoStep> steps;
  final List<TranscriptSegment> transcript;
  final String? failureReason;
}
