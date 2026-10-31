// lib/core/network/api_endpoints.dart
import '../config/env.dart';

/// Relative paths under [Env.apiBaseUrl]. Agreed contract with the backend team;
/// update here only — features never hard-code URLs. Request / response JSON
/// samples sit at the top of each feature's `data/models/*.dart` (or its API
/// service when it has no model file).
///
/// Course / VIP Menu purchases, slot consultations, chef services, chef
/// clients and chef meal suggestions were dropped for the chef meal-plan
/// booking (`/bookings`, `/chefs/me/bookings`); their paths are gone too.
/// A few paths are declared for the BE but not called by the app yet; they
/// say so in their doc comment.
abstract final class ApiEndpoints {
  // Auth (email + password)
  /// POST `{ email, password }` → `{ accessToken, refreshToken, expiresAt,
  /// user }`.
  static const String authLogin = '/auth/login';

  /// POST `{ fullName, email, password, phone? }` → same body as
  /// [authLogin]. Always creates role `User`.
  static const String authRegister = '/auth/register';

  /// POST `{ email }` → 204, whether or not the email is registered.
  static const String authForgotPassword = '/auth/forgot-password';

  /// POST `{ email, code }` → `{ resetToken }`.
  static const String authVerifyResetCode = '/auth/verify-reset-code';

  /// POST `{ resetToken, newPassword }` → 204.
  static const String authResetPassword = '/auth/reset-password';

  /// Future/unused: no client flow signs in with Google any more. Kept so
  /// the BE route stays documented.
  static const String authGoogle = '/auth/google';

  // Health profile & meal planner
  static const String healthProfile = '/health-profile/me';

  /// Body measurements ("Theo dõi cân nặng"): GET `?limit=` (≤ 100, newest
  /// first); POST `{ weightKg, waistCm?, bodyFatPct? }` → `{ measurement,
  /// profile }` (BE: POST is new).
  static const String healthMetrics = '/health-profile/me/metrics';

  /// POST `{ startDate, empty: true }` → a week with every slot empty
  /// ("Tự lên thực đơn").
  static const String mealPlans = '/meal-plans';
  static const String currentMealPlan = '/meal-plans/current';
  static const String currentMealPlanMeals = '/meal-plans/current/meals';

  /// POST `{ meals: [...] }`: many [currentMealPlanMeals] bodies at once
  /// ("Áp dụng kế hoạch vào Thực đơn") → `{ placed, skipped, days }`.
  static const String currentMealPlanMealsBatch =
      '/meal-plans/current/meals/batch';
  static const String generateMealPlan = '/meal-plans/generate';
  static String swapSuggestions(String planId) =>
      '/meal-plans/$planId/swap-suggestions';
  static String swapMeal(String planId) => '/meal-plans/$planId/meals';

  /// POST `{ message, scope: "day" | "week", date }` → an AI proposal
  /// `{ proposalId, reply, changes: [...] }` ("Chỉnh thực đơn với AI").
  static const String mealPlanAdjust = '/meal-plans/current/adjust';

  /// POST the accepted change ids of [proposalId] → the updated plan.
  static String mealPlanAdjustApply(String proposalId) =>
      '/meal-plans/current/adjust/$proposalId/apply';

  /// GET: dishes chefs suggested to the signed-in member ("Từ chuyên gia").
  static const String chefSuggestions = '/meal-plans/chef-suggestions';

  /// GET: "Công thức của tôi" (`recipes.created_by` = me).
  static const String myRecipes = '/users/me/recipes';

  /// The member's fridge, `user_ingredients` ("Nguyên liệu trong tủ"):
  /// GET the list, POST `{ items: [...] }` to add or refresh, DELETE to clear.
  static const String myIngredients = '/users/me/ingredients';
  static String myIngredient(String id) => '/users/me/ingredients/$id';

  // Ingredient nutrition DB & allergen catalog
  /// GET `?q=&veganOnly=true`.
  static const String ingredients = '/ingredients';

  /// GET the ingredient detail (nutrition, good for / caution, recipes).
  static String ingredient(String id) => '/ingredients/$id';

  /// GET `?q=`: allergen suggestions for the health profile.
  static const String allergens = '/catalog/allergens';

  // Smart kitchen (computer vision)
  /// Absolute on purpose: the host-root route, because BE bug B1 makes
  /// `/api/v1/vision/scan` answer 500. Revert to the relative `/vision/scan`
  /// once B1 is fixed.
  static String get visionScan => '${Env.apiOrigin}/vision/scan';

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

  /// DELETE a comment on the real BE (it has no route under `/posts/{id}`).
  static String commentDelete(String commentId) => '/comments/$commentId';

  /// GET `?cursor=&limit=`: replies of a top-level comment.
  static String commentReplies(String postId, String commentId) =>
      '/posts/$postId/comments/$commentId/replies';
  static const String uploadVideo = '/media/videos';

  /// POST multipart: jpg / png / webp / heic, at most 10 MB.
  static const String uploadImage = '/media/images';

  // Cooking videos + AI (speech-to-text → recipe extraction)
  static String video(String id) => '/videos/$id';
  static String videoRetryExtraction(String id) => '/videos/$id/extraction';

  // Store ads ("Được tài trợ" cards; public, guests too)
  /// GET `?city=&lat=&lng=&limit=`: running campaigns, nearest first.
  static const String adsFeed = '/ads/feed';

  /// POST once, the first time a campaign is shown.
  static String adImpression(String id) => '/ads/$id/impression';

  /// POST when the member taps a campaign.
  static String adClick(String id) => '/ads/$id/click';

  // Chef directory
  static const String chefs = '/chefs';
  static String chef(String id) => '/chefs/$id';

  // Chef meal-plan bookings (member and shared)
  /// POST a request for an N-day plan.
  static const String bookings = '/bookings';

  /// GET the signed-in member's bookings ("Lịch sử tư vấn").
  static const String myBookings = '/bookings/me';
  static String booking(String id) => '/bookings/$id';

  /// GET `?after=` (polled) / POST a chat message.
  static String bookingMessages(String id) => '/bookings/$id/messages';

  /// POST a price offer or counter-offer.
  static String bookingOffers(String id) => '/bookings/$id/offers';

  /// [action]: `accept` | `reject`.
  static String bookingOfferAction(String id, String offerId, String action) =>
      '/bookings/$id/offers/$offerId/$action';
  static String bookingCancel(String id) => '/bookings/$id/cancel';

  /// POST: creates the PaymentOS order that funds the escrow.
  static String bookingPayments(String id) => '/bookings/$id/payments';

  /// GET the delivered plan days.
  static String bookingPlan(String id) => '/bookings/$id/plan';

  /// PUT the member's feedback for one plan day.
  static String bookingDayFeedback(String id, int dayIndex) =>
      '/bookings/$id/plan/days/$dayIndex/feedback';

  /// GET / POST the complaint (with evidence).
  static String bookingComplaint(String id) => '/bookings/$id/complaint';

  // Booking payments: the order created by [bookingPayments] → PaymentOS QR
  // (confirmed by the PaymentOS webhook on the BE, never by the app).
  static String order(String id) => '/orders/$id';

  /// POST: a new QR after the last one expired or failed.
  static String orderPayments(String id) => '/orders/$id/payments';

  /// GET, polled every 3 s by the payment screen.
  static String payment(String id) => '/payments/$id';

  // Chef tools (role Chef, Tôi › Chuyên gia)
  /// GET / PUT "Hồ sơ & bảng giá".
  static const String myChefProfile = '/chefs/me/profile';

  /// GET / POST "Tài liệu kiến thức" for the RAG chatbot.
  static const String myKnowledgeDocs = '/chefs/me/knowledge-docs';

  /// GET `?status=`: the chef's booking inbox ("Yêu cầu tư vấn").
  static const String myChefBookings = '/chefs/me/bookings';

  /// POST `{ reason }`.
  static String chefBookingDecline(String id) =>
      '/chefs/me/bookings/$id/decline';

  /// PUT a draft plan day.
  static String chefPlanDay(String id, int dayIndex) =>
      '/chefs/me/bookings/$id/plan/days/$dayIndex';

  /// POST: sends one day (DailyFeedback).
  static String chefPlanDaySend(String id, int dayIndex) =>
      '/chefs/me/bookings/$id/plan/days/$dayIndex/send';

  /// POST: sends every day at once (OneShot).
  static String chefPlanSendAll(String id) =>
      '/chefs/me/bookings/$id/plan/send';

  /// POST `{ text, links? }`: the chef's answer to a complaint.
  static String chefComplaintResponse(String id) =>
      '/chefs/me/bookings/$id/complaint/response';

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

  /// GET the restaurant's photos and videos (`restaurant_media`).
  static String restaurantMedia(String id) => '/restaurants/$id/media';

  // Geocoding (server proxy; clients never call Nominatim directly)
  /// GET `?q=`.
  static const String geoSearch = '/geo/search';

  /// GET `?lat=&lng=`.
  static const String geoReverse = '/geo/reverse';

  // Global search & recipes
  static const String search = '/search';

  /// GET `?q=&limit=8`: autocomplete while typing.
  static const String searchSuggest = '/search/suggest';

  /// GET `?lat=&lng=`: the idle search page (trending, categories, …).
  static const String searchDiscover = '/search/discover';

  /// POST a member-written recipe; GET `/recipes/{id}` via [recipe].
  static const String recipes = '/recipes';
  static String recipe(String id) => '/recipes/$id';

  /// Declared, not called yet (optional; the mock computes it in [search]).
  static String recipeRelatedPosts(String id) => '/recipes/$id/related-posts';

  /// POST `{ name, swaps: [{ ingredientKey, substituteKey }], removed }` →
  /// the saved private recipe ("Lưu thành công thức của tôi"). BE: new.
  static String recipeVariants(String id) => '/recipes/$id/variants';

  /// GET `?cursor=&limit=10`: rating summary, `myReview` and reviews,
  /// newest first. BE: new.
  static String recipeReviews(String id) => '/recipes/$id/reviews';

  /// PUT `{ rating, content? }` (one per member, upsert) / DELETE the
  /// signed-in member's review. BE: new.
  static String recipeMyReview(String id) => '/recipes/$id/reviews/me';

  /// GET / PUT `{ content }` / DELETE the member's private note. BE: new.
  static String recipeMyNote(String id) => '/recipes/$id/notes/me';

  // Current user (BE: UsersController) + chef application
  static const String me = '/users/me';
  static String user(String id) => '/users/$id';
  static const String myPosts = '/users/me/posts';
  static const String mySavedPosts = '/users/me/saved-posts';
  static const String myComments = '/users/me/comments';
  static const String chefApplications = '/chef-applications';

  /// Declared, not called yet: the app reads the application status from
  /// [me] (`chefApplication.status`).
  static const String myChefApplication = '/chef-applications/me';
}
