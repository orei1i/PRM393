// lib/features/chef_studio/presentation/screens/chef_client_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/domain/commerce_status.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../../meal_planner/data/chef_suggestion_api_service.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../data/models/chef_client_models.dart';
import '../../domain/chef_client_rules.dart';
import '../controllers/chef_clients_controllers.dart';
import '../widgets/chef_client_card.dart';
import '../widgets/chef_only_gate.dart';
import 'chef_bookings_screen.dart';
import 'consultation_session_screen.dart';
import 'suggestion_form_screen.dart';

/// Khách hàng › one client: the health summary they share through the
/// package (read-only), their orders and consultations with me, the dishes
/// I suggested, and "Đề xuất món" / "Xem lịch hẹn" / "Gọi video".
class ChefClientDetailScreen extends ConsumerWidget {
  const ChefClientDetailScreen({super.key, required this.userId, this.name});

  final String userId;

  /// Shown in the app bar while loading.
  final String? name;

  static Route<void> route(String userId, {String? name}) =>
      MaterialPageRoute<void>(
          builder: (_) => ChefClientDetailScreen(userId: userId, name: name));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefClientProvider(userId));
    return Scaffold(
      appBar: AppBar(
          title: Text(async.valueOrNull?.fullName ?? name ?? 'Khách hàng')),
      body: ChefOnlyGate(
        child: switch (async) {
          AsyncData(:final value) => _Body(client: value),
          AsyncError(:final error) => Center(
              child: SingleChildScrollView(
                child: ErrorStateView(
                    error: error,
                    onRetry: () => ref.invalidate(chefClientProvider(userId))),
              ),
            ),
          _ => const _DetailSkeleton(),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.client});

  final ChefClientDto client;

  Future<void> _suggest(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await Navigator.of(context)
        .push<String>(SuggestionFormScreen.route(client));
    if (sent != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(sent)));
    }
  }

  void _videoCall(BuildContext context, OrderDto consult) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.videocam_outlined),
        title: const Text('Gọi video (sắp có)'),
        content: Text(
          'Gọi video trong ứng dụng đang được phát triển. Lịch hẹn với ${client.fullName}: '
          '${formatSlot(consult.consultation!.startAt)}. Bạn vẫn có thể mở buổi tư vấn để ghi chú và hoàn thành.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context)
                ..pop()
                ..push(
                    ConsultationSessionScreen.route(consult.consultation!.id));
            },
            child: const Text('Mở buổi tư vấn'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final consult = nextConsultation(client.packages, now);
    final canSuggest = canSuggestTo(client.packages, now);

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(sentSuggestionsProvider(client.userId));
        return ref.refresh(chefClientProvider(client.userId).future);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Row(
            children: [
              UserAvatar(name: client.fullName, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.fullName,
                        style: context.textStyles.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        clientBucketTag(context, client.status),
                        StatusPill(
                          label: '${client.packages.length} đơn với bạn',
                          background: context.colors.surfaceContainer,
                          foreground: context.colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canSuggest ? () => _suggest(context) : null,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.restaurant_menu_rounded),
            label: const Text('Đề xuất món'),
          ),
          if (!canSuggest)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Khách không còn gói nào đang dùng nên chưa đề xuất món được.',
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).push(ChefBookingsScreen.route()),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.event_note_outlined),
                  label: const Text('Xem lịch hẹn'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: consult == null
                      ? null
                      : () => _videoCall(context, consult),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Gọi video'),
                ),
              ),
            ],
          ),
          if (consult == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Gọi video dùng được khi khách có lịch tư vấn sắp tới.',
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
          const SizedBox(height: 20),
          const _SectionTitle(
            'Hồ sơ sức khoẻ',
            trailing: 'Khách chia sẻ qua gói · chỉ xem',
          ),
          const SizedBox(height: 8),
          _HealthCard(health: client.health),
          const SizedBox(height: 20),
          const _SectionTitle('Đơn hàng & lịch tư vấn'),
          const SizedBox(height: 8),
          for (final order in client.packages)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PackageTile(order: order, now: now),
            ),
          const SizedBox(height: 12),
          const _SectionTitle('Món đã đề xuất'),
          const SizedBox(height: 8),
          _SentSuggestions(userId: client.userId),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        Text(title, style: context.textStyles.titleMedium),
        if (trailing != null)
          Text(trailing!,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final ClientHealthDto? health;

  @override
  Widget build(BuildContext context) {
    final h = health;
    final vl = context.vl;
    if (h == null) {
      return VLCard(
        child: Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: vl.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Khách chưa chia sẻ hồ sơ sức khoẻ.',
                  style:
                      context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
            ),
          ],
        ),
      );
    }
    final bmi = h.bmi;
    Widget fact(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted)),
              const SizedBox(height: 2),
              Text(value,
                  style: context.textStyles.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fact('Mục tiêu', h.goal.label),
              fact(
                  'BMI',
                  bmi == null
                      ? '—'
                      : '${formatDecimal(bmi)} · ${Bmi.categorize(bmi).label}'),
            ],
          ),
          if (h.heightCm != null && h.weightKg != null) ...[
            const SizedBox(height: 10),
            Text(
              '${formatInt(h.heightCm!.round())} cm · ${formatDecimal(h.weightKg!)} kg',
              style: AppTypography.mono(
                  size: 12, color: context.colors.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Text('Dị ứng',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          const SizedBox(height: 4),
          if (h.allergies.isEmpty)
            Text('Không có', style: context.textStyles.bodyMedium)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in h.allergies)
                  VLTag.caution(context, allergenLabel(a)),
              ],
            ),
          if (h.dietaryRestrictions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Chế độ ăn',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in h.dietaryRestrictions)
                  VLTag(label: dietTagLabel(d)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.order, required this.now});

  final OrderDto order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final consultation = order.consultation;
    final grant = order.accessGrant;
    return VLCard(
      padding: const EdgeInsets.all(14),
      onTap: consultation == null
          ? null
          : () => Navigator.of(context)
              .push(ConsultationSessionScreen.route(consultation.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(order.service.title,
                    style: context.textStyles.titleSmall),
              ),
              const SizedBox(width: 8),
              Text(formatVnd(order.amount),
                  style: AppTypography.mono(
                      size: 13, color: context.colors.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              serviceTypeTag(context, order.type),
              orderStatusTag(context, order.status),
              if (consultation != null)
                consultationStatusTag(context, consultation.status)
              else if (grant != null)
                grantStatusTag(context, grant.statusAt(now)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (order.payment?.paidAt != null)
                'Thanh toán ${formatStamp(order.payment!.paidAt!)}'
              else
                'Đặt ${formatStamp(order.createdAt)}',
              packageWindow(order, now),
            ].join('\n'),
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
          if (consultation?.chefNotes case final notes?
              when notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Ghi chú của bạn: $notes',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.bodySmall),
          ],
          if (order.type == ServiceType.consult &&
              consultation != null &&
              consultation.status != ConsultationStatus.cancelled)
            Align(
              alignment: Alignment.centerRight,
              child: Text('Mở buổi tư vấn ›',
                  style: context.textStyles.labelMedium
                      ?.copyWith(color: context.colors.primary)),
            ),
        ],
      ),
    );
  }
}

class _SentSuggestions extends ConsumerWidget {
  const _SentSuggestions({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    return switch (ref.watch(sentSuggestionsProvider(userId))) {
      AsyncData(:final value) when value.isEmpty => VLCard(
          child: Text(
            'Chưa đề xuất món nào. Món bạn gửi sẽ hiện trong Thực đơn › Từ chuyên gia của khách.',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
        ),
      AsyncData(:final value) => Column(
          children: [
            for (final s in value)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SentSuggestionTile(suggestion: s),
              ),
          ],
        ),
      AsyncError() => VLCard(
          child: Row(
            children: [
              Expanded(
                child: Text('Chưa tải được món đã đề xuất.',
                    style: context.textStyles.bodyMedium),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(sentSuggestionsProvider(userId)),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      _ => const Shimmer(child: SkeletonBox(height: 72, radius: 16)),
    };
  }
}

/// A dish I suggested: name, kcal, meal/day, note, when.
class SentSuggestionTile extends StatelessWidget {
  const SentSuggestionTile({super.key, required this.suggestion});

  final SentSuggestionDto suggestion;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final vl = context.vl;
    final when = [
      if (s.slot != null) s.slot!.label,
      if (s.targetDate != null) formatLongDate(s.targetDate!),
    ].join(' · ');
    return VLCard(
      padding: const EdgeInsets.all(14),
      onTap: s.recipeId == null
          ? null
          : () => Navigator.of(context)
              .push(RecipeDetailScreen.route(s.recipeId!, name: s.dishName)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child:
                      Text(s.dishName, style: context.textStyles.titleSmall)),
              if (s.calories != null)
                Text('${formatInt(s.calories!)} kcal',
                    style: AppTypography.mono(size: 12, color: vl.muted)),
            ],
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(when,
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
          if (s.note != null && s.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('“${s.note}”', style: context.textStyles.bodySmall),
          ],
          if (s.createdAt != null) ...[
            const SizedBox(height: 4),
            Text('Đã gửi ${relativeTime(s.createdAt!)}',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      child: Shimmer(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SkeletonBox(width: 56, height: 56, radius: 28),
                SizedBox(width: 14),
                SkeletonBox(width: 160, height: 20),
              ]),
              SizedBox(height: 16),
              SkeletonBox(height: 50, radius: 24),
              SizedBox(height: 20),
              SkeletonBox(height: 140, radius: 16),
              SizedBox(height: 20),
              SkeletonBox(height: 110, radius: 16),
            ],
          ),
        ),
      ),
    );
  }
}
