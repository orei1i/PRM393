import 'dart:async';
import '../../domain/entities/community_entities.dart';
import '../../domain/repositories/community_repository.dart';
import '../datasources/community_seed.dart';

class MockCommunityRepository implements CommunityRepository {
  final _events = StreamController<void>.broadcast(sync: true);
  final List<RecipePost> _posts = CommunitySeed.posts;
  final List<Comment> _comments = [...CommunitySeed.comments];
  final Map<String, Map<String, VoteState>> _votes = {};
  final Map<String, Set<String>> _saved = {};
  int _sequence = 100;

  @override
  Stream<void> get changes => _events.stream;
  @override
  List<RecipePost> get posts => List.unmodifiable(_posts);
  @override
  List<Comment> get comments => List.unmodifiable(_comments);
  @override
  String newId() => 'local-${_sequence++}';
  @override
  RecipePost? find(String id) {
    for (final post in _posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  @override
  VoteState voteFor(String postId, String? userId) =>
      _votes[postId]?[userId] ?? VoteState.none;
  @override
  int votes(String postId) =>
      (find(postId)?.baseVotes ?? 0) +
      (_votes[postId]?.values.fold<int>(
            0,
            (sum, vote) =>
                sum +
                switch (vote) {
                  VoteState.up => 1,
                  VoteState.down => -1,
                  VoteState.none => 0,
                },
          ) ??
          0);
  @override
  bool isSaved(String postId, String? userId) =>
      _saved[userId]?.contains(postId) ?? false;

  @override
  void toggleVote(String postId, String userId, VoteState vote) {
    if (find(postId) == null) return;
    final current = voteFor(postId, userId);
    (_votes[postId] ??= {})[userId] = current == vote ? VoteState.none : vote;
    _events.add(null);
  }

  @override
  void toggleSaved(String postId, String userId) {
    if (find(postId) == null) return;
    final saved = _saved[userId] ??= {};
    if (!saved.remove(postId)) saved.add(postId);
    _events.add(null);
  }

  @override
  void savePost(RecipePost post) {
    final index = _posts.indexWhere((item) => item.id == post.id);
    if (index < 0) {
      _posts.insert(0, post);
    } else {
      _posts[index] = post;
    }
    _events.add(null);
  }

  @override
  void deletePost(String id) {
    _posts.removeWhere((post) => post.id == id);
    _comments.removeWhere((comment) => comment.postId == id);
    _votes.remove(id);
    for (final saved in _saved.values) {
      saved.remove(id);
    }
    _events.add(null);
  }

  @override
  void setHidden(String id, bool hidden) {
    final post = find(id);
    if (post != null) savePost(post.copyWith(hidden: hidden));
  }

  @override
  void saveComment(Comment comment) {
    if (find(comment.postId) == null) {
      throw StateError('This post is no longer available.');
    }
    final index = _comments.indexWhere((item) => item.id == comment.id);
    if (index < 0) {
      _comments.add(comment);
    } else {
      _comments[index] = comment;
    }
    _events.add(null);
  }

  @override
  void deleteComment(String id) {
    // Remove a subtree rather than leaving orphaned replies.
    final ids = <String>{id};
    var changed = true;
    while (changed) {
      final before = ids.length;
      ids.addAll(
        _comments.where((c) => ids.contains(c.parentId)).map((c) => c.id),
      );
      changed = ids.length != before;
    }
    _comments.removeWhere((comment) => ids.contains(comment.id));
    _events.add(null);
  }

  @override
  void dispose() => _events.close();
}
