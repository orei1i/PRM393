// lib/core/widgets/sign_in_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_navigation.dart';
import '../../features/auth/presentation/widgets/auth_widgets.dart';
import '../session/session_controller.dart';
import '../theme/vl_colors.dart';
import 'app_logo.dart';

/// Gate an *action* (like, comment, post, book a chef) — never reading.
///
/// Returns `true` immediately for members. Guests get a bottom sheet that
/// explains why sign-in is needed, with "Đăng nhập" / "Tạo tài khoản";
/// returns `true` only once they signed in or signed up, so the caller can
/// carry on with the action.
Future<bool> ensureSignedIn(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  if (!ref.read(sessionControllerProvider).isGuest) return true;
  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => SignInSheet(reason: reason),
  );
  return signedIn ?? false;
}

/// Pops `true` once the guest signed in or registered (from the screens it
/// opens), `false` on "Để sau".
class SignInSheet extends StatelessWidget {
  const SignInSheet({super.key, required this.reason});

  /// One sentence tied to the action, e.g. "Đăng nhập để bình luận".
  final String reason;

  Future<void> _open(BuildContext context, {required bool register}) async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final ok = register
        ? await AuthNavigation.register(navigator)
        : await AuthNavigation.login(navigator);
    if (ok && route != null) completeRoute<Object?>(navigator, route, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VeganLifeBadge(size: 52),
            const SizedBox(height: 16),
            Text('Tham gia cộng đồng VeganLife',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 6),
            Text(reason,
                style: context.textStyles.bodyLarge
                    ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 20),
            AuthChoiceButtons(
              onLogin: () => _open(context, register: false),
              onRegister: () => _open(context, register: true),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Để sau'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
