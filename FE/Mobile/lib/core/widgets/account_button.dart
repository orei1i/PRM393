// lib/core/widgets/account_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import '../session/session_controller.dart';

/// App-bar avatar: sign in (guest) or sign out (member → back to guest mode).
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final notifier = ref.read(sessionControllerProvider.notifier);
    final initial = (session.displayName?.isNotEmpty ?? false)
        ? session.displayName!.characters.first.toUpperCase()
        : null;

    return PopupMenuButton<String>(
      tooltip: session.isGuest ? 'Tài khoản (khách)' : 'Tài khoản',
      onSelected: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          if (value == 'sign_in') await notifier.signInWithGoogle();
          if (value == 'sign_out') await notifier.signOut();
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
        }
      },
      itemBuilder: (context) => [
        if (session.isGuest)
          const PopupMenuItem(
              value: 'sign_in', child: Text('Đăng nhập với Google'))
        else ...[
          PopupMenuItem(
              enabled: false,
              child: Text('Xin chào, ${session.displayName ?? 'bạn'}')),
          const PopupMenuItem(value: 'sign_out', child: Text('Đăng xuất')),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: initial == null
              ? const Icon(Icons.person_outline_rounded, size: 20)
              : Text(initial,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
