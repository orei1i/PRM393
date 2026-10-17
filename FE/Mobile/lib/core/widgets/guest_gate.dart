// lib/core/widgets/guest_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_navigation.dart';
import '../../features/auth/presentation/widgets/auth_widgets.dart';
import '../config/env.dart';
import '../session/session_controller.dart';
import '../theme/vl_colors.dart';

/// Shows [child] to members. Guests see what they'd unlock, with "Đăng nhập"
/// and "Tạo tài khoản"; the gate turns into [child] as soon as they are
/// signed in. Gates sit on intent (personal plan, fridge scan, Tôi), never
/// on reading.
class GuestGate extends ConsumerWidget {
  const GuestGate({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.benefits,
    required this.child,
    this.showClose = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> benefits;
  final Widget child;

  /// Adds a "Đóng" button that pops the route, for gates that fill a pushed
  /// fullscreen route without an app bar (the scanner).
  final bool showClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    if (!isGuest) return child;

    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: context.colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: context.colors.primary, size: 28),
                ),
                const SizedBox(height: 16),
                Text(title, style: context.textStyles.headlineSmall),
                const SizedBox(height: 8),
                Text(message,
                    style: context.textStyles.bodyLarge
                        ?.copyWith(color: context.vl.muted)),
                const SizedBox(height: 20),
                for (final b in benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 20, color: context.vl.success),
                        const SizedBox(width: 10),
                        Expanded(
                            child:
                                Text(b, style: context.textStyles.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                AuthChoiceButtons(
                  onLogin: () => AuthNavigation.login(Navigator.of(context)),
                  onRegister: () =>
                      AuthNavigation.register(Navigator.of(context)),
                ),
                const SizedBox(height: 12),
                Text(
                  Env.guestTrialLimit > 0
                      ? 'Bạn vẫn xem bài viết, công thức và hỏi AI ${Env.guestTrialLimit} lần miễn phí mà không cần tài khoản.'
                      : 'Bạn vẫn xem bài viết và công thức mà không cần tài khoản.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Paint the theme background ourselves: some hosts are dark (the scanner
    // route is black), and the themed text would be unreadable on them.
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: !showClose
          ? content
          : Stack(
              fit: StackFit.expand,
              children: [
                content,
                Positioned(
                  left: 0,
                  top: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton(
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
