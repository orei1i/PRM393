// lib/features/auth/presentation/screens/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/onboarding_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../auth_navigation.dart';
import '../widgets/auth_widgets.dart';

/// First launch only (guest, `vl.onboarded` unset): sign in, sign up or look
/// around as a guest. The app entry swaps it for the shell as soon as the
/// user signs in or taps "Khám phá không cần đăng nhập".
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  static const benefits = [
    (
      Icons.calendar_month_rounded,
      'Thực đơn chay 7 ngày theo cơ thể và mục tiêu của bạn'
    ),
    (
      Icons.document_scanner_outlined,
      'Quét tủ lạnh, AI gợi ý món từ nguyên liệu sẵn có'
    ),
    (
      Icons.forum_outlined,
      'Cộng đồng công thức và chuyên gia dinh dưỡng đồng hành'
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Center(child: VeganLifeBadge(size: 88)),
                    const SizedBox(height: 16),
                    Text(
                      'VeganLife',
                      textAlign: TextAlign.center,
                      style: context.textStyles.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: cs.primary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ăn chay khoẻ, dễ dàng mỗi ngày',
                      textAlign: TextAlign.center,
                      style: context.textStyles.titleMedium
                          ?.copyWith(color: vl.muted),
                    ),
                    const SizedBox(height: 28),
                    for (final (icon, text) in benefits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, size: 20, color: cs.primary),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(text,
                                  style: context.textStyles.bodyLarge),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(flex: 2),
                    AuthChoiceButtons(
                      onLogin: () =>
                          AuthNavigation.login(Navigator.of(context)),
                      onRegister: () =>
                          AuthNavigation.register(Navigator.of(context)),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () =>
                          ref.read(onboardingProvider.notifier).complete(),
                      child: const Text('Khám phá không cần đăng nhập'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
