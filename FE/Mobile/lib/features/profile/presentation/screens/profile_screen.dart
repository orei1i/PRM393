// lib/features/profile/presentation/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_nav.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/settings/theme_mode_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../booking/presentation/controllers/booking_controllers.dart';
import '../../../booking/presentation/screens/booking_history_screen.dart';
import '../../../booking/presentation/screens/chef_booking_inbox_screen.dart';
import '../../../chef_studio/presentation/screens/chef_knowledge_docs_screen.dart';
import '../../../chef_studio/presentation/screens/chef_profile_edit_screen.dart';
import '../../../chef_studio/presentation/screens/chef_wallet_screen.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../../meal_planner/presentation/screens/body_metrics_screen.dart';
import '../../../meal_planner/presentation/screens/health_profile_edit_screen.dart';
import '../../../meal_planner/presentation/widgets/health_header_card.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';
import 'chef_application_screen.dart';
import 'edit_profile_screen.dart';
import 'my_posts_screen.dart';

/// Tab "Tôi": account, health summary, my content, "Lịch sử tư vấn",
/// settings; chefs also get the "Chuyên gia" section (requests, wallet,
/// profile & prices, knowledge docs).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tôi')),
      body: const GuestGate(
        icon: Icons.person_outline_rounded,
        title: 'Hồ sơ VeganLife của bạn',
        message:
            'Đăng nhập để lưu công thức, đăng bài và đặt chuyên gia lên thực đơn.',
        benefits: [
          'Bài viết, video và công thức đã lưu ở một nơi',
          'Hồ sơ sức khoẻ dùng chung cho thực đơn AI và chuyên gia',
          'Đăng ký trở thành chuyên gia đã xác minh',
        ],
        child: _ProfileBody(),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileControllerProvider);
    return switch (async) {
      AsyncData(:final value) => RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(profileControllerProvider)
              ..invalidate(profileHealthProvider)
              ..invalidate(myPostsProvider)
              ..invalidate(savedPostsProvider);
            await ref.read(profileControllerProvider.future);
          },
          child: _Loaded(profile: value),
        ),
      AsyncError(:final error) => Center(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(profileControllerProvider)),
        ),
      _ => const _ProfileSkeleton(),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.profile});

  final UserProfile profile;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
            'Bạn vẫn xem được bảng tin và công thức ở chế độ khách.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ở lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(sessionControllerProvider.notifier).signOut();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    }
  }

  void _pickTheme(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final current = ref.watch(themeModeProvider);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in ThemeMode.values)
                  ListTile(
                    title: Text(mode.label),
                    trailing: current == mode
                        ? Icon(Icons.check_rounded,
                            color: context.colors.primary)
                        : null,
                    onTap: () {
                      ref.read(themeModeProvider.notifier).set(mode);
                      Navigator.pop(sheetContext);
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final stats = ref.watch(profileStatsProvider);
    // Chef studio is gated on the session role (D10).
    final isChef = ref.watch(sessionControllerProvider.select((s) => s.isChef));
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, floatingBarClearance(context)),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _AccountCard(profile: profile),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatTile(
                value: stats?.posts ?? profile.postCount, label: 'Bài viết'),
            const SizedBox(width: 8),
            _StatTile(
                value: stats?.likesReceived ?? profile.likesReceived,
                label: 'Lượt thích'),
            const SizedBox(width: 8),
            _StatTile(
                value: stats?.saved ?? profile.savedCount, label: 'Đã lưu'),
          ],
        ),
        const SizedBox(height: 12),
        const _HealthCard(),
        const SizedBox(height: 12),
        _ChefApplicationCard(profile: profile, isChef: isChef),
        const SizedBox(height: 16),
        if (isChef) ...[
          const _ChefSection(),
          const SizedBox(height: 12),
        ],
        _Section(
          title: 'Nội dung & tư vấn',
          children: [
            _MenuTile(
              icon: Icons.article_outlined,
              title: 'Bài viết của tôi',
              onTap: () => Navigator.of(context)
                  .push(MyPostsScreen.route(initialTab: 0)),
            ),
            _MenuTile(
              icon: Icons.bookmark_border_rounded,
              title: 'Đã lưu',
              onTap: () => Navigator.of(context)
                  .push(MyPostsScreen.route(initialTab: 1)),
            ),
            _MenuTile(
              icon: Icons.history_rounded,
              title: 'Lịch sử tư vấn',
              trailing: 'Chuyên gia bạn đã đặt, kế hoạch nhận được, khiếu nại',
              onTap: () =>
                  Navigator.of(context).push(BookingHistoryScreen.route()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Cài đặt',
          children: [
            _MenuTile(
              icon: Icons.manage_accounts_outlined,
              title: 'Thông tin cá nhân',
              onTap: () =>
                  Navigator.of(context).push(EditProfileScreen.route(profile)),
            ),
            _MenuTile(
              icon: Icons.dark_mode_outlined,
              title: 'Giao diện',
              trailing: themeMode.label,
              onTap: () => _pickTheme(context, ref),
            ),
            _MenuTile(
              icon: Icons.logout_rounded,
              title: 'Đăng xuất',
              destructive: true,
              onTap: () => _signOut(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Thành viên từ ${formatDayMonth(profile.createdAt)}/${profile.createdAt.year}',
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      child: Row(
        children: [
          UserAvatar(
              name: profile.fullName,
              size: 60,
              verified: profile.isVerifiedChef),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName,
                    style: context.textStyles.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(profile.email,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted)),
                const SizedBox(height: 8),
                VLTag.neutral(context, profile.role.label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: VLCard(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(formatInt(value),
                style: context.textStyles.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(label,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends ConsumerWidget {
  const _HealthCard();

  /// 66 → "66", 65.4 → "65,4" (a check-in's decimal shows).
  static String _kg(double kg) =>
      kg == kg.roundToDouble() ? '${kg.round()}' : formatDecimal(kg);

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final saved =
        await Navigator.of(context).push(HealthProfileEditScreen.route());
    if (saved == true) ref.invalidate(profileHealthProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileHealthProvider);
    return VLCard(
      onTap: () => _edit(context, ref),
      child: switch (async) {
        AsyncData(value: null) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      color: context.colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Hồ sơ sức khoẻ',
                        style: context.textStyles.titleMedium),
                  ),
                  Text('Thiết lập',
                      style: context.textStyles.labelLarge?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right_rounded,
                      color: context.colors.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Bạn chưa có hồ sơ sức khoẻ. Thêm chiều cao, cân nặng, mục tiêu '
                'và dị ứng để AI lên thực đơn phù hợp.',
                style: context.textStyles.bodyMedium,
              ),
            ],
          ),
        AsyncData(:final value?) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      color: context.colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Hồ sơ sức khoẻ',
                        style: context.textStyles.titleMedium),
                  ),
                  Text('Sửa',
                      style: context.textStyles.labelLarge?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w700)),
                  Icon(Icons.chevron_right_rounded,
                      color: context.colors.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${formatDecimal(value.heightCm, digits: 0)} cm · ${_kg(value.weightKg)} kg · '
                'BMI ${formatDecimal(value.bmi)} (${value.bmiCategory().label}) · ${value.goal.label}',
                style: context.textStyles.bodyMedium,
              ),
              if (value.allergies.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // Wraps at large text sizes (a VLTag would overflow).
                    for (final a in value.allergies)
                      StatusPill(
                        label: 'Dị ứng ${allergenLabel(a).toLowerCase()}',
                        icon: Icons.warning_amber_rounded,
                        background: context.vl.cautionContainer,
                        foreground: context.vl.onCautionContainer,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Dùng cho thực đơn AI và chỉ chia sẻ với chuyên gia khi bạn đặt chuyên gia.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              MetricsLinkRow(
                onTap: () => AppNav.open(
                    Navigator.of(context), BodyMetricsScreen.route()),
              ),
            ],
          ),
        AsyncError() => Text('Chưa tải được hồ sơ sức khoẻ.',
            style: context.textStyles.bodyMedium),
        _ => const Shimmer(child: SkeletonBox(height: 64)),
      },
    );
  }
}

class _ChefApplicationCard extends StatelessWidget {
  const _ChefApplicationCard({required this.profile, required this.isChef});

  final UserProfile profile;

  /// Signed in with the Chef role: the card opens "Yêu cầu tư vấn".
  final bool isChef;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (
      IconData icon,
      Color bg,
      Color fg,
      String title,
      String body,
      String? action
    ) = switch (profile.chefApplication) {
      _ when isChef => (
          Icons.verified_rounded,
          vl.successContainer,
          vl.onSuccessContainer,
          'Bạn là chuyên gia đã xác minh',
          'Nhận yêu cầu thiết kế thực đơn, thoả thuận giá, soạn kế hoạch và theo dõi ví của bạn.',
          'Mở yêu cầu tư vấn',
        ),
      ChefApplicationStatus.none => (
          Icons.workspace_premium_outlined,
          vl.aiContainer,
          vl.onAiContainer,
          'Trở thành chuyên gia',
          'Bạn là đầu bếp hoặc chuyên gia dinh dưỡng? Gửi chứng chỉ để nhận thiết kế thực đơn có phí trên VeganLife.',
          'Đăng ký',
        ),
      ChefApplicationStatus.pending => (
          Icons.hourglass_top_rounded,
          vl.cautionContainer,
          vl.onCautionContainer,
          'Hồ sơ chuyên gia đang chờ duyệt',
          'Ban quản trị sẽ phản hồi trong 1–3 ngày làm việc.',
          null,
        ),
      ChefApplicationStatus.approved => (
          Icons.verified_rounded,
          vl.successContainer,
          vl.onSuccessContainer,
          'Bạn là chuyên gia đã xác minh',
          'Hồ sơ của bạn đã hiển thị trong tab Chuyên gia.',
          null,
        ),
      ChefApplicationStatus.rejected => (
          Icons.info_outline_rounded,
          vl.cautionContainer,
          vl.onCautionContainer,
          'Hồ sơ chưa được duyệt',
          profile.chefRejectReason ?? 'Vui lòng bổ sung chứng chỉ và gửi lại.',
          'Gửi lại',
        ),
    };

    return VLCard(
      color: bg,
      borderColor: Colors.transparent,
      onTap: action == null
          ? null
          : () => Navigator.of(context).push(isChef
              ? ChefBookingInboxScreen.route()
              : ChefApplicationScreen.route()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: context.textStyles.titleSmall
                        ?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: context.textStyles.bodySmall?.copyWith(color: fg)),
                // Under the text rather than beside it, so a long label
                // ("Mở yêu cầu tư vấn") never squeezes the body at large
                // text sizes.
                if (action != null) ...[
                  const SizedBox(height: 8),
                  Text('$action ›',
                      style: context.textStyles.labelLarge
                          ?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tôi › "Chuyên gia" (role Chef): the KPI row "Yêu cầu mới · Đang thực
/// hiện · Đang giữ (đ)" and the chef tools.
class _ChefSection extends ConsumerWidget {
  const _ChefSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(chefBookingStatsProvider);
    final pending = stats?.needsAction ?? 0;
    return _Section(
      title: 'Chuyên gia',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              _Kpi(
                  value: stats == null ? '–' : formatInt(stats.newRequests),
                  label: 'Yêu cầu mới'),
              _Kpi(
                  value: stats == null ? '–' : formatInt(stats.inProgress),
                  label: 'Đang thực hiện'),
              _Kpi(
                  value: stats == null ? '–' : formatInt(stats.heldNet),
                  label: 'Đang giữ (đ)'),
            ],
          ),
        ),
        _MenuTile(
          icon: Icons.inbox_outlined,
          title: 'Yêu cầu tư vấn',
          badge: pending,
          onTap: () =>
              Navigator.of(context).push(ChefBookingInboxScreen.route()),
        ),
        _MenuTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Ví của tôi',
          onTap: () => Navigator.of(context).push(ChefWalletScreen.route()),
        ),
        _MenuTile(
          icon: Icons.storefront_outlined,
          title: 'Hồ sơ & bảng giá',
          onTap: () =>
              Navigator.of(context).push(ChefProfileEditScreen.route()),
        ),
        _MenuTile(
          icon: Icons.menu_book_outlined,
          title: 'Tài liệu kiến thức',
          onTap: () =>
              Navigator.of(context).push(ChefKnowledgeDocsScreen.route()),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: context.textStyles.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Text(label,
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title,
              style: context.textStyles.labelLarge
                  ?.copyWith(color: context.vl.muted)),
        ),
        VLCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 56),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.destructive = false,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final bool destructive;

  /// Items waiting on the user ("Yêu cầu tư vấn").
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.colors.error : null;
    // The value ("Theo hệ thống") goes under the title, not beside it, so
    // it can wrap at large text sizes instead of eating the tile's width.
    return ListTile(
      leading: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: trailing == null
          ? null
          : Text(trailing!,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.muted)),
      trailing: destructive
          ? null
          : Icon(Icons.chevron_right_rounded, color: context.vl.muted),
      onTap: onTap,
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SkeletonBox(height: 96, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(height: 64, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(height: 110, radius: 16),
            SizedBox(height: 12),
            SkeletonBox(height: 72, radius: 16),
          ],
        ),
      ),
    );
  }
}
