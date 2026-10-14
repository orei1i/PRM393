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
}
