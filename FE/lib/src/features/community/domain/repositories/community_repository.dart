import '../entities/community_entities.dart';

abstract interface class CommunityRepository {
  Stream<void> get changes;
  List<RecipePost> get posts;
  List<Comment> get comments;
  RecipePost? find(String id);
  VoteState voteFor(String postId, String? userId);
  int votes(String postId);
  bool isSaved(String postId, String? userId);
  void toggleVote(String postId, String userId, VoteState vote);
  void toggleSaved(String postId, String userId);
  void savePost(RecipePost post);
  void deletePost(String id);
  void setHidden(String id, bool hidden);
  void saveComment(Comment comment);
  void deleteComment(String id);
  String newId();
  void dispose();
}
