import '../../domain/entities/trial_chat_limit.dart';
import '../../domain/repositories/trial_quota_repository.dart';

class MockTrialQuotaRepository implements TrialQuotaRepository {
  TrialChatLimit _limit = const TrialChatLimit();
  @override
  TrialChatLimit get limit => _limit;
  @override
  bool consume() {
    if (_limit.depleted) return false;
    _limit = TrialChatLimit(used: _limit.used + 1);
    return true;
  }
}
