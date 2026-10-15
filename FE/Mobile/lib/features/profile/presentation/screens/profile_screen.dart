// lib/features/profile/presentation/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/settings/theme_mode_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/presentation/screens/my_consultations_screen.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';
import 'chef_application_screen.dart';
import 'edit_profile_screen.dart';
import 'my_posts_screen.dart';

/// Tab "Tôi": account, health summary, my content, consultations, settings.
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
            'Đăng nhập để lưu công thức, đăng bài và đặt lịch với chuyên gia.',
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
              ..invalidate(profileHealthProvider);
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _AccountCard(profile: profile),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatTile(value: profile.postCount, label: 'Bài viết'),
            const SizedBox(width: 8),
            _StatTile(value: profile.likesReceived, label: 'Lượt thích'),
            const SizedBox(width: 8),
            _StatTile(value: profile.savedCount, label: 'Đã lưu'),
          ],
        ),
        const SizedBox(height: 12),
        const _HealthCard(),
        const SizedBox(height: 12),
        _ChefApplicationCard(profile: profile),
        const SizedBox(height: 16),
        _Section(
          title: 'Nội dung & lịch hẹn',
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
              icon: Icons.event_note_outlined,
              title: 'Lịch tư vấn',
              onTap: () =>
                  Navigator.of(context).push(MyConsultationsScreen.route()),
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
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    VLTag.neutral(context,
                        profile.isVerifiedChef ? 'Chuyên gia' : 'Thành viên'),
                    if (profile.signedInWithGoogle)
                      VLTag.neutral(context, 'Google'),
                  ],
                ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileHealthProvider);
    return VLCard(
      child: switch (async) {
        AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      color: context.colors.primary),
                  const SizedBox(width: 8),
                  Text('Hồ sơ sức khoẻ', style: context.textStyles.titleMedium),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${formatDecimal(value.heightCm, digits: 0)} cm · ${formatDecimal(value.weightKg, digits: 0)} kg · '
                'BMI ${formatDecimal(value.bmi)} (${value.bmiCategory().label}) · ${value.goal.label}',
                style: context.textStyles.bodyMedium,
              ),
              if (value.allergies.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in value.allergies)
                      VLTag.caution(
                          context, 'Dị ứng ${allergenLabel(a).toLowerCase()}')
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Dùng cho thực đơn AI và chỉ chia sẻ với chuyên gia khi bạn đặt lịch.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted),
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
  const _ChefApplicationCard({required this.profile});

  final UserProfile profile;

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
      ChefApplicationStatus.none => (
          Icons.workspace_premium_outlined,
          vl.aiContainer,
          vl.onAiContainer,
          'Trở thành chuyên gia',
          'Bạn là đầu bếp hoặc chuyên gia dinh dưỡng? Gửi chứng chỉ để nhận tư vấn có phí trên VeganLife.',
          'Đăng ký',
        ),
      ChefApplicationStatus.pending => (
          Icons.hourglass_top_rounded,
          vl.cautionContainer,
          vl.onCautionContainer,
          'Hồ sơ chuyên gia đang được duyệt',
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
          : () => Navigator.of(context).push(ChefApplicationScreen.route()),
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
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            Text(action,
                style: context.textStyles.labelLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w800)),
          ],
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
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.colors.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing!,
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted)),
          if (!destructive)
            Icon(Icons.chevron_right_rounded, color: context.vl.muted),
        ],
      ),
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
