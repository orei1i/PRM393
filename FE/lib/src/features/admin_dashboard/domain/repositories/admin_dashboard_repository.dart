import '../entities/admin_entities.dart';

abstract interface class AdminDashboardRepository {
  Stream<void> get changes;
  List<AdminMetric> get metrics;
  List<SystemLog> get logs;
  List<AiMetric> get aiMetrics;
  List<ActivitySample> get activity;
  int get pendingReports;
  void dispose();
}
