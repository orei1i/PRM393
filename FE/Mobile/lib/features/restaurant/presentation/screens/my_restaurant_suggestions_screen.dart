// lib/features/restaurant/presentation/screens/my_restaurant_suggestions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/mock_restaurant_repository.dart';
import '../../data/restaurant_api_service.dart';
import '../../domain/entities/restaurant.dart';
import '../controllers/restaurant_controllers.dart';
import 'restaurant_detail_screen.dart';
import 'submit_restaurant_screen.dart';

/// "Quán tôi đã gợi ý": what became of the member's suggestions. Chờ duyệt is
/// private until an admin decides, Đã duyệt is public and opens the restaurant,
/// Bị từ chối shows the admin's reason. While restaurants are mock there is no
/// web console to decide, so a waiting one offers "Duyệt thử" / "Từ chối thử".
class MyRestaurantSuggestionsScreen extends ConsumerWidget {
  const MyRestaurantSuggestionsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const MyRestaurantSuggestionsScreen(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mySuggestionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Quán tôi đã gợi ý')),
      body: DemoDataBanner.wrap(
        BackendModule.restaurants,
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: SingleChildScrollView(
              child: ErrorStateView(
                  error: error,
                  onRetry: () => ref.invalidate(mySuggestionsProvider)),
            ),
          ),
          data: (items) => items.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    child: EmptyStateView(
                      icon: Icons.add_business_outlined,
                      title: 'Bạn chưa gợi ý quán nào',
                      message:
                          'Bạn biết quán chay nào ngon? Gợi ý để Ban quản trị duyệt và chia sẻ với cộng đồng.',
                      actionLabel: 'Gợi ý quán mới',
                      onAction: () => Navigator.of(context)
                          .pushReplacement(SubmitRestaurantScreen.route()),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.refresh(mySuggestionsProvider.future),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _SuggestionCard(
                        key: ValueKey(items[i].restaurant.id),
                        suggestion: items[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends ConsumerStatefulWidget {
  const _SuggestionCard({super.key, required this.suggestion});

  final RestaurantSuggestion suggestion;

  @override
  ConsumerState<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<_SuggestionCard> {
  bool _deciding = false;

  Future<void> _decide({required bool approve}) async {
    final api = ref.read(restaurantApiProvider);
    if (api is! MockRestaurantRepository) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deciding = true);
    try {
      await api.demoDecide(widget.suggestion.restaurant.id, approve: approve);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(approve
              ? 'Quán đã được duyệt và hiển thị công khai'
              : 'Quán đã bị từ chối'),
        ));
      ref
        ..invalidate(restaurantListProvider)
        ..invalidate(mySuggestionsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
    if (mounted) setState(() => _deciding = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final r = s.restaurant;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final at = s.submittedAt;
    final reason = s.rejectionReason?.trim();
    final demo =
        s.isPending && BackendModules.isMock(BackendModule.restaurants);
    return VLCard(
      onTap: s.isApproved
          ? () => Navigator.of(context)
              .push(RestaurantDetailScreen.route(r.id, name: r.name))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(r.name,
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _StatusTag(status: s.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(r.address, style: muted),
          if (at != null) Text('Gửi ${relativeTime(at)}', style: muted),
          const SizedBox(height: 8),
          Text(
            switch (s.status) {
              RestaurantSuggestionStatus.pending =>
                'Đang chờ Ban quản trị duyệt. Quán sẽ hiển thị công khai sau khi được duyệt.',
              RestaurantSuggestionStatus.approved => r.isVeganCertified
                  ? 'Đã hiển thị công khai, có nhãn Chứng nhận chay.'
                  : 'Đã hiển thị công khai với nhãn Chưa chứng nhận.',
              RestaurantSuggestionStatus.rejected =>
                'Lý do: ${reason == null || reason.isEmpty ? 'Ban quản trị chưa ghi lý do.' : reason}',
            },
            style: context.textStyles.bodyMedium,
          ),
          if (demo) ...[
            const SizedBox(height: 8),
            Text(
              'Bản demo chưa có Ban quản trị, bạn có thể thử quyết định thay:',
              style: muted,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _deciding ? null : () => _decide(approve: true),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Duyệt thử'),
                ),
                TextButton.icon(
                  onPressed: _deciding ? null : () => _decide(approve: false),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Từ chối thử'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.status});

  final RestaurantSuggestionStatus status;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (background, foreground) = switch (status) {
      RestaurantSuggestionStatus.pending => (
          context.colors.secondaryContainer,
          context.colors.onSecondaryContainer
        ),
      RestaurantSuggestionStatus.approved => (
          vl.successContainer,
          vl.onSuccessContainer
        ),
      RestaurantSuggestionStatus.rejected => (
          vl.cautionContainer,
          vl.onCautionContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label,
          style: context.textStyles.labelMedium?.copyWith(color: foreground)),
    );
  }
}
