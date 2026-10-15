// lib/core/widgets/mock_account_picker.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../session/mock_accounts.dart';
import '../session/session_controller.dart';
import '../session/user_role.dart';
import '../theme/vl_colors.dart';
import 'user_avatar.dart';

/// "Tiếp tục với Google" for every entry point (button, account menu, sign-in
/// sheet, guest gates).
///
/// Mock builds first ask which demo account to use, so testers can switch
/// between a member and a chef; the real build goes straight to Google.
/// Returns `false` when the picker is dismissed (no message: the user simply
/// changed their mind) and throws when sign-in fails. [onSigningIn] fires once
/// an account is chosen, for "Đang đăng nhập…" states.
Future<bool> runGoogleSignIn(
  BuildContext context,
  WidgetRef ref, {
  VoidCallback? onSigningIn,
}) async {
  MockAccount? account;
  if (Env.useMockData) {
    account = await showModalBottomSheet<MockAccount>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const MockAccountPicker(),
    );
    if (account == null || !context.mounted) return false;
  }
  final session = ref.read(sessionControllerProvider.notifier);
  onSigningIn?.call();
  await session.signInWithGoogle(account: account);
  return true;
}

/// Bottom sheet listing [mockAccounts]; pops with the chosen one.
class MockAccountPicker extends StatelessWidget {
  const MockAccountPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Chọn tài khoản Google (mô phỏng)',
                  style: context.textStyles.titleLarge),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Bản thử nghiệm: chọn vai trò để trải nghiệm app.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
            const SizedBox(height: 8),
            for (final account in mockAccounts)
              ListTile(
                leading: UserAvatar(
                    name: account.displayName,
                    verified: account.role == UserRole.chef),
                title: Text(account.label),
                subtitle: Text(account.email),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onTap: () => Navigator.of(context).pop(account),
              ),
          ],
        ),
      ),
    );
  }
}
