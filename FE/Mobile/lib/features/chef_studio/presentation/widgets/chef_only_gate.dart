// lib/features/chef_studio/presentation/widgets/chef_only_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/widgets/state_views.dart';

/// Chef-studio screens are for the Chef role only (D10). Anyone else —
/// including a chef who signs out while a screen is open — sees this instead
/// of the content, and no chef endpoint is called.
class ChefOnlyGate extends ConsumerWidget {
  const ChefOnlyGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChef = ref.watch(sessionControllerProvider.select((s) => s.isChef));
    if (isChef) return child;
    return const Center(
      child: SingleChildScrollView(
        child: EmptyStateView(
          icon: Icons.lock_outline_rounded,
          title: 'Chỉ dành cho chuyên gia',
          message:
              'Màn hình này dành cho chuyên gia đã được VeganLife xác minh. '
              'Bạn có thể đăng ký trong Tôi › Trở thành chuyên gia.',
        ),
      ),
    );
  }
}
