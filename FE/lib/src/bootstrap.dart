import 'core/theme/theme_view_model.dart';
import 'features/auth/data/repositories/mock_auth_repository.dart';
import 'features/auth/presentation/view_models/auth_view_model.dart';
import 'features/community/data/repositories/mock_community_repository.dart';
import 'features/community/domain/repositories/community_repository.dart';
import 'features/community/presentation/view_models/community_feed_view_model.dart';
import 'features/explore/data/repositories/mock_explore_repository.dart';
import 'features/explore/presentation/view_models/explore_view_model.dart';
import 'features/ai_nutrition/data/repositories/mock_nutrition_repository.dart';
import 'features/ai_nutrition/domain/repositories/nutrition_repository.dart';
import 'features/ai_nutrition/presentation/view_models/ai_nutrition_view_model.dart';
import 'features/trial_chat/data/repositories/mock_trial_quota_repository.dart';
import 'features/trial_chat/presentation/view_models/trial_chat_view_model.dart';
import 'features/meal_planner/data/repositories/mock_meal_plan_repository.dart';
import 'features/meal_planner/presentation/view_models/meal_planner_view_model.dart';
import 'features/discovery/data/repositories/mock_shops_repository.dart';
import 'features/discovery/presentation/view_models/nearby_shops_view_model.dart';
import 'features/user_profile/data/repositories/mock_user_profile_repository.dart';
import 'features/user_profile/presentation/view_models/user_profile_view_model.dart';
import 'features/admin_moderation/data/repositories/mock_moderation_repository.dart';
import 'features/admin_moderation/domain/repositories/moderation_repository.dart';
import 'features/admin_moderation/presentation/view_models/content_moderation_view_model.dart';
import 'features/admin_categories/data/repositories/mock_category_repository.dart';
import 'features/admin_categories/domain/repositories/category_repository.dart';
import 'features/admin_categories/presentation/view_models/category_management_view_model.dart';
import 'features/admin_ai_ops/data/repositories/mock_ai_operations_repository.dart';
import 'features/admin_ai_ops/domain/repositories/ai_operations_repository.dart';
import 'features/admin_ai_ops/presentation/view_models/ai_operations_view_model.dart';
import 'features/admin_dashboard/data/repositories/mock_admin_dashboard_repository.dart';
import 'features/admin_dashboard/domain/repositories/admin_dashboard_repository.dart';
import 'features/admin_dashboard/presentation/view_models/admin_dashboard_view_model.dart';

/// The single composition root. ViewModels never construct their repositories.
class AppDependencies {
  AppDependencies({
    Duration chatTokenDelay = const Duration(milliseconds: 28),
  }) {
    auth = AuthViewModel(MockAuthRepository());
    community = MockCommunityRepository();
    nutrition = MockNutritionRepository(tokenDelay: chatTokenDelay);
    moderation = MockModerationRepository(community);
    categories = MockCategoryRepository(community);
    aiOperations = MockAiOperationsRepository();
    dashboardRepository = MockAdminDashboardRepository(
      community,
      moderation,
      aiOperations,
    );
    feed = CommunityFeedViewModel(community, auth, categories);
    explore = ExploreViewModel(
      community,
      auth,
      MockExploreRepository(community),
      categories,
    );
    chat = AiNutritionViewModel(nutrition, auth);
    trialChat = TrialChatViewModel(nutrition, auth, MockTrialQuotaRepository());
    planner = MealPlannerViewModel(MockMealPlanRepository(), auth);
    shops = NearbyShopsViewModel(MockShopsRepository());
    profile = UserProfileViewModel(
      MockUserProfileRepository(),
      community,
      auth,
    );
    moderationVm = ContentModerationViewModel(moderation, auth);
    categoriesVm = CategoryManagementViewModel(categories, auth);
    aiOperationsVm = AiOperationsViewModel(aiOperations, auth);
    dashboard = AdminDashboardViewModel(dashboardRepository, auth);
  }
  final theme = ThemeViewModel();
  late final AuthViewModel auth;
  late final CommunityRepository community;
  late final NutritionRepository nutrition;
  late final ModerationRepository moderation;
  late final CategoryRepository categories;
  late final AiOperationsRepository aiOperations;
  late final AdminDashboardRepository dashboardRepository;
  late final CommunityFeedViewModel feed;
  late final ExploreViewModel explore;
  late final AiNutritionViewModel chat;
  late final TrialChatViewModel trialChat;
  late final MealPlannerViewModel planner;
  late final NearbyShopsViewModel shops;
  late final UserProfileViewModel profile;
  late final ContentModerationViewModel moderationVm;
  late final CategoryManagementViewModel categoriesVm;
  late final AiOperationsViewModel aiOperationsVm;
  late final AdminDashboardViewModel dashboard;
  void dispose() {
    dashboard.dispose();
    aiOperationsVm.dispose();
    categoriesVm.dispose();
    moderationVm.dispose();
    profile.dispose();
    shops.dispose();
    planner.dispose();
    trialChat.dispose();
    chat.dispose();
    explore.dispose();
    feed.dispose();
    dashboardRepository.dispose();
    aiOperations.dispose();
    categories.dispose();
    moderation.dispose();
    community.dispose();
    auth.dispose();
    theme.dispose();
  }
}
