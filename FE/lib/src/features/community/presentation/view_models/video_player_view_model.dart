import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../domain/entities/community_entities.dart';
import '../../domain/repositories/community_repository.dart';

class VideoPlayerViewModel extends ViewModel {
  VideoPlayerViewModel(this._repository, this.postId) {
    _subscription = _repository.changes.listen((_) {
      if (post == null) _timer?.cancel();
      emit();
    });
  }
  final CommunityRepository _repository;
  final String postId;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  int _elapsedSeconds = 0;
  RecipePost? get post {
    final value = _repository.find(postId);
    return value != null && !value.hidden && value.isVideo ? value : null;
  }

  Duration get duration {
    final value = post;
    return value == null ? Duration.zero : CookingVideo(post: value).duration;
  }

  bool get playing => _timer?.isActive ?? false;
  double get progress => duration.inSeconds == 0
      ? 0
      : (_elapsedSeconds / duration.inSeconds).clamp(0, 1);
  String get elapsed => _format(_elapsedSeconds);
  String get durationLabel => _format(duration.inSeconds);
  static String _format(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  void toggle() {
    if (disposed || post == null || duration.inSeconds == 0) return;
    if (playing) {
      _timer?.cancel();
      emit();
      return;
    }
    if (_elapsedSeconds >= duration.inSeconds) _elapsedSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds = (_elapsedSeconds + 1).clamp(0, duration.inSeconds);
      if (_elapsedSeconds >= duration.inSeconds) _timer?.cancel();
      emit();
    });
    emit();
  }

  void seek(double value) {
    if (disposed || post == null || !value.isFinite) return;
    _elapsedSeconds = (value.clamp(0, 1) * duration.inSeconds).round();
    if (_elapsedSeconds >= duration.inSeconds) _timer?.cancel();
    emit();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription.cancel();
    super.dispose();
  }
}
