// lib/features/chef_studio/presentation/widgets/chef_client_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/chef_client_models.dart';
import '../../domain/chef_client_rules.dart';

/// "15/10 → 14/11 · còn 30 ngày", "Lịch hẹn T5, 17/10 · 14:00",
/// "Đã hoàn tiền"…: when a package runs, in one line.
String packageWindow(OrderDto order, DateTime now) {
  if (order.status == OrderStatus.refunded) return 'Đã hoàn tiền';
  if (order.type == ServiceType.consult) {
    final c = order.consultation;
    if (c == null) return 'Tư vấn 1–1';
    return '${formatSlot(c.startAt)} · ${c.status.label}';
  }
  final grant = order.accessGrant;
  if (grant == null) return order.status.label;
  final start = formatDayMonth(grant.grantedAt);
  final end = grant.expiresAt;
  if (end == null) return 'Từ $start';
  final left = daysLeft(order, now) ?? 0;
  return left > 0
      ? '$start → ${formatDayMonth(end)} · còn $left ngày'
      : '$start → ${formatDayMonth(end)} · đã hết hạn';
}

Widget clientBucketTag(BuildContext context, ClientBucket bucket) {
  final vl = context.vl;
  final (Color bg, Color fg) = switch (bucket) {
    ClientBucket.active => (vl.successContainer, vl.onSuccessContainer),
    ClientBucket.expiringSoon => (vl.cautionContainer, vl.onCautionContainer),
    ClientBucket.ended => (
        context.colors.surfaceContainer,
        context.colors.onSurfaceVariant
      ),
  };
  return StatusPill(label: bucket.label, background: bg, foreground: fg);
}

/// One client on "Khách hàng": who, which package (and how long it has
/// left), the next appointment and the last dish suggested.
class ChefClientCard extends StatelessWidget {
  const ChefClientCard({
    super.key,
    required this.client,
    required this.now,
    required this.onTap,
    this.typeFilter,
    this.trailing,
  });

  final ChefClientDto client;
  final DateTime now;
  final VoidCallback onTap;

  /// Leads with a package of this type when the list is filtered.
  final ServiceType? typeFilter;

  /// E.g. "Đề xuất" on the suggestions screen.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final muted = context.textStyles.bodySmall?.copyWith(color: vl.muted);
    final package =
        primaryPackage(client.packages, client.status, now, type: typeFilter);
    final next = nextConsultation(client.packages, now);
    final others = client.packages.length - 1;
    final last = client.lastSuggestion;

    return VLCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: client.fullName, size: 44),
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
                    Text(client.fullName,
                        style: context.textStyles.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    clientBucketTag(context, client.status),
                  ],
                ),
                if (package != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(package.service.title,
                          style: context.textStyles.bodyMedium),
                      serviceTypeTag(context, package.type),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(packageWindow(package, now), style: muted),
                ],
                if (next != null &&
                    next.consultation != null &&
                    next.id != package?.id) ...[
                  const SizedBox(height: 4),
                  _Line(
                    icon: Icons.event_outlined,
                    text: 'Lịch hẹn: ${formatSlot(next.consultation!.startAt)}',
                  ),
                ],
                if (last != null) ...[
                  const SizedBox(height: 4),
                  _Line(
                    icon: Icons.restaurant_menu_rounded,
                    text: 'Đề xuất gần nhất: ${last.dishName}'
                        '${last.createdAt == null ? '' : ' · ${relativeTime(last.createdAt!)}'}',
                  ),
                ],
                if (others > 0) ...[
                  const SizedBox(height: 4),
                  Text('+$others gói khác', style: muted),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(Icons.chevron_right_rounded, color: vl.muted),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: vl.muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant)),
        ),
      ],
    );
  }
}
