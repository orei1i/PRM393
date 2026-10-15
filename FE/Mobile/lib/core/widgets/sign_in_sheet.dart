// lib/core/widgets/sign_in_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_controller.dart';
import '../theme/vl_colors.dart';
import 'google_sign_in_button.dart';

/// Gate an *action* (like, comment, post, book a chef) — never reading.
///
/// Returns `true` immediately for members. Guests get a bottom sheet that
/// explains why sign-in is needed; returns `true` only if they signed in.
Future<bool> ensureSignedIn(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  if (!ref.read(sessionControllerProvider).isGuest) return true;
  final signedIn = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SignInSheet(reason: reason),
  );
  return signedIn ?? false;
}

class SignInSheet extends StatelessWidget {
  const SignInSheet({super.key, required this.reason});

  /// One sentence tied to the action, e.g. "Đăng nhập để bình luận".
  final String reason;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.colors.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.eco_rounded,
                  color: context.colors.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Tham gia cộng đồng VeganLife',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 6),
            Text(reason,
                style: context.textStyles.bodyLarge
                    ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 20),
            GoogleSignInButton(
                onSignedIn: () => Navigator.of(context).pop(true)),
            const SizedBox(height: 8),
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
