// lib/features/profile/presentation/controllers/profile_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/session/session_controller.dart';
import '../../../community/data/community_api_service.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/controllers/feed_controller.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/health_profile.dart';
import '../../data/models/user_profile_model.dart';
import '../../data/profile_api_service.dart';
import '../../domain/entities/user_profile.dart';

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, UserProfile>(
        ProfileController.new);

class ProfileController extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    ref.watch(sessionControllerProvider.select((s) => s.accessToken));
    return (await ref.watch(profileApiProvider).getMe()).toEntity();
  }

  /// Throws on failure so the form can stay open with the user's input.
  Future<void> updateInfo({required String fullName, String? phone}) async {
    final me = state.requireValue;
    final updated = await ref.read(profileApiProvider).updateMe(
        me.id, UpdateUserRequestDto(fullName: fullName, phone: phone));
    final saved = updated.toEntity();
    // The session's name signs the composer, the avatar menu, new posts…
    await ref
        .read(sessionControllerProvider.notifier)
        .updateDisplayName(saved.fullName.isEmpty ? fullName : saved.fullName);
    if (BackendModules.isMock(BackendModule.profile)) {
      state = AsyncData(saved);
      return;
    }
    // The real PUT answers without `stats` and `chefApplication`.
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // Saved anyway: the profile screen shows the failed reload.
    }
  }

  Future<void> submitChefApplication(ChefApplicationRequest request) async {
    await ref.read(profileApiProvider).submitChefApplication(request);
    ref.invalidateSelf();
    await future;
  }
}

/// Health summary card on the profile (same source as the meal planner);
/// `null` until the member sets a profile up (new account).
final profileHealthProvider = FutureProvider<HealthProfile?>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  return (await ref.watch(mealPlannerApiProvider).getHealthProfile())
      ?.toEntity();
});

final myPostsProvider = FutureProvider<List<Post>>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  ref.watch(communityRevisionProvider);
  final list = await ref.watch(communityApiProvider).getMyPosts();
  return list.map((p) => p.toEntity()).toList();
});

/// The real BE has no "my posts", so the list comes from scanning the newest
/// posts of the feed: `true` when there were more than it scanned.
final myPostsTruncatedProvider = Provider<bool>((ref) {
  ref.watch(myPostsProvider);
  final api = ref.watch(communityApiProvider);
  return api is RemoteCommunityApiService && api.myPostsTruncated;
});

final savedPostsProvider = FutureProvider<List<Post>>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  ref.watch(communityRevisionProvider);
  final list = await ref.watch(communityApiProvider).getSavedPosts();
  return list.map((p) => p.toEntity()).toList();
});

typedef ProfileStats = ({int posts, int likesReceived, int saved});

/// Counts on the "Tôi" tab, taken from the same lists as "Bài viết của tôi" /
/// "Đã lưu" so they follow new posts, likes and saves in this session.
/// `null` until both lists have loaded once (the screen then falls back to
/// the stats in `GET /users/me`).
final profileStatsProvider = Provider<ProfileStats?>((ref) {
  final mine = ref.watch(myPostsProvider);
  final saved = ref.watch(savedPostsProvider);
  if (!mine.hasValue || !saved.hasValue) return null;
  final posts = mine.requireValue;
  return (
    posts: posts.length,
    likesReceived: posts.fold(0, (sum, p) => sum + p.likeCount),
    saved: saved.requireValue.length,
  );
});
