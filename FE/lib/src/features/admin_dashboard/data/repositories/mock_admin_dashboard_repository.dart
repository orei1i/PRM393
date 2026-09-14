import 'dart:async';
import '../../../community/domain/repositories/community_repository.dart';
import '../../../admin_moderation/domain/repositories/moderation_repository.dart';
import '../../../admin_ai_ops/domain/repositories/ai_operations_repository.dart';
import '../../domain/entities/admin_entities.dart';
import '../../domain/repositories/admin_dashboard_repository.dart';

class MockAdminDashboardRepository implements AdminDashboardRepository {
  MockAdminDashboardRepository(this._community, this._moderation, this._ai) {
    _subscriptions = [
      _community.changes.listen((_) => _events.add(null)),
      _moderation.changes.listen((_) => _events.add(null)),
      _ai.changes.listen((_) => _events.add(null)),
    ];
  }
  final CommunityRepository _community;
  final ModerationRepository _moderation;
  final AiOperationsRepository _ai;
  final _events = StreamController<void>.broadcast(sync: true);
  late final List<StreamSubscription<void>> _subscriptions;
  @override
  Stream<void> get changes => _events.stream;
  @override
  int get pendingReports => _moderation.flags.where((f) => f.actionable).length;
  @override
  List<AdminMetric> get metrics => [
    AdminMetric(
      'Published recipes',
      '${_community.posts.where((p) => !p.hidden && !p.isVideo).length}',
      'Current demo session',
    ),
    AdminMetric(
      'Cooking videos',
      '${_community.posts.where((p) => !p.hidden && p.isVideo).length}',
      'Current demo session',
    ),
    AdminMetric('Open reports', '$pendingReports', 'Awaiting a human review'),
    AdminMetric(
      'AI reviews',
      '${_ai.logs.where((l) => l.overridden).length}',
      'Manual overrides recorded',
    ),
  ];
  @override
  List<SystemLog> get logs => [
    ..._moderation.actions
        .take(3)
        .map((a) => SystemLog('Moderation: ${a.decision.name}', a.title)),
    const SystemLog(
      'Demo repositories ready',
      'All features are using local, seeded data.',
    ),
    if (_ai.logs.any((l) => l.needsReview))
      const SystemLog(
        'Sample AI response needs review',
        'A low-confidence record is available in AI operations.',
        warning: true,
      ),
  ];
  @override
  List<AiMetric> get aiMetrics => const [
    AiMetric('Sample mean latency', '900 ms'),
    AiMetric('Sample score', '82%'),
    AiMetric('Data source', 'Local mock'),
  ];
  @override
  List<ActivitySample> get activity => const [
    ActivitySample('Mon', 18),
    ActivitySample('Tue', 24),
    ActivitySample('Wed', 20),
    ActivitySample('Thu', 31),
    ActivitySample('Fri', 28),
    ActivitySample('Sat', 42),
    ActivitySample('Sun', 35),
  ];
  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _events.close();
  }
}
