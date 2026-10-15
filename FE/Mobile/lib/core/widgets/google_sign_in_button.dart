// lib/core/widgets/google_sign_in_button.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_exception.dart';
import 'mock_account_picker.dart';

/// "Tiếp tục với Google". Replace the leading icon with Google's official
/// button asset when the real sign-in is wired (brand guidelines).
/// In mock mode it first opens the demo account picker.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key, this.onSignedIn});

  final VoidCallback? onSignedIn;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    try {
      final signedIn = await runGoogleSignIn(context, ref,
          onSigningIn: () => setState(() => _loading = true));
      if (signedIn) widget.onSignedIn?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _signIn,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      icon: _loading
          ? const SizedBox.square(
              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.account_circle_outlined),
      label: Text(_loading ? 'Đang đăng nhập…' : 'Tiếp tục với Google'),
    );
  }
}
