// lib/features/restaurant/presentation/screens/restaurant_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/mock_persona.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';
import '../widgets/restaurant_media_strip.dart';
import '../widgets/restaurant_tile.dart';
import '../widgets/review_sheet.dart';
import '../widgets/vl_map.dart';
import 'restaurant_route_screen.dart';

/// Restaurant detail: an embedded OpenStreetMap (tap → full map), in-app
/// "Chỉ đường", "Ảnh & video" and reviews. Guests can read; writing a review
/// needs sign-in. One review per member: "Sửa đánh giá của bạn" replaces it.
/// "Mở bằng Google Maps" (turn-by-turn) lives in the app-bar overflow.
class RestaurantDetailScreen extends ConsumerWidget {
  const RestaurantDetailScreen(
      {super.key, required this.restaurantId, this.name});

  final String restaurantId;

  /// Shown in the app bar while the detail loads.
  final String? name;

  static Route<void> route(String restaurantId, {String? name}) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.restaurant(restaurantId)),
        builder: (_) =>
            RestaurantDetailScreen(restaurantId: restaurantId, name: name),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(restaurantDetailProvider(restaurantId));
    final loaded = async.valueOrNull?.restaurant;
    final title = loaded?.name ?? name ?? 'Quán chay';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [if (loaded != null) GoogleMapsMenu(restaurant: loaded)],
      ),
      body: async.when(
        data: (value) => _DetailBody(state: value),
        error: (error, _) => Center(
          child: SingleChildScrollView(
            child: error is ApiException && error.statusCode == 404
                ? EmptyStateView(
                    icon: Icons.storefront_outlined,
                    title: 'Không tìm thấy quán',
                    message: 'Quán có thể đã bị gỡ khỏi VeganLife.',
                    actionLabel: 'Quay lại',
                    onAction: () => Navigator.of(context).maybePop(),
                  )
                : ErrorStateView(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(restaurantDetailProvider(restaurantId)),
                  ),
          ),
        ),
        loading: () => const _DetailSkeleton(),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.state});

  final RestaurantDetailState state;

  Future<void> _writeReview(BuildContext context, WidgetRef ref) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để viết đánh giá quán chay.')) {
      return;
    }
    if (!context.mounted) return;
    final id = state.restaurant.id;
    final userId = mockPersonaId(ref.read(sessionControllerProvider));
    final mine =
        ref.read(restaurantDetailProvider(id)).valueOrNull?.reviewBy(userId);
    var replaced = false;
    final saved = await showReviewSheet(
      context,
      restaurantName: state.restaurant.name,
      existing: mine,
      onSubmit: (rating, comment) async {
        replaced = await ref
            .read(restaurantDetailProvider(id).notifier)
            .submitReview(rating: rating, comment: comment);
      },
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(replaced
            ? 'Đã cập nhật đánh giá của bạn.'
            : 'Cảm ơn bạn! Đánh giá đã được đăng.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = state.restaurant;
    final userId = ref.watch(sessionControllerProvider.select(mockPersonaId));
    final mine = state.reviewBy(userId);
    // The member's own review first, then everyone else's, newest first.
    final reviews = [
      if (mine != null) mine,
      ...state.reviews.where((v) => v.id != mine?.id),
    ];

    return ListView(
      padding:
          EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        FoodCover(
          seed: r.id,
          height: 150,
          child: const Center(
            child:
                Icon(Icons.storefront_rounded, color: Colors.white, size: 56),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name,
                  style: context.textStyles.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RatingLabel(average: r.averageRating, count: r.reviewCount),
                  DistanceLabel(restaurant: r),
                ],
              ),
              const SizedBox(height: 12),
              _CertificationNote(certified: r.isVeganCertified),
              const SizedBox(height: 12),
              _InfoRow(icon: Icons.place_outlined, text: r.address),
              if (r.createdByName != null)
                _InfoRow(
                  icon: Icons.person_add_alt_outlined,
                  text: 'Được gợi ý bởi ${r.createdByName}',
                ),
              const SizedBox(height: 4),
              _LocationPreview(restaurant: r),
              if (r.hasLocation) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context)
                      .push(RestaurantRouteScreen.route(r)),
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Chỉ đường'),
                ),
              ],
            ],
          ),
        ),
        if (state.media.isNotEmpty) ...[
          const _SectionGap(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text('Ảnh & video (${state.media.length})',
                style: context.textStyles.titleMedium),
          ),
          RestaurantMediaStrip(media: state.media),
          const SizedBox(height: 16),
        ],
        const _SectionGap(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Đánh giá', style: context.textStyles.titleMedium),
              const SizedBox(height: 12),
              _RatingSummary(state: state),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _writeReview(context, ref),
                icon: Icon(mine == null
                    ? Icons.rate_review_outlined
                    : Icons.edit_outlined),
                label: Text(
                    mine == null ? 'Viết đánh giá' : 'Sửa đánh giá của bạn'),
              ),
            ],
          ),
        ),
        if (reviews.isEmpty)
          const EmptyStateView(
            icon: Icons.rate_review_outlined,
            title: 'Chưa có đánh giá',
            message: 'Hãy là người đầu tiên chia sẻ cảm nhận về quán này.',
          )
        else
          for (final (i, review) in reviews.indexed) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: 64,
                  endIndent: 16,
                  color: context.vl.border),
            _ReviewTile(review: review, isMine: review.id == mine?.id),
          ],
      ],
    );
  }
}

/// The embedded 180 dp map (tap → full map), or "Quán chưa có vị trí trên
/// bản đồ" for places without coordinates.
class _LocationPreview extends StatelessWidget {
  const _LocationPreview({required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final point = r.location;
    if (point == null) {
      return Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, color: context.vl.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Quán chưa có vị trí trên bản đồ nên chưa tính được khoảng cách và chỉ đường.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'Bản đồ vị trí quán. Chạm để mở bản đồ lớn',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 180,
          child: VLMap(
            center: point,
            zoom: 16,
            interactive: false,
            onTap: () =>
                Navigator.of(context).push(RestaurantMapScreen.route(r)),
            layers: [
              MarkerLayer(
                markers: [
                  Marker(
                    point: point.latLng,
                    width: RestaurantPin.size,
                    height: RestaurantPin.size,
                    child: RestaurantPin(
                        certified: r.isVeganCertified,
                        selected: true,
                        label: r.name),
                  ),
                ],
              ),
            ],
            overlays: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: context.colors.surface,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      tooltip: 'Mở bản đồ lớn',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context)
                          .push(RestaurantMapScreen.route(r)),
                      icon: const Icon(Icons.open_in_full_rounded, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Certified badge, or the "being verified" note for member submissions.
class _CertificationNote extends StatelessWidget {
  const _CertificationNote({required this.certified});

  final bool certified;

  @override
  Widget build(BuildContext context) {
    final bg =
        certified ? context.vl.successContainer : context.vl.cautionContainer;
    final fg = certified
        ? context.vl.onSuccessContainer
        : context.vl.onCautionContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(certified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
              size: 20, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              certified
                  ? 'Chứng nhận chay: Ban quản trị VeganLife đã xác minh quán phục vụ món thuần chay.'
                  : 'Chưa chứng nhận — Ban quản trị đang xác minh',
              style: context.textStyles.bodyMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.vl.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.textStyles.bodyMedium)),
        ],
      ),
    );
  }
}

/// Average + stars + count, next to the 5★→1★ distribution bars.
class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.state});

  final RestaurantDetailState state;

  @override
  Widget build(BuildContext context) {
    final r = state.restaurant;
    final counts = state.starCounts;
    final total = state.reviews.length;
    final avg = r.averageRating;
    // Label columns grow with the text size so digits are never clipped.
    final scale = MediaQuery.textScalerOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              avg == null ? '–' : formatDecimal(avg),
              style: context.textStyles.displaySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            StarRow(rating: avg ?? 0),
            const SizedBox(height: 4),
            Text('${r.reviewCount} đánh giá',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Semantics(
                    label: '$star sao: ${counts[star - 1]} đánh giá',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        SizedBox(
                          width: scale.scale(10),
                          child: Text('$star',
                              style: context.textStyles.labelMedium),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: total == 0 ? 0 : counts[star - 1] / total,
                              minHeight: 8,
                              color: context.vl.caution,
                              backgroundColor:
                                  context.colors.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: scale.scale(24),
                          child: Text('${counts[star - 1]}',
                              textAlign: TextAlign.end,
                              style: context.textStyles.labelMedium
                                  ?.copyWith(color: context.vl.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review, required this.isMine});

  final RestaurantReview review;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final when = relativeTime(review.updatedAt ?? review.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: review.userName, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(review.userName,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (isMine) VLTag.neutral(context, 'Bạn'),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      label: '${review.rating} sao',
                      excludeSemantics: true,
                      child:
                          StarRow(rating: review.rating.toDouble(), size: 14),
                    ),
                    Text(review.isEdited ? '$when · đã sửa' : when,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(review.comment, style: context.textStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The surface-tone band between sections, like the feed's post gap.
class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.surfaceContainerHigh,
        child: const SizedBox(height: 8, width: double.infinity),
      );
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 150, radius: 0),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 220, height: 24),
                SizedBox(height: 12),
                SkeletonBox(width: 160, height: 14),
                SizedBox(height: 16),
                SkeletonBox(height: 44, radius: 12),
                SizedBox(height: 16),
                SkeletonBox(height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 240, height: 14),
                SizedBox(height: 24),
                SkeletonBox(height: 96, radius: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
