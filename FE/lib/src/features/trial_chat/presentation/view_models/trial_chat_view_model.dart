import '../../../ai_nutrition/presentation/view_models/ai_nutrition_view_model.dart';
import '../../domain/entities/trial_chat_limit.dart';
import '../../domain/repositories/trial_quota_repository.dart';

class TrialChatViewModel extends AiNutritionViewModel {
  TrialChatViewModel(super.repository, super.auth, this._quota);
  final TrialQuotaRepository _quota;
  TrialChatLimit get limit => _quota.limit;
  bool get shouldPromptForAuth => auth.isGuest && limit.depleted && !busy;
  @override
  bool get authorized => auth.isGuest;
  @override
  bool reserveTurn() {
    if (_quota.consume()) return true;
    fail('Your three trial turns are used. Join to keep exploring.');
    return false;
  }
}
