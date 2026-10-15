// lib/features/ads/presentation/widgets/sponsored_store_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../restaurant/domain/geo.dart';
import '../../../restaurant/presentation/maps_launcher.dart';
import '../../../restaurant/presentation/screens/restaurant_detail_screen.dart';
import '../../data/models/ad_feed_item.dart';

/// Google Maps directions to the store: its coordinates, else its address
/// (same URL as the restaurant page's "Chỉ đường").
Uri directionsUri(AdRestaurantDto r) =>
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': r.hasLocation ? '${r.latitude},${r.longitude}' : r.address,
    });

/// Runs an ad's CTA: "Xem quán" and "Đặt bàn" open the restaurant page
/// (booking happens there), "Chỉ đường" opens Google Maps.
Future<void> openAdCta(BuildContext context, WidgetRef ref, AdFeedItemDto ad,
    {AdCtaType? as}) async {
  switch (as ?? ad.ctaType) {
    case AdCtaType.viewStore:
    case AdCtaType.book:
      await Navigator.of(context).push(RestaurantDetailScreen.route(
          ad.restaurantId,
          name: ad.restaurant.name));
    case AdCtaType.directions:
      final messenger = ScaffoldMessenger.of(context);
      final open = ref.read(urlOpenerProvider);
      var opened = false;
      try {
        opened = await open(directionsUri(ad.restaurant));
      } catch (_) {
        opened = false;
      }
      if (!opened) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Chưa mở được bản đồ trên máy này.')));
      }
  }
}

/// "Được tài trợ" store card, full width like the posts around it: store,
/// rating, distance, the campaign's headline and message, its CTA, and
/// "Chỉ đường" as a second action when the CTA is something else.
class SponsoredStoreCard extends ConsumerWidget {
  const SponsoredStoreCard({super.key, required this.ad});

  final AdFeedItemDto ad;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ad.restaurant;
    final vl = context.vl;
    final cs = context.colors;
    final muted = context.textStyles.bodySmall?.copyWith(color: vl.muted);
    final rating = r.averageRating;
    final facts = [
      if (rating != null)
        '★ ${formatDecimal(rating)} (${formatInt(r.reviewCount)} đánh giá)'
      else
        'Chưa có đánh giá',
      if (ad.distanceKm != null) formatDistance(ad.distanceKm),
    ].join(' · ');

    return Semantics(
      container: true,
      label: 'Được tài trợ: ${r.name}',
      child: Material(
        color: cs.surface,
        child: InkWell(
          onTap: () => openAdCta(context, ref, ad, as: AdCtaType.viewStore),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.campaign_outlined, size: 16, color: vl.muted),
                    const SizedBox(width: 6),
                    Text('Được tài trợ',
                        style: context.textStyles.labelMedium
                            ?.copyWith(color: vl.muted)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.storefront_rounded,
                          color: cs.onSecondaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              style: context.textStyles.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (r.isVeganCertified)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.verified_rounded,
                                      size: 14, color: vl.success),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text('Chứng nhận thuần chay',
                                        style: context.textStyles.labelSmall
                                            ?.copyWith(
                                                color: vl.onSuccessContainer,
                                                fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 2),
                          Text(facts, style: muted),
                          Text(r.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: muted),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(ad.headline,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (ad.message.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(ad.message, style: context.textStyles.bodyMedium),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => openAdCta(context, ref, ad),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 44)),
                      icon: Icon(switch (ad.ctaType) {
                        AdCtaType.viewStore => Icons.storefront_outlined,
                        AdCtaType.directions => Icons.directions_outlined,
                        AdCtaType.book => Icons.event_seat_outlined,
                      }),
                      label: Text(ad.ctaLabel),
                    ),
                    if (ad.ctaType != AdCtaType.directions)
                      TextButton.icon(
                        onPressed: () => openAdCta(context, ref, ad,
                            as: AdCtaType.directions),
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 44)),
                        icon: const Icon(Icons.directions_outlined),
                        label: const Text('Chỉ đường'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
