// lib/core/widgets/account_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_navigation.dart';
import '../network/api_exception.dart';
import '../session/session_controller.dart';
import 'user_avatar.dart';

/// App-bar avatar. Guests: "Đăng nhập" / "Tạo tài khoản". Members: "Xin
/// chào, …" and "Đăng xuất" (back to guest mode).
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final notifier = ref.read(sessionControllerProvider.notifier);
    final name = session.displayName;

    return PopupMenuButton<String>(
      tooltip: session.isGuest ? 'Tài khoản (khách)' : 'Tài khoản',
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        try {
          switch (value) {
            case 'sign_in':
              await AuthNavigation.login(navigator);
            case 'register':
              await AuthNavigation.register(navigator);
            case 'sign_out':
              await notifier.signOut();
          }
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
        }
      },
      itemBuilder: (context) => [
        if (session.isGuest) ...const [
          PopupMenuItem(value: 'sign_in', child: Text('Đăng nhập')),
          PopupMenuItem(value: 'register', child: Text('Tạo tài khoản')),
        ] else ...[
          PopupMenuItem(
              enabled: false,
              child: Text('Xin chào, ${session.displayName ?? 'bạn'}')),
          const PopupMenuItem(value: 'sign_out', child: Text('Đăng xuất')),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: name == null || name.isEmpty
            ? CircleAvatar(
                radius: 18,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.person_outline_rounded, size: 20),
              )
            : UserAvatar(name: name, size: 36),
      ),
    );
  }
}
