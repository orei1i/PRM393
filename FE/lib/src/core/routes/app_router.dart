import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../bootstrap.dart';
import '../widgets/app_widgets.dart';
import 'app_shell.dart';
import '../../features/explore/presentation/views/explore_view.dart';
import '../../features/trial_chat/presentation/views/trial_chat_view.dart';
import '../../features/community/presentation/views/community_feed_view.dart';
import '../../features/community/presentation/views/post_detail_view.dart';
import '../../features/community/presentation/views/create_post_view.dart';
import '../../features/community/presentation/views/video_player_mock_view.dart';
import '../../features/community/presentation/view_models/post_detail_view_model.dart';
import '../../features/community/presentation/view_models/create_post_view_model.dart';
import '../../features/community/presentation/view_models/video_player_view_model.dart';
import '../../features/ai_nutrition/presentation/views/ai_nutrition_chat_view.dart';
import '../../features/meal_planner/presentation/views/weekly_meal_calendar_view.dart';
import '../../features/meal_planner/presentation/views/bmi_calculator_view.dart';
import '../../features/discovery/presentation/views/nearby_shops_view.dart';
import '../../features/user_profile/presentation/views/profile_view.dart';
import '../../features/user_profile/presentation/views/user_content_management_view.dart';
import '../../features/admin_dashboard/presentation/views/admin_dashboard_view.dart';
import '../../features/admin_moderation/presentation/views/content_moderation_view.dart';
import '../../features/admin_categories/presentation/views/category_management_view.dart';
import '../../features/admin_ai_ops/presentation/views/ai_operations_view.dart';

GoRouter createAppRouter(AppDependencies d, {String? initialLocation}) {
  var lastRole = d.auth.role;
  return GoRouter(
    initialLocation: initialLocation ?? d.auth.homeRoute,
    refreshListenable: d.auth,
    redirect: (context, state) {
      if (lastRole != d.auth.role) {
        lastRole = d.auth.role;
        return d.auth.homeRoute;
      }
      final path = state.uri.path;
      if (path == '/') return d.auth.homeRoute;
      if (path.startsWith('/admin') && !d.auth.isAdmin) return d.auth.homeRoute;
      const memberPaths = [
        '/community',
        '/assistant',
        '/planner',
        '/bmi',
        '/discover',
        '/profile',
        '/my-content',
        '/create',
      ];
      if (d.auth.isGuest &&
          (memberPaths.contains(path) || path.startsWith('/edit/'))) {
        return '/explore';
      }
      if (!d.auth.isGuest && path == '/trial') return '/assistant';
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: EmptyState(
        title: 'This path is a little overgrown.',
        message: 'The page could not be found.',
        action: FilledButton(
          onPressed: () => context.go(d.auth.homeRoute),
          child: const Text('Back to VeganLife'),
        ),
      ),
    ),
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/explore', builder: (_, _) => const ExploreView()),
          GoRoute(
            path: '/trial',
            builder: (_, _) => const TrialChatView(),
            onExit: (_, _) {
              d.trialChat.cancel();
              return true;
            },
          ),
          GoRoute(
            path: '/community',
            builder: (_, _) => const CommunityFeedView(),
          ),
          GoRoute(
            path: '/post/:id',
            builder: (context, state) => ChangeNotifierProvider(
              key: ValueKey(
                'post-${state.pathParameters['id']}-${d.auth.role}',
              ),
              create: (_) => PostDetailViewModel(
                d.community,
                d.auth,
                state.pathParameters['id']!,
              ),
              child: const PostDetailView(),
            ),
          ),
          GoRoute(
            path: '/create',
            builder: (context, state) => ChangeNotifierProvider(
              key: ValueKey('create-${d.auth.role}'),
              create: (_) =>
                  CreatePostViewModel(d.community, d.auth, d.categories),
              child: const CreatePostView(),
            ),
          ),
          GoRoute(
            path: '/edit/:id',
            builder: (context, state) => ChangeNotifierProvider(
              key: ValueKey(
                'edit-${state.pathParameters['id']}-${d.auth.role}',
              ),
              create: (_) => CreatePostViewModel(
                d.community,
                d.auth,
                d.categories,
                postId: state.pathParameters['id'],
              ),
              child: const CreatePostView(),
            ),
          ),
          GoRoute(
            path: '/video/:id',
            builder: (context, state) => ChangeNotifierProvider(
              key: ValueKey('video-${state.pathParameters['id']}'),
              create: (_) => VideoPlayerViewModel(
                d.community,
                state.pathParameters['id']!,
              ),
              child: const VideoPlayerMockView(),
            ),
          ),
          GoRoute(
            path: '/assistant',
            builder: (_, _) => const AiNutritionChatView(),
            onExit: (_, _) {
              d.chat.cancel();
              return true;
            },
          ),
          GoRoute(
            path: '/planner',
            builder: (_, _) => const WeeklyMealCalendarView(),
          ),
          GoRoute(path: '/bmi', builder: (_, _) => const BmiCalculatorView()),
          GoRoute(
            path: '/discover',
            builder: (_, _) => const NearbyShopsView(),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileView()),
          GoRoute(
            path: '/my-content',
            builder: (_, _) => const UserContentManagementView(),
          ),
          GoRoute(
            path: '/admin',
            builder: (_, _) => const AdminDashboardView(),
          ),
          GoRoute(
            path: '/admin/moderation',
            builder: (_, _) => const ContentModerationView(),
          ),
          GoRoute(
            path: '/admin/categories',
            builder: (_, _) => const CategoryManagementView(),
          ),
          GoRoute(
            path: '/admin/ai',
            builder: (_, _) => const AiOperationsView(),
          ),
        ],
      ),
    ],
  );
}
