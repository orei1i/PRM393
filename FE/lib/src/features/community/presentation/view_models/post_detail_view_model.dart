import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/community_entities.dart';
import '../../domain/repositories/community_repository.dart';

class PostDetailViewModel extends ViewModel {
  PostDetailViewModel(this._repository, this._auth, this.postId) {
    _subscription = _repository.changes.listen((_) => emit());
    _auth.addListener(_roleChanged);
  }
  final CommunityRepository _repository;
  final AuthViewModel _auth;
  final String postId;
  late final StreamSubscription<void> _subscription;
  String _draft = '';
  String? _replyTo;
  RecipePost? get post {
    final value = _repository.find(postId);
    return value?.hidden == true ? null : value;
  }

  int get votes => _repository.votes(postId);
  VoteState get vote => _repository.voteFor(postId, _auth.userId);
  bool get saved => _repository.isSaved(postId, _auth.userId);
  bool get canWrite => _auth.canParticipate && post != null;
  List<Comment> get comments => _repository.comments
      .where((c) => c.postId == postId && c.parentId == null)
      .toList(growable: false);
  List<Comment> replies(String id) => _repository.comments
      .where((c) => c.postId == postId && c.parentId == id)
      .toList(growable: false);
  String? get replyTo => _replyTo;
  bool get canSubmit => canWrite && _draft.trim().isNotEmpty;

  void setDraft(String value) {
    _draft = value;
    emit();
  }

  void reply(String? id) {
    _replyTo = id;
    emit();
  }

  bool toggleVote(VoteState value) {
    if (!canWrite) return false;
    _repository.toggleVote(postId, _auth.userId!, value);
    return true;
  }

  bool toggleSaved() {
    if (!canWrite) return false;
    _repository.toggleSaved(postId, _auth.userId!);
    return true;
  }

  bool submitComment() {
    if (!canWrite) {
      fail('Sign in to join the conversation.');
      return false;
    }
    final text = _draft.trim();
    if (text.isEmpty || text.length > 1000) {
      fail('Write a comment of 1–1,000 characters.');
      return false;
    }
    if (_replyTo != null &&
        !_repository.comments.any(
          (c) => c.id == _replyTo && c.postId == postId,
        )) {
      _replyTo = null;
      fail('That comment was removed. Please try again.');
      return false;
    }
    _repository.saveComment(
      Comment(
        id: _repository.newId(),
        postId: postId,
        authorId: _auth.userId!,
        author: _auth.name,
        text: text,
        parentId: _replyTo,
      ),
    );
    _draft = '';
    _replyTo = null;
    clearError();
    return true;
  }

  void _roleChanged() {
    _draft = '';
    _replyTo = null;
    emit();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(_roleChanged);
    super.dispose();
  }
}
