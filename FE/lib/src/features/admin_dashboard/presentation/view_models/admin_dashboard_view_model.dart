import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/admin_entities.dart';
import '../../domain/repositories/admin_dashboard_repository.dart';

class AdminDashboardViewModel extends ViewModel {
  AdminDashboardViewModel(this._repository, this._auth) {
    _subscription = _repository.changes.listen((_) => emit());
    _auth.addListener(_reset);
  }
  final AdminDashboardRepository _repository;
  final AuthViewModel _auth;
  late final StreamSubscription<void> _subscription;
  bool _dismissed = false;
  bool _table = false;
  List<AdminMetric> get metrics => _auth.isAdmin ? _repository.metrics : [];
  List<SystemLog> get logs => _auth.isAdmin ? _repository.logs : [];
  List<AiMetric> get aiMetrics => _auth.isAdmin ? _repository.aiMetrics : [];
  List<ActivitySample> get activity =>
      _auth.isAdmin ? _repository.activity : [];
  bool get showAlert =>
      _auth.isAdmin && !_dismissed && _repository.pendingReports > 0;
  String get alert =>
      '${_repository.pendingReports} community reports need a human review.';
  bool get tableMode => _table;
  void dismissAlert() {
    _dismissed = true;
    emit();
  }

  void toggleTable() {
    _table = !_table;
    emit();
  }

  void refresh() {
    _dismissed = false;
    clearError();
  }

  void _reset() {
    _dismissed = false;
    emit();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(_reset);
    super.dispose();
  }
}
