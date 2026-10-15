// lib/features/chef_studio/presentation/screens/chef_suggestions_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/models/chef_client_models.dart';
import '../../domain/chef_client_rules.dart';
import '../controllers/chef_clients_controllers.dart';
import '../widgets/chef_client_card.dart';
import '../widgets/chef_only_gate.dart';
import 'chef_client_detail_screen.dart';
import 'suggestion_form_screen.dart';

/// Chef studio › "Đề xuất món cho khách": members with a live package, VIP
/// Menu and consult clients first. "Đề xuất" composes a dish that lands in
/// the member's Thực đơn › Từ chuyên gia.
class ChefSuggestionsScreen extends ConsumerWidget {
  const ChefSuggestionsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefSuggestionsScreen());

  Future<void> _compose(BuildContext context, ChefClientDto client) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await Navigator.of(context)
        .push<String>(SuggestionFormScreen.route(client));
    if (sent != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(sent)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đề xuất món cho khách')),
      body: ChefOnlyGate(
        child: switch (ref.watch(chefClientsProvider)) {
          AsyncData(:final value) => _list(context, ref, value),
          AsyncError(:final error) => Center(
              child: SingleChildScrollView(
                child: ErrorStateView(
                    error: error,
                    onRetry: () => ref.invalidate(chefClientsProvider)),
              ),
            ),
          _ => const _Skeleton(),
        },
      ),
    );
  }

  Widget _list(
      BuildContext context, WidgetRef ref, List<ChefClientDto> clients) {
    final now = DateTime.now();
    final eligible =
        clients.where((c) => canSuggestTo(c.packages, now)).toList();
    final menu =
        eligible.where((c) => hasMenuPackage(c.packages, now)).toList();
    final others =
        eligible.where((c) => !hasMenuPackage(c.packages, now)).toList();

    if (eligible.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.restaurant_menu_rounded,
            title: 'Chưa có khách đang dùng gói',
            message:
                'Khi thành viên mua Thực đơn VIP, khoá học hoặc đặt lịch tư vấn với bạn, bạn có thể gửi món cho họ ở đây.',
          ),
        ),
      );
    }

    Widget section(String title, String hint, List<ChefClientDto> list) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.textStyles.titleMedium),
            Text(hint,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 8),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ChefClientCard(
                  client: c,
                  now: now,
                  onTap: () => Navigator.of(context).push(
                      ChefClientDetailScreen.route(c.userId, name: c.fullName)),
                  trailing: FilledButton.tonal(
                    onPressed: () => _compose(context, c),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: const Text('Đề xuất'),
                  ),
                ),
              ),
          ],
        );

    return RefreshIndicator(
      onRefresh: () => ref.refresh(chefClientsProvider.future),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          if (menu.isNotEmpty)
            section('Thực đơn VIP & tư vấn',
                'Khách bạn đang lên thực đơn hoặc sắp tư vấn.', menu),
          if (others.isNotEmpty) ...[
            if (menu.isNotEmpty) const SizedBox(height: 8),
            section('Khách khác đang dùng gói', 'Học viên khoá học của bạn.',
                others),
          ],
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...const [
              SkeletonBox(height: 112, radius: 16),
              SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
