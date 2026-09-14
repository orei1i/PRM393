import 'dart:async';
import '../../../community/domain/repositories/community_repository.dart';
import '../../domain/entities/moderation_entities.dart';
import '../../domain/repositories/moderation_repository.dart';

class MockModerationRepository implements ModerationRepository {
  MockModerationRepository(this._community) {
    _reconcileMissingContent();
    _subscription = _community.changes.listen(
      (_) => _reconcileMissingContent(),
    );
  }
  final CommunityRepository _community;
  late final StreamSubscription<void> _subscription;
  final _events = StreamController<void>.broadcast(sync: true);
  final _flags = [
    const FlaggedContent(
      id: 'f1',
      postId: 'p3',
      title: 'Crispy tofu in 15 minutes',
      author: 'Sam Rivera',
      reason: 'Review a reported nutrition statement in the video description.',
      reports: 3,
    ),
    const FlaggedContent(
      id: 'f2',
      postId: 'p7',
      title: 'Roasted sweet potato salad',
      author: 'Noor Lee',
      reason: 'Possible promotional content; verify community guidelines.',
      reports: 2,
    ),
    const FlaggedContent(
      id: 'f3',
      postId: 'p2',
      title: 'Creamy mushroom pasta',
      author: 'Alex Green',
      reason: 'Allergen labeling clarification requested.',
      reports: 1,
    ),
  ];
  final List<ModerationAction> _actions = [];
  @override
  Stream<void> get changes => _events.stream;
  @override
  List<FlaggedContent> get flags => List.unmodifiable(_flags);
  @override
  List<ModerationAction> get actions => List.unmodifiable(_actions);
  @override
  void apply(String id, ModerationDecision decision, String actorId) {
    final index = _flags.indexWhere((f) => f.id == id && f.actionable);
    if (index < 0) throw StateError('This report has already been resolved.');
    final flag = _flags[index];
    if (_community.find(flag.postId) == null) {
      _reconcileMissingContent();
      throw StateError('This content has been removed.');
    }
    _flags[index] = flag.resolve(
      contentRemoved: decision == ModerationDecision.delete,
    );
    switch (decision) {
      case ModerationDecision.approve:
        _community.setHidden(flag.postId, false);
      case ModerationDecision.delete:
        _community.deletePost(flag.postId);
      case ModerationDecision.warn:
        break;
    }
    _actions.insert(
      0,
      ModerationAction(
        contentId: id,
        title: flag.title,
        decision: decision,
        actorId: actorId,
        at: DateTime.now(),
      ),
    );
    _events.add(null);
  }

  void _reconcileMissingContent() {
    var changed = false;
    for (var i = 0; i < _flags.length; i++) {
      final flag = _flags[i];
      if (!flag.contentRemoved && _community.find(flag.postId) == null) {
        _flags[i] = flag.resolve(contentRemoved: true);
        changed = true;
      }
    }
    if (changed) _events.add(null);
  }

  @override
  void dispose() {
    _subscription.cancel();
    _events.close();
  }
}
