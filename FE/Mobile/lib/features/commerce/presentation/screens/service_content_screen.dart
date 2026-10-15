// lib/features/commerce/presentation/screens/service_content_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/models/order_model.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';

/// A bought course / VIP menu: summary + "Mở nội dung" while the access
/// grant is Active. Without one the server answers 403 `no_access`.
class ServiceContentScreen extends ConsumerWidget {
  const ServiceContentScreen({super.key, required this.serviceId, this.title});

  final String serviceId;

  /// App-bar title while loading.
  final String? title;

  static Route<void> route(String serviceId, {String? title}) =>
      MaterialPageRoute<void>(
          builder: (_) =>
              ServiceContentScreen(serviceId: serviceId, title: title));

  static bool _noAccess(Object error) =>
      error is ApiException &&
      (error.code == 'no_access' || error.statusCode == 403);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(serviceContentProvider(serviceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.title ?? title ?? 'Nội dung'),
      ),
      body: GuestGate(
        icon: Icons.lock_outline_rounded,
        title: 'Nội dung đã mua',
        message: 'Đăng nhập bằng tài khoản đã mua gói để mở nội dung.',
        benefits: const ['Xem lại khoá học, thực đơn VIP trên mọi thiết bị'],
        child: async.when(
          data: (content) => _Content(content: content),
          error: (error, _) => Center(
            child: SingleChildScrollView(
              child: _noAccess(error)
                  ? EmptyStateView(
                      icon: Icons.lock_outline_rounded,
                      title: 'Bạn chưa mua gói này',
                      message:
                          'Mua gói trên trang của chuyên gia để mở nội dung. Quyền truy cập đã hết hạn cũng cần mua lại.',
                      actionLabel: 'Quay lại',
                      onAction: () => Navigator.of(context).maybePop(),
                    )
                  : ErrorStateView(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(serviceContentProvider(serviceId))),
            ),
          ),
          loading: () => const Shimmer(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 72, radius: 16),
                  SizedBox(height: 16),
                  SkeletonBox(width: 220, height: 20),
                  SizedBox(height: 10),
                  SkeletonBox(height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(height: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.content});

  final ServiceContentDto content;

  Future<void> _open(BuildContext context, String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không mở được nội dung.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = content.contentUrl;
    final expires = content.accessExpiresAt;
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        VLCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  serviceTypeTag(context, content.type),
                  if (expires != null)
                    VLTag.neutral(
                        context, 'Hết hạn ${formatFullDate(expires)}'),
                ],
              ),
              const SizedBox(height: 8),
              Text('Bởi ${content.chefName}',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MarkdownBody(data: content.summary),
        const SizedBox(height: 20),
        if (url != null)
          FilledButton.icon(
            onPressed: () => _open(context, url),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Mở nội dung'),
          ),
      ],
    );
  }
}
