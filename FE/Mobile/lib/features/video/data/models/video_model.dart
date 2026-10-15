// lib/features/video/data/models/video_model.dart
//
// GET /videos/{id}
// {
//   "id": "vid_cha_lua", "title": "…", "author": { "id": "u_12", "fullName": "…", "isVerifiedChef": true },
//   "coverSeed": "cha-lua", "videoUrl": "https://…mp4", "durationSeconds": 724,
//   "aiStatus": "ready", "summary": "…", "servings": 4, "totalMinutes": 45, "kcalPerServing": 210,
//   "ingredients": [{ "name": "Đậu hũ ky", "quantity": "200 g", "atSecond": 35, "uncertain": false }],
//   "steps": [{ "index": 1, "text": "…", "atSecond": 60 }],
//   "transcript": [{ "atSecond": 0, "text": "…" }],
//   "failureReason": null
// }
import '../../../../core/models/author_summary.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../domain/entities/video_recipe.dart';

class VideoRecipeDto {
  const VideoRecipeDto({
    required this.id,
    required this.title,
    required this.author,
    required this.coverSeed,
    required this.durationSeconds,
    required this.aiStatus,
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

  factory VideoRecipeDto.fromJson(Map<String, dynamic> json) => VideoRecipeDto(
        id: json['id']?.toString() ?? '',
        title: json['title'] as String? ?? '',
        author: AuthorSummary.fromJsonValue(json['author']),
        coverSeed: json['coverSeed'] as String? ?? json['id']?.toString() ?? '',
        durationSeconds: readInt(json['durationSeconds']),
        aiStatus: json['aiStatus'] as String? ?? 'queued',
        videoUrl: json['videoUrl'] as String?,
        summary: json['summary'] as String?,
        servings: json['servings'] == null ? null : readInt(json['servings']),
        totalMinutes:
            json['totalMinutes'] == null ? null : readInt(json['totalMinutes']),
        kcalPerServing: json['kcalPerServing'] == null
            ? null
            : readInt(json['kcalPerServing']),
        ingredients: _list(json['ingredients']),
        steps: _list(json['steps']),
        transcript: _list(json['transcript']),
        failureReason: json['failureReason'] as String?,
      );

  static List<Map<String, dynamic>> _list(Object? value) =>
      value is List<Object?>
          ? value.whereType<Map<String, dynamic>>().toList()
          : const [];

  final String id;
  final String title;
  final AuthorSummary author;
  final String coverSeed;
  final int durationSeconds;
  final String aiStatus;
  final String? videoUrl;
  final String? summary;
  final int? servings;
  final int? totalMinutes;
  final int? kcalPerServing;
  final List<Map<String, dynamic>> ingredients;
  final List<Map<String, dynamic>> steps;
  final List<Map<String, dynamic>> transcript;
  final String? failureReason;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author.toJson(),
        'coverSeed': coverSeed,
        'durationSeconds': durationSeconds,
        'aiStatus': aiStatus,
        'videoUrl': videoUrl,
        'summary': summary,
        'servings': servings,
        'totalMinutes': totalMinutes,
        'kcalPerServing': kcalPerServing,
        'ingredients': ingredients,
        'steps': steps,
        'transcript': transcript,
        'failureReason': failureReason,
      };

  VideoRecipe toEntity() => VideoRecipe(
        id: id,
        title: title,
        author: author,
        coverSeed: coverSeed,
        durationSeconds: durationSeconds,
        status: VideoAiStatus.fromApi(aiStatus),
        videoUrl: videoUrl,
        summary: summary,
        servings: servings,
        totalMinutes: totalMinutes,
        kcalPerServing: kcalPerServing,
        ingredients: [
          for (final i in ingredients)
            VideoIngredient(
              name: i['name'] as String? ?? '',
              quantity: i['quantity'] as String? ?? '',
              atSecond: i['atSecond'] == null ? null : readInt(i['atSecond']),
              uncertain: i['uncertain'] == true,
            ),
        ],
        steps: [
          for (final s in steps)
            VideoStep(
              index: readInt(s['index']),
              text: s['text'] as String? ?? '',
              atSecond: readInt(s['atSecond']),
            ),
        ],
        transcript: [
          for (final t in transcript)
            TranscriptSegment(
                atSecond: readInt(t['atSecond']),
                text: t['text'] as String? ?? ''),
        ],
        failureReason: failureReason,
      );
}
