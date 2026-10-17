// lib/features/reels/data/reels_api_service.dart
//
// GET /posts?mediaType=Video&limit=20   → FeedPage of posts (same wire as
// the feed), each with the playable file:
// { …post…, "mediaType": "Video", "mediaUrl": "https://…mp4" | null,
//   "durationSeconds": 42,                       // proposed posts.duration_seconds
//   "video": { "id": "vid_x", "durationSeconds": 724, "aiStatus": "ready",
//              "videoUrl": "https://…mp4" } | null }
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/json_helpers.dart';
import '../../community/data/community_api_service.dart';
import '../../community/data/models/post_model.dart';
import '../../community/domain/entities/post.dart';
import '../../video/data/mock/video_mock_data.dart';
import '../domain/reel.dart';

/// Public sample clips used in mock mode, so playback works without a
/// backend (Flutter's API-doc assets and MDN's CC0 sample).
const reelSampleVideos = [
  sampleVideoUrlB, // butterfly.mp4
  sampleVideoUrlA, // bee.mp4
  sampleVideoUrlC, // flower.mp4
];

class ReelDto {
  const ReelDto({required this.post, this.videoUrl, this.durationSeconds});

  factory ReelDto.fromJson(Map<String, dynamic> json) {
    final video = readMap(json['video']);
    final seconds = json['durationSeconds'] ?? video['durationSeconds'];
    return ReelDto(
      post: PostDto.fromJson(json),
      videoUrl: json['mediaUrl'] as String? ?? video['videoUrl'] as String?,
      durationSeconds: seconds == null ? null : readInt(seconds),
    );
  }

  final PostDto post;
  final String? videoUrl;
  final int? durationSeconds;

  Reel toEntity() {
    final entity = post.toEntity();
    return Reel(
      post: entity,
      videoUrl: videoUrl,
      durationSeconds: durationSeconds ?? entity.videoDurationSeconds,
    );
  }
}

/// Reels are video posts (`posts.media_type = Video`).
abstract interface class ReelsApiService {
  Future<List<ReelDto>> getReels({int limit = 20});
}

class RemoteReelsApiService implements ReelsApiService {
  RemoteReelsApiService(this._dio);

  final Dio _dio;

  @override
  Future<List<ReelDto>> getReels({int limit = 20}) => guardApi(() async {
        final res = await _dio
            .get<Map<String, dynamic>>(ApiEndpoints.feed, queryParameters: {
          'mediaType': PostMediaType.video.apiValue,
          'limit': limit,
        });
        final items = res.data?['items'];
        return items is List<Object?>
            ? items
                .whereType<Map<String, dynamic>>()
                .map(ReelDto.fromJson)
                .toList()
            : const [];
      });
}

/// The community's video posts (so like / save / comment hit the same
/// posts). A post whose `mediaUrl` is one of the public [reelSampleVideos]
/// plays it; the other mock files and uploads point at URLs that don't
/// exist, so those reels take a sample clip in turn.
class MockReelsRepository implements ReelsApiService {
  MockReelsRepository(this._community);

  final CommunityApiService _community;

  @override
  Future<List<ReelDto>> getReels({int limit = 20}) async {
    final page =
        await _community.getFeed(mediaType: PostMediaType.video, limit: limit);
    return [
      for (final (i, post) in page.items.indexed)
        ReelDto(
          post: post,
          videoUrl: reelSampleVideos.contains(post.mediaUrl)
              ? post.mediaUrl
              : reelSampleVideos[i % reelSampleVideos.length],
          durationSeconds: post.videoDurationSeconds,
        ),
    ];
  }
}

final reelsApiProvider = Provider<ReelsApiService>((ref) {
  if (Env.useMockData) {
    return MockReelsRepository(ref.watch(communityApiProvider));
  }
  return RemoteReelsApiService(ref.watch(dioProvider));
});
