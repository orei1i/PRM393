// lib/core/network/api_endpoints.dart

/// Relative paths under [Env.apiBaseUrl]. Agreed contract with the backend team;
/// update here only — features never hard-code URLs. Request / response JSON
/// samples sit at the top of each feature's `data/models/*.dart` (or its API
/// service when it has no model file).
abstract final class ApiEndpoints {
  // Auth
  static const String authGoogle = '/auth/google';

  // Health profile & meal planner
  static const String healthProfile = '/health-profile/me';

  /// POST `{ startDate, empty: true }` → a week with every slot empty
  /// ("Tự lên thực đơn").
  static const String mealPlans = '/meal-plans';
  static const String currentMealPlan = '/meal-plans/current';
  static const String currentMealPlanMeals = '/meal-plans/current/meals';
  static const String generateMealPlan = '/meal-plans/generate';
  static String swapSuggestions(String planId) =>
      '/meal-plans/$planId/swap-suggestions';
  static String swapMeal(String planId) => '/meal-plans/$planId/meals';

  /// GET: dishes chefs suggested to the signed-in member ("Từ chuyên gia").
  static const String chefSuggestions = '/meal-plans/chef-suggestions';

  /// GET: "Công thức của tôi" (`recipes.created_by` = me).
  static const String myRecipes = '/users/me/recipes';

  /// The member's fridge, `user_ingredients` ("Nguyên liệu trong tủ"):
  /// GET the list, POST `{ items: [...] }` to add or refresh, DELETE to clear.
  static const String myIngredients = '/users/me/ingredients';
  static String myIngredient(String id) => '/users/me/ingredients/$id';

  // Smart kitchen (computer vision)
  static const String visionScan = '/vision/scan';
  static const String menuFromIngredients = '/meal-plans/from-ingredients';

  // RAG chatbot
  static const String guestTrial = '/chat/guest-trial';
  static String chatMessages(String sessionId) =>
      '/chat/sessions/$sessionId/messages';

  // Community feed
  /// GET `?type=&cursor=&limit=`; Reels ask for `?mediaType=Video&limit=`.
  static const String feed = '/posts';
  static const String posts = '/posts';
  static String post(String id) => '/posts/$id';
  static String postLike(String id) => '/posts/$id/like';
  static String postSave(String id) => '/posts/$id/save';
  static String postComments(String id) => '/posts/$id/comments';
  static String postReport(String id) => '/posts/$id/reports';
  static String postComment(String postId, String commentId) =>
      '/posts/$postId/comments/$commentId';
  static const String uploadVideo = '/media/videos';

  // Cooking videos + AI (speech-to-text → recipe extraction)
  static String video(String id) => '/videos/$id';
  static String videoRetryExtraction(String id) => '/videos/$id/extraction';

  // Store ads ("Được tài trợ" cards; public, guests too)
  /// GET `?city=&lat=&lng=&limit=`: running campaigns, nearest first.
  static const String adsFeed = '/ads/feed';

  // Chefs & consultations
  static const String chefs = '/chefs';
  static String chef(String id) => '/chefs/$id';
  static const String myConsultations = '/consultations/me';
  static String cancelConsultation(String id) => '/consultations/$id/cancel';

  // Orders, PaymentOS payments, access grants (buyer side)
  static const String orders = '/orders';
  static const String myOrders = '/orders/me';
  static String order(String id) => '/orders/$id';
  static String cancelOrder(String id) => '/orders/$id/cancel';
  static String orderPayments(String id) => '/orders/$id/payments';
  static String payment(String id) => '/payments/$id';

  /// Mock/dev only; the real confirmation is the PaymentOS webhook (BE).
  static String mockConfirmPayment(String id) => '/payments/$id/mock-confirm';
  static String serviceContent(String id) => '/services/$id/content';

  // Chef studio (role Chef)
  static const String myChefProfile = '/chefs/me/profile';
  static const String myChefServices = '/chefs/me/services';
  static String myChefService(String id) => '/chefs/me/services/$id';
  static const String myChefOrders = '/chefs/me/orders';
  static const String myChefConsultations = '/chefs/me/consultations';

  /// [action]: `confirm` | `decline` | `start` | `complete`.
  static String chefConsultationAction(String id, String action) =>
      '/chefs/me/consultations/$id/$action';
  static const String myKnowledgeDocs = '/chefs/me/knowledge-docs';

  /// "Khách hàng": members using the chef's packages, computed from orders,
  /// access grants and consultations. GET `?status=Active|ExpiringSoon|Ended`.
  static const String myChefClients = '/chefs/me/clients';
  static String myChefClient(String userId) => '/chefs/me/clients/$userId';

  /// GET what the chef suggested to [userId]; POST a new dish for that
  /// member's "Từ chuyên gia" list.
  static String myChefClientSuggestions(String userId) =>
      '/chefs/me/clients/$userId/suggestions';

  // Chef wallet: earnings minus the 10 % platform fee, withdrawals
  static const String myChefWallet = '/chefs/me/wallet';

  /// GET `?month=yyyy-MM`.
  static const String myChefWalletTransactions =
      '/chefs/me/wallet/transactions';

  /// PUT the payout bank account.
  static const String myChefBankAccount = '/chefs/me/bank-account';

  /// GET the history, POST `{ amount }` to request a withdrawal.
  static const String myChefWithdrawals = '/chefs/me/withdrawals';

  // Restaurants & reviews
  static const String restaurants = '/restaurants';
  static String restaurant(String id) => '/restaurants/$id';
  static String restaurantReviews(String id) => '/restaurants/$id/reviews';
  static const String suggestedRestaurants = '/restaurants/suggested';

  // Global search & recipes
  static const String search = '/search';

  /// POST a member-written recipe; GET `/recipes/{id}` via [recipe].
  static const String recipes = '/recipes';
  static String recipe(String id) => '/recipes/$id';
  static String recipeRelatedPosts(String id) => '/recipes/$id/related-posts';

  // Current user (BE: UsersController) + chef application
  static const String me = '/users/me';
  static String user(String id) => '/users/$id';
  static const String myPosts = '/users/me/posts';
  static const String mySavedPosts = '/users/me/saved-posts';
  static const String myComments = '/users/me/comments';
  static const String chefApplications = '/chef-applications';
  static const String myChefApplication = '/chef-applications/me';
}
