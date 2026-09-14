import '../entities/ai_ops_entities.dart';

abstract interface class AiOperationsRepository {
  Stream<void> get changes;
  List<AiModelLog> get logs;
  List<ModelPerformanceMetric> get metrics;
  void applyOverride(String id, String text, String reason);
  void dispose();
}
