import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../../community/domain/entities/community_entities.dart';
import '../../../community/domain/repositories/community_repository.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_profile_repository.dart';

class UserProfileViewModel extends ViewModel {
  UserProfileViewModel(this._profiles, this._community, this._auth) {
    _subscription = _community.changes.listen((_) => emit());
    _auth.addListener(_reset);
  }
  final UserProfileRepository _profiles;
  final CommunityRepository _community;
  final AuthViewModel _auth;
  late final StreamSubscription<void> _subscription;
  ContentTab _tab = ContentTab.posts;
  ContentTab get tab => _tab;
  UserProfile get profile =>
      _profiles.profileFor(_auth.userId ?? '', _auth.name);
  List<RecipePost> get _owned =>
      _community.posts.where((p) => p.authorId == _auth.userId).toList();
  List<RecipePost> get posts => _owned
      .where((p) => p.isVideo == (_tab == ContentTab.videos))
      .toList(growable: false);
  List<Comment> get comments => _community.comments
      .where((c) => c.authorId == _auth.userId)
      .toList(growable: false);
  UserContentSummary get summary => UserContentSummary(
    posts: _owned.where((p) => !p.isVideo).length,
    videos: _owned.where((p) => p.isVideo).length,
    comments: comments.length,
  );
  void setTab(ContentTab value) {
    _tab = value;
    clearError();
  }

  bool deletePost(String id) {
    if (!_auth.canParticipate ||
        _community.find(id)?.authorId != _auth.userId) {
      fail('You can only delete your own content.');
      return false;
    }
    _community.deletePost(id);
    clearError();
    return true;
  }

  bool deleteComment(String id) {
    if (!_auth.canParticipate || !comments.any((c) => c.id == id)) {
      fail('You can only delete your own comments.');
      return false;
    }
    _community.deleteComment(id);
    clearError();
    return true;
  }

  bool editComment(String id, String text) {
    final trimmed = text.trim();
    if (!_auth.canParticipate || !comments.any((c) => c.id == id)) {
      fail('You can only edit your own comments.');
      return false;
    }
    if (trimmed.isEmpty || trimmed.length > 1000) {
      fail('Use a comment of 1–1,000 characters.');
      return false;
    }
    _community.saveComment(
      comments.firstWhere((c) => c.id == id).copyWith(text: trimmed),
    );
    clearError();
    return true;
  }

  void _reset() {
    _tab = ContentTab.posts;
    clearError();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(_reset);
    super.dispose();
  }
}
