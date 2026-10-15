// lib/features/chef_studio/presentation/screens/chef_bookings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_consultation_card.dart';
import '../widgets/chef_only_gate.dart';

/// "Lịch hẹn & đơn hàng": Chờ xác nhận · Sắp tới · Gói đã bán · Đã xong.
class ChefBookingsScreen extends ConsumerWidget {
  const ChefBookingsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefBookingsScreen());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChef = ref.watch(sessionControllerProvider.select((s) => s.isChef));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lịch hẹn & đơn hàng'),
          bottom: isChef
              ? const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Chờ xác nhận'),
                    Tab(text: 'Sắp tới'),
                    Tab(text: 'Gói đã bán'),
                    Tab(text: 'Đã xong'),
                  ],
                )
              : null,
        ),
        body: const ChefOnlyGate(
          child: TabBarView(
            children: [
              _ConsultationTab(_Tab.pending),
              _ConsultationTab(_Tab.upcoming),
              _PackagesTab(),
              _ConsultationTab(_Tab.done),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Tab { pending, upcoming, done }

class _ConsultationTab extends ConsumerWidget {
  const _ConsultationTab(this.tab);

  final _Tab tab;

  bool _matches(ConsultationDto c) => switch (tab) {
        _Tab.pending => c.status == ConsultationStatus.pending,
        _Tab.upcoming => c.status == ConsultationStatus.confirmed ||
            c.status == ConsultationStatus.inProgress,
        _Tab.done => c.status == ConsultationStatus.completed ||
            c.status == ConsultationStatus.declined ||
            c.status == ConsultationStatus.cancelled,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefConsultationsProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (all) {
        final items = all.where(_matches).toList();
        if (tab == _Tab.done) {
          items.sort((a, b) => b.startAt.compareTo(a.startAt));
        }
        if (items.isEmpty) {
          final (IconData icon, String title, String message) = switch (tab) {
            _Tab.pending => (
                Icons.inbox_outlined,
                'Không có yêu cầu chờ xác nhận',
                'Yêu cầu mới hiện ở đây ngay khi khách thanh toán xong.',
              ),
            _Tab.upcoming => (
                Icons.event_available_outlined,
                'Chưa có lịch sắp tới',
                'Lịch bạn đã xác nhận sẽ hiện ở đây.',
              ),
            _Tab.done => (
                Icons.history_rounded,
                'Chưa có buổi tư vấn đã xong',
                'Buổi đã hoàn thành, đã từ chối hoặc khách huỷ sẽ hiện ở đây.',
              ),
          };
          return _RefreshableEmpty(
            onRefresh: () => ref.refresh(chefConsultationsProvider.future),
            child: EmptyStateView(icon: icon, title: title, message: message),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(chefConsultationsProvider.future),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => ChefConsultationCard(item: items[i]),
          ),
        );
      },
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(chefConsultationsProvider)),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

/// "Gói đã bán": paid courses and VIP menus with their access grant.
class _PackagesTab extends ConsumerWidget {
  const _PackagesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefOrdersProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (orders) {
        final sold = orders
            .where((o) => o.type.isPackage && o.status == OrderStatus.paid)
            .toList();
        if (sold.isEmpty) {
          return _RefreshableEmpty(
            onRefresh: () => ref.refresh(chefOrdersProvider.future),
            child: const EmptyStateView(
              icon: Icons.school_outlined,
              title: 'Chưa bán khoá học hay thực đơn VIP',
              message:
                  'Thêm dịch vụ loại Khoá học hoặc Thực đơn VIP trong "Dịch vụ của tôi".',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(chefOrdersProvider.future),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
            itemCount: sold.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _SoldCard(order: sold[i]),
          ),
        );
      },
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error, onRetry: () => ref.invalidate(chefOrdersProvider)),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _SoldCard extends StatelessWidget {
  const _SoldCard({required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    final grant = order.accessGrant;
    final buyer = order.buyer?.fullName ?? 'Khách';
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: buyer, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(buyer,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(order.service.title,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (grant != null)
                grantStatusTag(context, grant.statusAt(DateTime.now())),
              serviceTypeTag(context, order.type),
              Text(formatVnd(order.amount),
                  style: context.textStyles.titleSmall?.copyWith(
                      color: context.colors.primary,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          if (grant != null) ...[
            const SizedBox(height: 6),
            InfoRow(label: 'Cấp quyền', value: formatStamp(grant.grantedAt)),
            if (grant.expiresAt != null)
              InfoRow(
                  label: 'Hết hạn', value: formatFullDate(grant.expiresAt!)),
          ],
        ],
      ),
    );
  }
}

/// Empty state that still supports pull-to-refresh.
class _RefreshableEmpty extends StatelessWidget {
  const _RefreshableEmpty({required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
