// lib/features/chef_studio/presentation/screens/chef_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/presentation/screens/chef_profile_screen.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_only_gate.dart';
import 'chef_bookings_screen.dart';
import 'chef_clients_screen.dart';
import 'chef_knowledge_docs_screen.dart';
import 'chef_profile_edit_screen.dart';
import 'chef_services_screen.dart';
import 'chef_suggestions_screen.dart';
import 'chef_wallet_screen.dart';
import 'consultation_session_screen.dart';

/// Tôi › Chuyên gia › "Bảng điều khiển chuyên gia".
class ChefDashboardScreen extends StatelessWidget {
  const ChefDashboardScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefDashboardScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bảng điều khiển chuyên gia')),
      body: const ChefOnlyGate(child: _Body()),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefDashboardProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (d) {
        final profile = d.profile;
        if (profile == null) {
          return Center(
            child: SingleChildScrollView(
              child: EmptyStateView(
                icon: Icons.badge_outlined,
                title: 'Chưa có hồ sơ chuyên gia',
                message:
                    'Tạo hồ sơ để xuất hiện trong tab Chuyên gia và bắt đầu nhận đặt lịch.',
                actionLabel: 'Tạo hồ sơ chuyên gia',
                onAction: () =>
                    Navigator.of(context).push(ChefProfileEditScreen.route()),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(chefDashboardProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatTile(
                      icon: Icons.pending_actions_rounded,
                      value: formatInt(d.pendingCount),
                      label: 'Chờ xác nhận'),
                  const SizedBox(width: 8),
                  _StatTile(
                      icon: Icons.today_rounded,
                      value: formatInt(d.todayCount),
                      label: 'Hôm nay'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatTile(
                      icon: Icons.payments_outlined,
                      value: formatVnd(d.monthRevenue),
                      label: 'Doanh thu tháng này'),
                  const SizedBox(width: 8),
                  _StatTile(
                      icon: Icons.menu_book_outlined,
                      value: formatInt(d.pendingDocs),
                      label: 'Tài liệu chờ duyệt'),
                ],
              ),
              const SizedBox(height: 16),
              Text('Lịch sắp tới', style: context.textStyles.titleMedium),
              const SizedBox(height: 8),
              _NextCard(dashboard: d),
              const SizedBox(height: 16),
              VLCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _Tile(
                      icon: Icons.event_note_outlined,
                      title: 'Lịch hẹn & đơn hàng',
                      badge: d.pendingCount,
                      onTap: () => Navigator.of(context)
                          .push(ChefBookingsScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.groups_outlined,
                      title: 'Khách hàng',
                      onTap: () =>
                          Navigator.of(context).push(ChefClientsScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.restaurant_menu_rounded,
                      title: 'Đề xuất món cho khách',
                      onTap: () => Navigator.of(context)
                          .push(ChefSuggestionsScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: d.available == null
                          ? 'Ví'
                          : 'Ví · ${formatVnd(d.available!)}',
                      onTap: () =>
                          Navigator.of(context).push(ChefWalletScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.storefront_outlined,
                      title: 'Dịch vụ của tôi',
                      onTap: () => Navigator.of(context)
                          .push(ChefServicesScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.menu_book_outlined,
                      title: 'Tài liệu kiến thức',
                      onTap: () => Navigator.of(context)
                          .push(ChefKnowledgeDocsScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.badge_outlined,
                      title: 'Hồ sơ chuyên gia',
                      onTap: () => Navigator.of(context)
                          .push(ChefProfileEditScreen.route()),
                    ),
                    const Divider(indent: 56),
                    _Tile(
                      icon: Icons.visibility_outlined,
                      title: 'Xem trang công khai',
                      onTap: () => Navigator.of(context)
                          .push(ChefProfileScreen.route(profile.id)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(chefDashboardProvider)),
        ),
      ),
      loading: () => const _DashboardSkeleton(),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: VLCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.colors.primary),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: context.textStyles.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(label,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ],
        ),
      ),
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.dashboard});

  final ChefDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    final next = dashboard.next;
    if (next == null) {
      return VLCard(
        child: Text('Chưa có lịch hẹn sắp tới.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.muted)),
      );
    }
    return VLCard(
      color: context.vl.successContainer,
      borderColor: Colors.transparent,
      onTap: () =>
          Navigator.of(context).push(ConsultationSessionScreen.route(next.id)),
      child: Row(
        children: [
          UserAvatar(name: next.buyer?.fullName ?? 'Khách', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formatSlot(next.startAt),
                    style: context.textStyles.titleSmall?.copyWith(
                        color: context.vl.onSuccessContainer,
                        fontWeight: FontWeight.w700)),
                Text(
                  '${next.buyer?.fullName ?? 'Khách'} · ${next.serviceTitle}',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.onSuccessContainer),
                ),
                const SizedBox(height: 4),
                consultationStatusTag(context, next.status),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: context.vl.onSuccessContainer),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.icon,
      required this.title,
      required this.onTap,
      this.badge = 0});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge > 0)
            Badge(
              label: Text('$badge'),
              backgroundColor: context.vl.caution,
            ),
          Icon(Icons.chevron_right_rounded, color: context.vl.muted),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Shimmer(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Row(children: [
                Expanded(child: SkeletonBox(height: 92, radius: 16)),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 92, radius: 16)),
              ]),
              SizedBox(height: 8),
              Row(children: [
                Expanded(child: SkeletonBox(height: 92, radius: 16)),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(height: 92, radius: 16)),
              ]),
              SizedBox(height: 16),
              SkeletonBox(height: 72, radius: 16),
              SizedBox(height: 16),
              SkeletonBox(height: 280, radius: 16),
            ],
          ),
        ),
      ),
    );
  }
}
