// lib/features/community/data/backend_posts.dart
//
// What the feed and Reels share on the real BE: the device-local saved list and
// the post JSON adapter.
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
