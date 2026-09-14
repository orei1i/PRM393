# Cây source VeganLife

Cây dưới liệt kê toàn bộ file trong `lib/` và bộ test được triển khai, không phải cấu trúc đề xuất. Platform scaffolds được rút gọn; build/cache, IDE metadata và các thư mục BE/FE/.qodo có sẵn không được đưa vào.

```text
Project/
├── pubspec.yaml
├── pubspec.lock
├── analysis_options.yaml
├── .gitignore
├── README.md
├── docs/
│   ├── source-tree.md
│   └── verification.md
├── lib/
│   ├── main.dart
│   └── src/
│       ├── app.dart
│       ├── bootstrap.dart
│       ├── core/
│       │   ├── constants/app_constants.dart
│       │   ├── network/backend_config.dart
│       │   ├── routes/
│       │   │   ├── app_router.dart
│       │   │   ├── app_shell.dart
│       │   │   └── navigation_section.dart
│       │   ├── state/view_model.dart
│       │   ├── theme/
│       │   │   ├── app_theme.dart
│       │   │   └── theme_view_model.dart
│       │   └── widgets/
│       │       ├── app_widgets.dart
│       │       ├── food_art.dart
│       │       └── validated_editor.dart
│       └── features/
│           ├── auth/
│           │   ├── data/repositories/mock_auth_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/auth_session.dart
│           │   │   └── repositories/auth_repository.dart
│           │   └── presentation/
│           │       ├── view_models/auth_view_model.dart
│           │       └── widgets/auth_sheet.dart
│           ├── role_switcher/
│           │   └── presentation/widgets/role_switcher.dart
│           ├── explore/
│           │   ├── data/repositories/mock_explore_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/explore_items.dart
│           │   │   └── repositories/explore_repository.dart
│           │   └── presentation/
│           │       ├── view_models/explore_view_model.dart
│           │       └── views/explore_view.dart
│           ├── trial_chat/
│           │   ├── data/repositories/mock_trial_quota_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/trial_chat_limit.dart
│           │   │   └── repositories/trial_quota_repository.dart
│           │   └── presentation/
│           │       ├── view_models/trial_chat_view_model.dart
│           │       └── views/trial_chat_view.dart
│           ├── community/
│           │   ├── data/
│           │   │   ├── datasources/community_seed.dart
│           │   │   ├── models/recipe_post_model.dart
│           │   │   └── repositories/mock_community_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/community_entities.dart
│           │   │   └── repositories/community_repository.dart
│           │   └── presentation/
│           │       ├── view_models/
│           │       │   ├── community_feed_view_model.dart
│           │       │   ├── create_post_view_model.dart
│           │       │   ├── post_detail_view_model.dart
│           │       │   └── video_player_view_model.dart
│           │       ├── views/
│           │       │   ├── community_feed_view.dart
│           │       │   ├── create_post_view.dart
│           │       │   ├── post_detail_view.dart
│           │       │   └── video_player_mock_view.dart
│           │       └── widgets/recipe_card.dart
│           ├── ai_nutrition/
│           │   ├── data/repositories/mock_nutrition_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/nutrition_entities.dart
│           │   │   └── repositories/nutrition_repository.dart
│           │   └── presentation/
│           │       ├── view_models/ai_nutrition_view_model.dart
│           │       ├── views/ai_nutrition_chat_view.dart
│           │       └── widgets/nutrition_chat_panel.dart
│           ├── meal_planner/
│           │   ├── data/repositories/mock_meal_plan_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/meal_entities.dart
│           │   │   └── repositories/meal_plan_repository.dart
│           │   └── presentation/
│           │       ├── view_models/meal_planner_view_model.dart
│           │       ├── views/
│           │       │   ├── bmi_calculator_view.dart
│           │       │   └── weekly_meal_calendar_view.dart
│           │       └── widgets/day_selector.dart
│           ├── discovery/
│           │   ├── data/repositories/mock_shops_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/shop_entities.dart
│           │   │   └── repositories/shops_repository.dart
│           │   └── presentation/
│           │       ├── view_models/nearby_shops_view_model.dart
│           │       └── views/nearby_shops_view.dart
│           ├── user_profile/
│           │   ├── data/repositories/mock_user_profile_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/user_profile.dart
│           │   │   └── repositories/user_profile_repository.dart
│           │   └── presentation/
│           │       ├── view_models/user_profile_view_model.dart
│           │       ├── views/
│           │       │   ├── profile_view.dart
│           │       │   └── user_content_management_view.dart
│           │       └── widgets/user_content_list.dart
│           ├── admin_dashboard/
│           │   ├── data/repositories/mock_admin_dashboard_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/admin_entities.dart
│           │   │   └── repositories/admin_dashboard_repository.dart
│           │   └── presentation/
│           │       ├── view_models/admin_dashboard_view_model.dart
│           │       ├── views/admin_dashboard_view.dart
│           │       └── widgets/activity_chart.dart
│           ├── admin_moderation/
│           │   ├── data/repositories/mock_moderation_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/moderation_entities.dart
│           │   │   └── repositories/moderation_repository.dart
│           │   └── presentation/
│           │       ├── view_models/content_moderation_view_model.dart
│           │       └── views/content_moderation_view.dart
│           ├── admin_categories/
│           │   ├── data/repositories/mock_category_repository.dart
│           │   ├── domain/
│           │   │   ├── entities/category_entities.dart
│           │   │   └── repositories/category_repository.dart
│           │   └── presentation/
│           │       ├── view_models/category_management_view_model.dart
│           │       └── views/category_management_view.dart
│           └── admin_ai_ops/
│               ├── data/repositories/mock_ai_operations_repository.dart
│               ├── domain/
│               │   ├── entities/ai_ops_entities.dart
│               │   └── repositories/ai_operations_repository.dart
│               └── presentation/
│                   ├── view_models/ai_operations_view_model.dart
│                   └── views/ai_operations_view.dart
├── test/
│   ├── widget_test.dart
│   ├── features/
│   │   ├── regressions_test.dart
│   │   ├── shared_state_test.dart
│   │   └── view_models_test.dart
│   ├── routing/app_router_test.dart
│   └── widgets/
│       ├── activity_chart_test.dart
│       ├── chat_regressions_test.dart
│       ├── editor_regressions_test.dart
│       ├── flow_regressions_test.dart
│       ├── input_state_test.dart
│       └── responsive_test.dart
├── integration_test/app_flow_test.dart
├── test_driver/integration_test.dart
├── android/                  # Flutter Android/Gradle scaffold
├── ios/                      # Flutter Runner/Xcode scaffold
└── web/                      # index, manifest và platform icons
```

## Lớp chịu trách nhiệm

- State ứng dụng: `AuthViewModel`, `ThemeViewModel`, các feature ViewModels trong `AppDependencies`.
- State theo route: `PostDetailViewModel`, `CreatePostViewModel`, `VideoPlayerViewModel`.
- Shared data events: community, category, moderation và AI-ops repositories; dashboard aggregate subscribe các nguồn cần thiết.
- State thuần UI: controllers/focus/scroll trong widget; route/dialog không làm validation hay mutation nghiệp vụ.
- Không có thư mục assets giả: artwork được vẽ offline trong `food_art.dart`; native/web launcher icons thuộc scaffold tương ứng.

Xem [README](../README.md) để chạy thử và [verification](verification.md) để biết phần nào đã thực thi.
