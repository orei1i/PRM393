// lib/features/video/data/mock/mock_video_store.dart
import '../../../../core/models/author_summary.dart';
import '../models/video_model.dart';
import 'video_mock_data.dart';

/// In-memory video catalogue shared by the community and video mocks.
///
/// Videos created from the app walk through the real pipeline timing:
/// 0–4 s queued → 4–10 s transcribing → 10–16 s extracting → ready.
class MockVideoStore {
  MockVideoStore._() {
    for (final json in seedVideos) {
      _videos[json['id'] as String] = _Entry(VideoRecipeDto.fromJson(json));
    }
  }

  static final MockVideoStore instance = MockVideoStore._();

  final Map<String, _Entry> _videos = {};

  VideoRecipeDto? get(String id) => _videos[id]?.current();

  /// Registers a video submitted by link (or an uploaded file's URL) and
  /// returns its id.
  String createFromLink(
      {required String title,
      required AuthorSummary author,
      required String url,
      int durationSeconds = 300}) {
    final id = 'vid_${DateTime.now().millisecondsSinceEpoch}';
    _videos[id] = _Entry(
      VideoRecipeDto(
        id: id,
        title: title,
        author: author,
        coverSeed: id,
        durationSeconds: durationSeconds,
        aiStatus: 'queued',
        videoUrl: url,
      ),
      startedAt: DateTime.now(),
    );
    return id;
  }

  /// Restarts the pipeline for a failed video.
  void retry(String id) {
    final entry = _videos[id];
    if (entry == null) return;
    _videos[id] = _Entry(entry.base, startedAt: DateTime.now());
  }
}

class _Entry {
  _Entry(this.base, {this.startedAt});

  final VideoRecipeDto base;

  /// Non-null while (or after) the simulated pipeline runs.
  final DateTime? startedAt;

  VideoRecipeDto current() {
    final start = startedAt;
    if (start == null) return base;
    final elapsed = DateTime.now().difference(start).inSeconds;
    final status = switch (elapsed) {
      < 4 => 'queued',
      < 10 => 'transcribing',
      < 16 => 'extracting',
      _ => 'ready',
    };
    if (status != 'ready') return _copy(status);
    return base.summary != null ? _copy('ready') : _generated();
  }

  VideoRecipeDto _copy(String status) => VideoRecipeDto(
        id: base.id,
        title: base.title,
        author: base.author,
        coverSeed: base.coverSeed,
        durationSeconds: base.durationSeconds,
        aiStatus: status,
        videoUrl: base.videoUrl,
        summary: status == 'ready' ? base.summary : null,
        servings: base.servings,
        totalMinutes: base.totalMinutes,
        kcalPerServing: base.kcalPerServing,
        ingredients: status == 'ready' ? base.ingredients : const [],
        steps: status == 'ready' ? base.steps : const [],
        transcript: status == 'ready' ? base.transcript : const [],
      );

  /// What the extractor returns for a brand-new upload (mock template).
  VideoRecipeDto _generated() => VideoRecipeDto(
        id: base.id,
        title: base.title,
        author: base.author,
        coverSeed: base.coverSeed,
        durationSeconds: base.durationSeconds,
        aiStatus: 'ready',
        videoUrl: base.videoUrl,
        summary:
            'Tóm tắt tự động từ lời thoại video. Hãy kiểm tra lại định lượng trước khi lưu vào thực đơn.',
        servings: 2,
        totalMinutes: 25,
        kcalPerServing: 380,
        ingredients: const [
          {'name': 'Đậu hũ non', 'quantity': '1 hộp', 'atSecond': 20},
          {'name': 'Nấm bào ngư', 'quantity': '150 g', 'atSecond': 41},
          {
            'name': 'Hành lá',
            'quantity': '2 nhánh',
            'atSecond': 63,
            'uncertain': true
          },
          {'name': 'Nước tương', 'quantity': '1 muỗng canh', 'atSecond': 75},
        ],
        steps: const [
          {
            'index': 1,
            'text': 'Sơ chế nguyên liệu, cắt đậu hũ miếng vừa ăn.',
            'atSecond': 20
          },
          {
            'index': 2,
            'text': 'Xào nấm với chút dầu đến khi se lại.',
            'atSecond': 41
          },
          {
            'index': 3,
            'text':
                'Cho đậu hũ và nước tương, đun nhỏ lửa 5 phút, rắc hành lá.',
            'atSecond': 75
          },
        ],
        transcript: const [
          {'atSecond': 0, 'text': '(Lời thoại được nhận dạng tự động)'},
          {
            'atSecond': 20,
            'text': 'Đầu tiên mình cắt đậu hũ non thành miếng vừa ăn.'
          },
        ],
      );
}
