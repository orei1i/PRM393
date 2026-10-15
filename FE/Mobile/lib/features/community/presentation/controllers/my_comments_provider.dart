// lib/features/community/presentation/controllers/my_comments_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import 'feed_controller.dart';

/// "Nội dung của tôi › Bình luận". Refetches on account changes and after
/// any comment is added, edited or deleted ([communityRevisionProvider]).
final myCommentsProvider = FutureProvider<List<MyComment>>((ref) async {
  ref.watch(sessionControllerProvider.select((s) => (s.accessToken, s.userId)));
  ref.watch(communityRevisionProvider);
  final list = await ref.watch(communityApiProvider).getMyComments();
  return list.map((c) => c.toEntity()).toList();
});
