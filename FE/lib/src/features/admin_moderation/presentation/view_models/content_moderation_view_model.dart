import 'dart:async';
import '../../../../core/state/view_model.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/moderation_entities.dart';
import '../../domain/repositories/moderation_repository.dart';

class ContentModerationViewModel extends ViewModel {
  ContentModerationViewModel(this._repository, this._auth) {
    _subscription = _repository.changes.listen((_) => emit());
    _auth.addListener(_reset);
  }
  final ModerationRepository _repository;
  final AuthViewModel _auth;
  late final StreamSubscription<void> _subscription;
  bool _resolved = false;
  bool get showResolved => _resolved;
  List<FlaggedContent> get flags => _auth.isAdmin
      ? _repository.flags
            .where((f) => f.resolved == _resolved)
            .toList(growable: false)
      : [];
  List<ModerationAction> get actions =>
      _auth.isAdmin ? _repository.actions : [];
  void setResolved(bool value) {
    _resolved = value;
    emit();
  }

  bool act(String id, ModerationDecision decision) {
    if (!_auth.isAdmin) {
      fail('Administrator access required.');
      return false;
    }
    try {
      _repository.apply(id, decision, _auth.userId!);
      clearError();
      return true;
    } catch (_) {
      fail('This report is no longer pending. Refresh the list.');
      return false;
    }
  }

  void _reset() {
    _resolved = false;
    clearError();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _auth.removeListener(_reset);
    super.dispose();
  }
}
