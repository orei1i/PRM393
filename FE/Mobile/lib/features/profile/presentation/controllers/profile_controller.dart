// lib/features/profile/presentation/controllers/profile_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../community/data/community_api_service.dart';
import '../../../community/domain/entities/post.dart';
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
    state = AsyncData(updated.toEntity());
  }

  Future<void> submitChefApplication(ChefApplicationRequest request) async {
    await ref.read(profileApiProvider).submitChefApplication(request);
    ref.invalidateSelf();
    await future;
  }
}

/// Health summary card on the profile (same source as the meal planner).
final profileHealthProvider = FutureProvider<HealthProfile>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  return (await ref.watch(mealPlannerApiProvider).getHealthProfile())
      .toEntity();
});

final myPostsProvider = FutureProvider<List<Post>>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  final list = await ref.watch(communityApiProvider).getMyPosts();
  return list.map((p) => p.toEntity()).toList();
});

final savedPostsProvider = FutureProvider<List<Post>>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => s.accessToken));
  final list = await ref.watch(communityApiProvider).getSavedPosts();
  return list.map((p) => p.toEntity()).toList();
});
