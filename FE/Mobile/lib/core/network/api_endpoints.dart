// lib/core/network/api_endpoints.dart

/// Relative paths under [Env.apiBaseUrl]. Agreed contract with the backend team;
/// update here only — features never hard-code URLs.
abstract final class ApiEndpoints {
  // Auth
  static const String authGoogle = '/auth/google';

  // Health profile & meal planner
  static const String healthProfile = '/health-profile/me';
  static const String currentMealPlan = '/meal-plans/current';
  static const String generateMealPlan = '/meal-plans/generate';
  static String swapSuggestions(String planId) =>
      '/meal-plans/$planId/swap-suggestions';
  static String swapMeal(String planId) => '/meal-plans/$planId/meals';

  // Smart kitchen (computer vision)
  static const String visionScan = '/vision/scan';
  static const String menuFromIngredients = '/meal-plans/from-ingredients';

  // RAG chatbot
  static const String guestTrial = '/chat/guest-trial';
  static String chatMessages(String sessionId) =>
      '/chat/sessions/$sessionId/messages';

  // Community feed
  static const String feed = '/posts';
  static const String posts = '/posts';
  static String post(String id) => '/posts/$id';
  static String postLike(String id) => '/posts/$id/like';
  static String postSave(String id) => '/posts/$id/save';
  static String postComments(String id) => '/posts/$id/comments';
  static String postReport(String id) => '/posts/$id/reports';

  // Cooking videos + AI (speech-to-text → recipe extraction)
  static String video(String id) => '/videos/$id';
  static String videoRetryExtraction(String id) => '/videos/$id/extraction';

  // Chefs & consultations
  static const String chefs = '/chefs';
  static String chef(String id) => '/chefs/$id';
  static const String consultations = '/consultations';
  static const String myConsultations = '/consultations/me';
  static String cancelConsultation(String id) => '/consultations/$id/cancel';

  // Current user (BE: UsersController) + chef application
  static const String me = '/users/me';
  static String user(String id) => '/users/$id';
  static const String myPosts = '/users/me/posts';
  static const String mySavedPosts = '/users/me/saved-posts';
  static const String chefApplications = '/chef-applications';
  static const String myChefApplication = '/chef-applications/me';
}
