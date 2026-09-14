import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/ai_ops_entities.dart';
import '../../domain/repositories/ai_operations_repository.dart';

class AiOperationsViewModel extends ViewModel {
  AiOperationsViewModel(this._repository, this._auth) {
    _subscription = _repository.changes.listen((_) => emit());
    _auth.addListener(_reset);
  }
  final AiOperationsRepository _repository;
  final AuthViewModel _auth;
  late final StreamSubscription<void> _subscription;
  String _filter = 'All';
  static const filters = ['All', 'Needs review', 'Overridden'];
  String get filter => _filter;
  List<AiModelLog> get logs => !_auth.isAdmin
      ? []
      : _repository.logs
            .where(
              (l) => switch (_filter) {
                'Needs review' => l.needsReview,
                'Overridden' => l.overridden,
                _ => true,
              },
            )
            .toList(growable: false);
  List<ModelPerformanceMetric> get metrics =>
      _auth.isAdmin ? _repository.metrics : [];
  void setFilter(String value) {
    _filter = value;
    emit();
  }

  bool applyOverride(String id, String text, String reason) {
    if (!_auth.isAdmin) {
      fail('Administrator access required.');
      return false;
    }
    if (text.trim().length < 10 ||
        text.trim().length > 2000 ||
        reason.trim().length < 5 ||
        reason.trim().length > 500) {
      fail(
        'Provide replacement text (10–2,000 characters) and a reason (5–500 characters).',
      );
      return false;
    }
    try {
      _repository.applyOverride(id, text.trim(), reason.trim());
      clearError();
      return true;
    } catch (_) {
      fail('This log is no longer available.');
      return false;
    }
  }

  void _reset() {
    _filter = 'All';
    clearError();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(_reset);
    super.dispose();
  }
}
