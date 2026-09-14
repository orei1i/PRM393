import '../entities/trial_chat_limit.dart';

abstract interface class TrialQuotaRepository {
  TrialChatLimit get limit;
  bool consume();
}
