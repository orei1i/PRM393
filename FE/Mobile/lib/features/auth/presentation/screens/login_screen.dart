// lib/features/auth/presentation/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/mock_accounts.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../domain/auth_validators.dart';
import '../auth_navigation.dart';
import '../widgets/auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// "Đăng nhập" with email + password. Pops `true` once signed in.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialEmail, bool? showTestAccounts})
      : _showTestAccounts = showTestAccounts;

  final String? initialEmail;

  final bool? _showTestAccounts;

  /// "Điền tài khoản thử nghiệm" chips: only while auth is mock.
  bool get showTestAccounts =>
      _showTestAccounts ?? BackendModules.isMock(BackendModule.auth);

  static Route<bool> route({String? email}) =>
      MaterialPageRoute<bool>(builder: (_) => LoginScreen(initialEmail: email));

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .signIn(email: _email.text, password: _password.text);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e);
      });
    }
  }

  void _fill(MockAccount account) {
    setState(() {
      _email.text = account.email;
      _password.text = account.password;
      _error = null;
    });
    _form.currentState?.validate();
  }

  Future<void> _forgotPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    final email = await Navigator.of(context)
        .push<String>(ForgotPasswordScreen.route(email: _email.text.trim()));
    if (email == null || !mounted) return;
    setState(() {
      _email.text = email;
      _password.clear();
      _error = null;
    });
    messenger.showSnackBar(const SnackBar(
        content: Text('Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới.')));
  }

  Future<void> _register() async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final ok =
        await navigator.push<bool>(RegisterScreen.route(fromLogin: true));
    if (ok == true && route != null) {
      completeRoute<Object?>(navigator, route, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                const Center(child: VeganLifeBadge(size: 64)),
                const SizedBox(height: 16),
                Text('Chào mừng bạn trở lại',
                    textAlign: TextAlign.center,
                    style: context.textStyles.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  'Đăng nhập để lưu thực đơn, đăng bài và đặt chuyên gia.',
                  textAlign: TextAlign.center,
                  style:
                      context.textStyles.bodyMedium?.copyWith(color: vl.muted),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Email', border: OutlineInputBorder()),
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: _password,
                  label: 'Mật khẩu',
                  textInputAction: TextInputAction.done,
                  validator: AuthValidators.loginPassword,
                  onSubmitted: (_) => _submit(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _forgotPassword,
                    child: const Text('Quên mật khẩu?'),
                  ),
                ),
                if (_error case final error?) ...[
                  AuthErrorBox(message: error),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(_loading ? 'Đang đăng nhập…' : 'Đăng nhập'),
                ),
                if (widget.showTestAccounts) ...[
                  const SizedBox(height: 20),
                  Text('Điền tài khoản thử nghiệm:',
                      style: context.textStyles.labelLarge
                          ?.copyWith(color: vl.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, icon, account) in [
                        (
                          'Thành viên',
                          Icons.person_outline_rounded,
                          minhAnhAccount
                        ),
                        (
                          'Chuyên gia',
                          Icons.soup_kitchen_outlined,
                          tamChefAccount
                        ),
                      ])
                        ActionChip(
                          avatar: Icon(icon, size: 18),
                          label: Text(label),
                          tooltip: account.email,
                          onPressed: _loading ? null : () => _fill(account),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Chưa có tài khoản?',
                        style: context.textStyles.bodyMedium),
                    TextButton(
                      onPressed: _loading ? null : _register,
                      child: const Text('Đăng ký'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
