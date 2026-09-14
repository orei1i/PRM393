enum ModerationDecision { approve, delete, warn }

class FlaggedContent {
  const FlaggedContent({
    required this.id,
    required this.postId,
    required this.title,
    required this.author,
    required this.reason,
    required this.reports,
    this.resolved = false,
    this.contentRemoved = false,
  });
  final String id, postId, title, author, reason;
  final int reports;
  final bool resolved, contentRemoved;
  bool get actionable => !resolved && !contentRemoved;
  FlaggedContent resolve({bool contentRemoved = false}) => FlaggedContent(
    id: id,
    postId: postId,
    title: title,
    author: author,
    reason: reason,
    reports: reports,
    resolved: true,
    contentRemoved: this.contentRemoved || contentRemoved,
  );
}

class ModerationAction {
  const ModerationAction({
    required this.contentId,
    required this.title,
    required this.decision,
    required this.actorId,
    required this.at,
  });
  final String contentId, title, actorId;
  final ModerationDecision decision;
  final DateTime at;
}
