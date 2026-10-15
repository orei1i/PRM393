// lib/features/ads/presentation/controllers/ads_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../restaurant/data/location_service.dart';
import '../../data/ads_api_service.dart';
import '../../data/models/ad_feed_item.dart';

/// Sent as `city` for campaign targeting. No reverse geocoding yet: the
/// (mock) location is always in TP.HCM.
const adCity = 'TP. Hồ Chí Minh';

/// Sponsored store cards for Trang chủ, nearest to the user's location
/// first. Public: the same for guests and members. A failure only means the
/// feed shows no ads.
final feedAdsProvider = FutureProvider<List<AdFeedItemDto>>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  return ref.watch(adsApiProvider).getFeed(
        city: adCity,
        lat: location.point.latitude,
        lng: location.point.longitude,
        limit: 3,
      );
});

/// Candidates for the single card inside a food post's detail page
/// (`sponsoredAdForPost`): more than the feed's 3, so a store serving the
/// dish the post talks about can win over a nearer one. Fetched once per
/// session; a failure only means no card.
final postAdCandidatesProvider =
    FutureProvider<List<AdFeedItemDto>>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  return ref.watch(adsApiProvider).getFeed(
        city: adCity,
        lat: location.point.latitude,
        lng: location.point.longitude,
        limit: 10,
      );
});

/// One ad after every this many posts.
const adEvery = 6;

/// A row of the feed: a post or a sponsored card.
sealed class FeedSlot<P> {
  const FeedSlot();
}

class PostSlot<P> extends FeedSlot<P> {
  const PostSlot(this.post, this.index);
  final P post;

  /// Index in the post list.
  final int index;
}

class AdSlot<P> extends FeedSlot<P> {
  const AdSlot(this.ad);
  final AdFeedItemDto ad;
}

/// [posts] with an ad after every [every] posts, each ad used once (fewer
/// ads than gaps leaves the later gaps empty).
List<FeedSlot<P>> interleaveAds<P>(List<P> posts, List<AdFeedItemDto> ads,
    {int every = adEvery}) {
  final slots = <FeedSlot<P>>[];
  var nextAd = 0;
  for (var i = 0; i < posts.length; i++) {
    slots.add(PostSlot(posts[i], i));
    if ((i + 1) % every == 0 && nextAd < ads.length) {
      slots.add(AdSlot(ads[nextAd++]));
    }
  }
  return slots;
}
