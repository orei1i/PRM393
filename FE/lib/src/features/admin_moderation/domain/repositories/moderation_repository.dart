import '../entities/moderation_entities.dart';

abstract interface class ModerationRepository {
  Stream<void> get changes;
  List<FlaggedContent> get flags;
  List<ModerationAction> get actions;
  void apply(String id, ModerationDecision decision, String actorId);
  void dispose();
}
