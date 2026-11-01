// lib/features/community/data/backend_posts.dart
//
// What the feed and Reels share on the real BE: the device-local saved list
// (the BE has no `/posts/{id}/save`), the ids of the member's own posts (no
// `/users/me/posts`) and the post JSON adapter.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_controller.dart';
import '../../../core/utils/media_url.dart';

/// "Đã lưu" on this device, per account (`vl.saved_posts.<userId>`), newest
/// first. Without [prefs] it only lasts as long as the object.
class SavedPostsStore {
  SavedPostsStore({required this.currentUserId, SharedPreferences? prefs})
      : _prefs = prefs;

  final String? Function() currentUserId;
  final SharedPreferences? _prefs;
  final Map<String, List<String>> _memory = {};

  static String keyFor(String userId) => 'vl.saved_posts.$userId';

  List<String> get ids {
    final user = currentUserId();
    if (user == null) return const [];
    final prefs = _prefs;
    return (prefs == null
            ? _memory[user]
            : prefs.getStringList(keyFor(user))) ??
        const [];
  }

  bool contains(String postId) => ids.contains(postId);

  Future<void> setSaved(String postId, {required bool saved}) async {
    final user = currentUserId();
    if (user == null) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
    final next = [
      if (saved) postId,
      for (final id in ids)
        if (id != postId) id,
    ];
    final prefs = _prefs;
    if (prefs == null) {
      _memory[user] = next;
    } else {
      await prefs.setStringList(keyFor(user), next);
    }
  }
}

final savedPostsStoreProvider =
    Provider<SavedPostsStore>((ref) => SavedPostsStore(
          prefs: ref.watch(sharedPreferencesProvider),
          currentUserId: () => ref.read(sessionControllerProvider).userId,
        ));

/// The member's own posts on this device, per account
/// (`vl.my_post_ids.<userId>`), newest first, at most [maxIds]. The feed only
/// lists `Published` posts, so this is how "Bài của tôi" still finds one that
/// waits for review or was rejected: GET `/posts/{id}` works for its owner.
/// Posts written on another device stay unknown until they reach the feed.
/// Without [prefs] it only lasts as long as the object.
class MyPostIdsStore {
  MyPostIdsStore({required this.currentUserId, SharedPreferences? prefs})
      : _prefs = prefs;

  static const maxIds = 100;

  final String? Function() currentUserId;
  final SharedPreferences? _prefs;
  final Map<String, List<String>> _memory = {};

  static String keyFor(String userId) => 'vl.my_post_ids.$userId';

  List<String> get ids {
    final user = currentUserId();
    if (user == null) return const [];
    final prefs = _prefs;
    return (prefs == null
            ? _memory[user]
            : prefs.getStringList(keyFor(user))) ??
        const [];
  }

  Future<void> _save(List<String> next) async {
    final user = currentUserId();
    if (user == null) return;
    final prefs = _prefs;
    if (prefs == null) {
      _memory[user] = next;
    } else {
      await prefs.setStringList(keyFor(user), next);
    }
  }

  /// A new post goes first; one seen in the feed goes after what is known.
  Future<void> add(String postId) =>
      _save([postId, ...ids.where((id) => id != postId)].take(maxIds).toList());

  Future<void> addKnown(Iterable<String> postIds) {
    final known = ids.toSet();
    final fresh = postIds.where(known.add).toList();
    if (fresh.isEmpty) return Future.value();
    return _save([...ids, ...fresh].take(maxIds).toList());
  }

  Future<void> remove(String postId) =>
      _save(ids.where((id) => id != postId).toList());
}

final myPostIdsStoreProvider = Provider<MyPostIdsStore>((ref) => MyPostIdsStore(
      prefs: ref.watch(sharedPreferencesProvider),
      currentUserId: () => ref.read(sessionControllerProvider).userId,
    ));

/// The value POST `/posts` needs for a URL [absoluteMediaUrl] made absolute:
/// the BE matches it against its media assets (an absolute URL gets a 400).
String? backendMediaUrl(String? url) {
  if (url == null || !url.startsWith('${Env.apiOrigin}/')) return url;
  return url.substring(Env.apiOrigin.length);
}

/// A BE post body as `PostDto.fromJson` should read it:
/// - `mediaUrl` absolute, to display and play it. Only for display: POST
///   `/posts` keeps sending the raw value of the upload.
/// - `savedByMe` from [saved].
Map<String, dynamic> adaptBackendPost(
    Map<String, dynamic> json, SavedPostsStore? saved) {
  final adapted = Map<String, dynamic>.of(json)
    ..['mediaUrl'] = absoluteMediaUrl(json['mediaUrl'] as String?);
  if (saved != null && saved.contains(json['id']?.toString() ?? '')) {
    adapted['savedByMe'] = true;
  }
  return adapted;
}

/// The BE clamps `pageSize` to this.
const backendMaxPageSize = 50;
