// lib/features/ads/presentation/widgets/sponsored_restaurant_row.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../restaurant/domain/entities/restaurant.dart';
import '../../../restaurant/domain/geo.dart';
import '../../../restaurant/presentation/screens/restaurant_detail_screen.dart';
import '../../../restaurant/presentation/screens/restaurant_route_screen.dart';
import '../../../restaurant/presentation/widgets/restaurant_tile.dart';
import '../../data/models/ad_feed_item.dart';
import '../controllers/ads_controller.dart';

/// The advertised store as a restaurant (for the route screen and markers).
Restaurant adRestaurant(AdFeedItemDto ad) {
  final r = ad.restaurant;
  return Restaurant(
    id: ad.restaurantId.isEmpty ? r.id : ad.restaurantId,
    name: r.name,
    address: r.address,
    isVeganCertified: r.isVeganCertified,
    location: r.hasLocation ? GeoPoint(r.latitude!, r.longitude!) : null,
    distanceKm: ad.distanceKm,
    averageRating: r.reviewCount == 0 ? null : r.averageRating,
    reviewCount: r.reviewCount,
  );
}

/// Runs an ad's CTA after counting the click: "Xem quán" and "Đặt bàn" open
/// the restaurant page (booking happens there), "Chỉ đường" the in-app route.
Future<void> openAdCta(BuildContext context, WidgetRef ref, AdFeedItemDto ad,
    {AdCtaType? as}) async {
  ref.read(adEventsProvider).click(ad.id);
  final restaurant = adRestaurant(ad);
  final cta = as ?? ad.ctaType;
  if (cta == AdCtaType.directions && restaurant.hasLocation) {
    await Navigator.of(context).push(RestaurantRouteScreen.route(restaurant));
    return;
  }
  await Navigator.of(context)
      .push(RestaurantDetailScreen.route(restaurant.id, name: restaurant.name));
}

/// The single "Được tài trợ" row at the top of "Quán chay gần bạn": shaped
/// like a restaurant row, plus the campaign headline and, when the campaign's
/// button is not "Xem quán", that button. [onShown] fires once, on the first
/// build (the screen reports the impression).
class SponsoredRestaurantRow extends ConsumerStatefulWidget {
  const SponsoredRestaurantRow({super.key, required this.ad, this.onShown});

  final AdFeedItemDto ad;
  final VoidCallback? onShown;

  @override
  ConsumerState<SponsoredRestaurantRow> createState() =>
      _SponsoredRestaurantRowState();
}

class _SponsoredRestaurantRowState
    extends ConsumerState<SponsoredRestaurantRow> {
  @override
  void initState() {
    super.initState();
    widget.onShown?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final r = adRestaurant(ad);
    final vl = context.vl;
    return Semantics(
      container: true,
      label: 'Được tài trợ: ${r.name}',
      child: Material(
        color: Color.alphaBlend(vl.cautionContainer.withValues(alpha: 0.35),
            context.colors.surface),
        child: InkWell(
          onTap: () => openAdCta(context, ref, ad, as: AdCtaType.viewStore),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RestaurantThumb(seed: r.id),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(ad.headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.bodyMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              CertificationTag(certified: r.isVeganCertified),
                              DistanceLabel(restaurant: r),
                              RatingLabel(
                                  average: r.averageRating,
                                  count: r.reviewCount),
                            ],
                          ),
                          if (ad.ctaType != AdCtaType.viewStore)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 40),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onPressed: () => openAdCta(context, ref, ad),
                                icon: Icon(switch (ad.ctaType) {
                                  AdCtaType.directions =>
                                    Icons.directions_outlined,
                                  AdCtaType.book => Icons.event_seat_outlined,
                                  AdCtaType.viewStore =>
                                    Icons.storefront_outlined,
                                }),
                                label: Text(ad.ctaLabel),
                              ),
                            ),
                        ],
                      ),
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
