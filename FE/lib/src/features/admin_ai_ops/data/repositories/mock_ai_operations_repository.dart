import 'dart:async';
import '../../domain/entities/ai_ops_entities.dart';
import '../../domain/repositories/ai_operations_repository.dart';

class MockAiOperationsRepository implements AiOperationsRepository {
  final _events = StreamController<void>.broadcast(sync: true);
  final _logs = [
    const AiModelLog(
      id: 'a1',
      prompt: 'Plant-based protein ideas',
      response: 'Include legumes, tofu, tempeh, and varied grains.',
      confidence: .96,
      latencyMs: 820,
    ),
    const AiModelLog(
      id: 'a2',
      prompt: 'Nutrition plan for a special medical condition',
      response: 'This needs individual assessment by a qualified clinician.',
      confidence: .62,
      latencyMs: 1120,
    ),
    const AiModelLog(
      id: 'a3',
      prompt: 'Egg substitutes for baking',
      response: 'A flax mixture can work in some recipes; results vary.',
      confidence: .88,
      latencyMs: 760,
    ),
  ];
  @override
  Stream<void> get changes => _events.stream;
  @override
  List<AiModelLog> get logs => List.unmodifiable(_logs);
  @override
  List<ModelPerformanceMetric> get metrics => [
    const ModelPerformanceMetric('Sample mean latency', '900', 'ms'),
    const ModelPerformanceMetric('Sample response score', '82', '%'),
    ModelPerformanceMetric(
      'Manual overrides',
      '${_logs.where((l) => l.overridden).length}',
      'local',
    ),
  ];
  @override
  void applyOverride(String id, String text, String reason) {
    final index = _logs.indexWhere((l) => l.id == id);
    if (index < 0) throw StateError('Unknown log');
    _logs[index] = _logs[index].override(text, reason);
    _events.add(null);
  }

  @override
  void dispose() => _events.close();
}
