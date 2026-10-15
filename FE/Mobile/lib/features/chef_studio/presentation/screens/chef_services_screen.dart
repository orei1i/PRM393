// lib/features/chef_studio/presentation/screens/chef_services_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/data/models/service_model.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_only_gate.dart';
import 'service_form_screen.dart';

/// "Dịch vụ của tôi": what the chef sells (consults, courses, VIP menus).
class ChefServicesScreen extends ConsumerWidget {
  const ChefServicesScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefServicesScreen());

  static Future<void> _openForm(BuildContext context,
      {ServiceDto? editing}) async {
    final message = await Navigator.of(context)
        .push(ServiceFormScreen.route(editing: editing));
    if (message != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChef = ref.watch(sessionControllerProvider.select((s) => s.isChef));
    return Scaffold(
      appBar: AppBar(title: const Text('Dịch vụ của tôi')),
      floatingActionButton: isChef
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Thêm dịch vụ'),
            )
          : null,
      body: const ChefOnlyGate(child: _Body(onOpen: _openForm)),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.onOpen});

  final Future<void> Function(BuildContext, {ServiceDto? editing}) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefServicesProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (services) => services.isEmpty
          ? Center(
              child: SingleChildScrollView(
                child: EmptyStateView(
                  icon: Icons.storefront_outlined,
                  title: 'Chưa có dịch vụ',
                  message:
                      'Thêm buổi tư vấn 1–1, khoá học hoặc thực đơn VIP để khách đặt mua.',
                  actionLabel: 'Thêm dịch vụ',
                  onAction: () => onOpen(context),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(chefServicesProvider.future),
              child: ListView.separated(
                // Clear of the "Thêm dịch vụ" button.
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
                itemCount: services.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ServiceRow(
                  service: services[i],
                  onTap: () => onOpen(context, editing: services[i]),
                ),
              ),
            ),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(chefServicesProvider)),
        ),
      ),
      loading: () => const ListSkeleton(height: 96),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.onTap});

  final ServiceDto service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = service.durationMinutes;
    final days = service.type.accessDays;
    return VLCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.title,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    serviceTypeTag(context, service.type),
                    if (minutes != null)
                      VLTag.neutral(context, '$minutes phút'),
                    if (days != null)
                      VLTag.neutral(context, 'Truy cập $days ngày'),
                    Text(formatVnd(service.price),
                        style: context.textStyles.titleSmall?.copyWith(
                            color: context.colors.primary,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.vl.muted),
        ],
      ),
    );
  }
}
