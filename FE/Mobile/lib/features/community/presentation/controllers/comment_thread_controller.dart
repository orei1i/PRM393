// lib/features/community/presentation/controllers/comment_thread_controller.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../../core/models/author_summary.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';

/// A top-level comment with the replies loaded so far (oldest first).
class CommentThread {
  const CommentThread({
    required this.comment,
    this.replies = const [],
    this.repliesCursor,
    this.repliesStarted = false,
    this.loadingReplies = false,
  });

  /// Its [Comment.replyCount] counts every reply, loaded or not.
  final Comment comment;
  final List<Comment> replies;

  /// Next page of replies once [repliesStarted]; `null` before that means
  /// "from the start" (the preview is merged by id).
  final String? repliesCursor;
  final bool repliesStarted;
  final bool loadingReplies;

  /// "Xem thêm N phản hồi".
  int get hiddenReplies => math.max(0, comment.replyCount - replies.length);

  CommentThread copyWith({
    Comment? comment,
    List<Comment>? replies,
    String? repliesCursor,
    bool clearRepliesCursor = false,
    bool? repliesStarted,
    bool? loadingReplies,
  }) =>
      CommentThread(
        comment: comment ?? this.comment,
        replies: replies ?? this.replies,
        repliesCursor:
            clearRepliesCursor ? null : (repliesCursor ?? this.repliesCursor),
        repliesStarted: repliesStarted ?? this.repliesStarted,
        loadingReplies: loadingReplies ?? this.loadingReplies,
      );
}

/// One post's comments for the post detail and the Reels comments sheet:
/// cursor paging (newest first, [pageSize] per page) as the list scrolls,
/// replies one level deep, add / edit / delete, and the comment count
/// (replies included).
///
/// [onCountChanged] receives each change of the count (+1 for a new
/// comment, −(1 + replies) for a deleted one) so the feed's copy follows.
class CommentThreadController extends ChangeNotifier {
  CommentThreadController({
    required this.api,
    required this.postId,
    required int initialCount,
    required this.me,
    this.onCountChanged,
    this.onEdited,
  }) : _total = initialCount;

  final CommunityApiService api;
  final String postId;

  /// The signed-in member, for comments shown before the server confirms.
  final AuthorSummary Function() me;
  final ValueChanged<int>? onCountChanged;
  final VoidCallback? onEdited;

  static const pageSize = 10;

  List<CommentThread> _threads = const [];
  String? _nextCursor;
  bool _started = false;
  bool _loading = false;
  Object? _error;
  int _total;
  bool _disposed = false;

  List<CommentThread> get threads => _threads;

  /// Every comment, replies included ("Bình luận (N)").
  int get total => _total;

  /// The first page arrived.
  bool get started => _started;
  bool get loading => _loading;

  /// The last page request failed ("Chưa tải được bình luận · Thử lại").
  Object? get error => _error;
  bool get hasMore => !_started || _nextCursor != null;
  bool get isEmpty => _started && _threads.isEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _count(int delta) {
    if (delta == 0) return;
    _total = math.max(0, _total + delta);
    onCountChanged?.call(delta);
  }

  static CommentThread _threadOf(Comment c) =>
      CommentThread(comment: c, replies: c.replies);

  /// The next page (the first one when nothing is loaded yet). Errors are
  /// kept in [error], never thrown. A call while a page is loading waits
  /// for that page.
  Future<void> loadMore() {
    final running = _pageLoad;
    if (running != null) return running;
    if (!hasMore) return Future.value();
    return _pageLoad = _loadPage().whenComplete(() {
      _pageLoad = null;
    });
  }

  Future<void>? _pageLoad;
  final Map<String, Future<void>> _replyLoads = {};

  Future<void> _loadPage() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final page =
          (await api.getComments(postId, cursor: _nextCursor, limit: pageSize))
              .toEntity();
      final known = {for (final t in _threads) t.comment.id};
      _threads = [
        ..._threads,
        for (final c in page.items)
          if (!known.contains(c.id)) _threadOf(c),
      ];
      _nextCursor = page.nextCursor;
      _started = true;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  CommentThread? threadOf(String commentId) {
    for (final t in _threads) {
      if (t.comment.id == commentId) return t;
    }
    return null;
  }

  /// A loaded comment or reply.
  Comment? find(String commentId) {
    for (final t in _threads) {
      if (t.comment.id == commentId) return t.comment;
      for (final r in t.replies) {
        if (r.id == commentId) return r;
      }
    }
    return null;
  }

  void _updateThread(String id, CommentThread Function(CommentThread) change) {
    _threads = [
      for (final t in _threads) t.comment.id == id ? change(t) : t,
    ];
    _notify();
  }

  /// "Xem thêm N phản hồi": the next page of replies (a call while they
  /// load waits for them). Rethrows on failure.
  Future<void> loadReplies(String commentId) {
    final running = _replyLoads[commentId];
    if (running != null) return running;
    final thread = threadOf(commentId);
    if (thread == null) return Future.value();
    return _replyLoads[commentId] = _loadReplies(thread).whenComplete(() {
      // A block: `remove` returns this future, which must not be awaited.
      _replyLoads.remove(commentId);
    });
  }

  Future<void> _loadReplies(CommentThread thread) async {
    final commentId = thread.comment.id;
    _updateThread(commentId, (t) => t.copyWith(loadingReplies: true));
    try {
      final page = (await api.getReplies(postId, commentId,
              cursor: thread.repliesStarted ? thread.repliesCursor : null))
          .toEntity();
      _updateThread(commentId, (t) {
        final byId = {for (final r in t.replies) r.id: r};
        for (final r in page.items) {
          byId.putIfAbsent(r.id, () => r);
        }
        final replies = byId.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        // Without another page, what we have is everything.
        final count =
            page.nextCursor == null ? replies.length : t.comment.replyCount;
        return t.copyWith(
          comment: t.comment.copyWith(replyCount: math.max(count, 0)),
          replies: replies,
          repliesStarted: true,
          repliesCursor: page.nextCursor,
          clearRepliesCursor: page.nextCursor == null,
          loadingReplies: false,
        );
      });
    } catch (e) {
      _updateThread(commentId, (t) => t.copyWith(loadingReplies: false));
      rethrow;
    }
  }

  /// Sends [text]; [replyTo] answers a comment (a reply to a reply joins the
  /// same top-level comment). Shown at once (top of the list, or at the end
  /// of its thread), replaced by the server's copy; removed again and
  /// rethrown on failure.
  Future<Comment> add(String text, {Comment? replyTo}) async {
    final content = text.trim();
    if (content.isEmpty) throw ArgumentError.value(text, 'text', 'empty');
    final parentId = replyTo == null ? null : (replyTo.parentId ?? replyTo.id);
    final pending = Comment(
      id: 'pending_${DateTime.now().microsecondsSinceEpoch}',
      author: me(),
      text: content,
      createdAt: DateTime.now(),
      pending: true,
      postId: postId,
      parentId: parentId,
    );
    _insert(pending);
    try {
      final saved = (await api.addComment(postId, content, parentId: parentId))
          .toEntity();
      _replace(pending.id, saved);
      _count(1);
      _notify();
      return saved;
    } catch (_) {
      _remove(pending);
      _notify();
      rethrow;
    }
  }

  void _insert(Comment c) {
    final parentId = c.parentId;
    if (parentId == null) {
      _threads = [_threadOf(c), ..._threads];
    } else {
      _threads = [
        for (final t in _threads)
          t.comment.id == parentId
              ? t.copyWith(
                  comment:
                      t.comment.copyWith(replyCount: t.comment.replyCount + 1),
                  replies: [...t.replies, c],
                )
              : t,
      ];
    }
    _notify();
  }

  void _replace(String id, Comment saved) {
    _threads = [
      for (final t in _threads)
        if (t.comment.id == id)
          t.copyWith(comment: saved.copyWith(replies: const []))
        else
          t.copyWith(
              replies: _dedupe([
            for (final r in t.replies) r.id == id ? saved : r,
          ])),
    ];
  }

  /// A page of replies may already hold the server's copy of a comment
  /// that was still pending here.
  static List<Comment> _dedupe(List<Comment> list) {
    final seen = <String>{};
    return [
      for (final c in list)
        if (seen.add(c.id)) c
    ];
  }

  void _remove(Comment c) {
    if (c.parentId == null) {
      _threads = _threads.where((t) => t.comment.id != c.id).toList();
      return;
    }
    _threads = [
      for (final t in _threads)
        if (t.comment.id == c.parentId)
          t.copyWith(
            comment: t.comment
                .copyWith(replyCount: math.max(0, t.comment.replyCount - 1)),
            replies: t.replies.where((r) => r.id != c.id).toList(),
          )
        else
          t,
    ];
  }

  /// Saves the member's own comment; rethrows on failure.
  Future<Comment> edit(Comment comment, String text) async {
    final content = text.trim();
    if (content.isEmpty) throw ArgumentError.value(text, 'text', 'empty');
    final saved =
        (await api.updateComment(postId, comment.id, content)).toEntity();
    // Keep what this screen knows about the replies.
    final merged = (find(comment.id) ?? comment)
        .copyWith(text: saved.text, updatedAt: saved.updatedAt);
    _threads = [
      for (final t in _threads)
        if (t.comment.id == comment.id)
          t.copyWith(comment: merged)
        else
          t.copyWith(replies: [
            for (final r in t.replies) r.id == comment.id ? merged : r,
          ]),
    ];
    onEdited?.call();
    _notify();
    return merged;
  }

  /// Replies that go with [comment] when it is deleted.
  int repliesGoingWith(Comment comment) =>
      comment.isReply ? 0 : (threadOf(comment.id)?.comment.replyCount ?? 0);

  /// Deletes the member's own comment (a top-level one with its replies);
  /// rethrows on failure and keeps it.
  Future<void> delete(Comment comment) async {
    final removed = 1 + repliesGoingWith(comment);
    await api.deleteComment(postId, comment.id);
    _remove(comment);
    _count(-removed);
    _notify();
  }

  /// Loads pages (and replies) until [commentId] is on screen, for "Nội dung
  /// của tôi › Bình luận". [parentId] is set for a reply. `true` if found.
  Future<bool> reveal(String commentId, {String? parentId}) async {
    final topId = parentId ?? commentId;
    var pages = 0;
    while (threadOf(topId) == null && hasMore && pages < 20) {
      await loadMore();
      if (_error != null) return false;
      pages++;
    }
    final thread = threadOf(topId);
    if (thread == null) return false;
    if (parentId == null) return true;
    var rounds = 0;
    while (find(commentId) == null &&
        (threadOf(topId)?.hiddenReplies ?? 0) > 0 &&
        rounds < 20) {
      try {
        await loadReplies(topId);
      } catch (_) {
        return false;
      }
      rounds++;
    }
    return find(commentId) != null;
  }
}
