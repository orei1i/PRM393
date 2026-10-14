// lib/core/widgets/guest_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_controller.dart';
import '../theme/vl_colors.dart';
import 'google_sign_in_button.dart';

/// Shows [child] to members. Guests see what they'd unlock + 1-tap sign-in.
/// Gates sit on intent (personal plan, fridge scan), never on reading.
class GuestGate extends ConsumerWidget {
  const GuestGate({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.benefits,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<String> benefits;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    if (!isGuest) return child;

    return SafeArea(
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
                Text(message, style: context.textStyles.bodyLarge?.copyWith(color: context.vl.muted)),
                const SizedBox(height: 20),
                for (final b in benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 20, color: context.vl.success),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: context.textStyles.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const GoogleSignInButton(),
                const SizedBox(height: 12),
                Text(
                  'Bạn vẫn xem công thức và hỏi AI 3 lần miễn phí mà không cần tài khoản.',
                  style: context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
