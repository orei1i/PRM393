// lib/features/auth/presentation/screens/forgot_password_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/auth_api_service.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/auth_validators.dart';
import '../widgets/auth_widgets.dart';

enum _Step { email, code, password }

/// "Quên mật khẩu": email → 6-digit code → new password, on one screen.
/// Pops the email once the password is changed, so Đăng nhập can prefill it.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  static const resendAfter = Duration(seconds: 60);

  static Route<String> route({String? email}) => MaterialPageRoute<String>(
      builder: (_) => ForgotPasswordScreen(initialEmail: email));

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Step _step = _Step.email;
  bool _loading = false;
  String? _error;

  /// Mock builds only: the code the mock server "sent".
  String? _debugCode;
  String? _resetToken;
  int _resendIn = 0;
  Timer? _countdown;

  @override
  void dispose() {
    _countdown?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  AuthApiService get _api => ref.read(authApiProvider);

  Future<void> _run(Future<void> Function() call) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        // A dead code (3 wrong tries, 10 minutes): resend right away.
        if (e is ApiException && e.code == 'code_expired') {
          _countdown?.cancel();
          _resendIn = 0;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    setState(() => _resendIn = ForgotPasswordScreen.resendAfter.inSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendIn <= 1) timer.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  /// Step 1's "Gửi mã", and "Gửi lại mã" on step 2 (same email).
  Future<void> _sendCode() async {
    if (_step == _Step.email &&
        !(_emailForm.currentState?.validate() ?? false)) {
      return;
    }
    await _run(() async {
      final code = await _api.requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      _code.clear();
      setState(() {
        _debugCode = code;
        _step = _Step.code;
      });
      _startCountdown();
    });
  }

  Future<void> _verify() async {
    if (!(_codeForm.currentState?.validate() ?? false)) return;
    await _run(() async {
      final token = await _api.verifyResetCode(
          email: _email.text.trim(), code: _code.text.trim());
      if (!mounted) return;
      _countdown?.cancel();
      setState(() {
        _resetToken = token;
        _step = _Step.password;
      });
    });
  }

  Future<void> _reset() async {
    if (!(_passwordForm.currentState?.validate() ?? false)) return;
    await _run(() async {
      await _api.resetPassword(
          resetToken: _resetToken!, newPassword: _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(_email.text.trim());
    });
  }

  String get _resendLabel {
    if (_resendIn <= 0) return 'Gửi lại mã';
    final m = _resendIn ~/ 60;
    final s = (_resendIn % 60).toString().padLeft(2, '0');
    return 'Gửi lại mã ($m:$s)';
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final children = switch (_step) {
      _Step.email => [
          Text('Đặt lại mật khẩu', style: context.textStyles.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Nhập email bạn dùng để đăng nhập. Chúng tôi sẽ gửi mã xác minh gồm 6 chữ số.',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 20),
          Form(
            key: _emailForm,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              onFieldSubmitted: (_) => _sendCode(),
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
              validator: AuthValidators.email,
            ),
          ),
          const SizedBox(height: 16),
          if (_error case final error?) ...[
            AuthErrorBox(message: error),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _sendCode,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_loading ? 'Đang gửi…' : 'Gửi mã'),
          ),
        ],
      _Step.code => [
          Text('Nhập mã xác minh', style: context.textStyles.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Nếu email đã đăng ký, mã 6 chữ số đã được gửi tới '
            '${AuthValidators.maskEmail(_email.text.trim())}',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          if (_debugCode case final code?) ...[
            const SizedBox(height: 12),
            AuthInfoBox(
              icon: Icons.science_outlined,
              message: '(Bản thử nghiệm) Mã xác minh: $code',
            ),
          ],
          const SizedBox(height: 20),
          Form(
            key: _codeForm,
            child: TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onFieldSubmitted: (_) => _verify(),
              decoration: const InputDecoration(
                  labelText: 'Nhập mã', border: OutlineInputBorder()),
              validator: AuthValidators.resetCode,
            ),
          ),
          const SizedBox(height: 16),
          if (_error case final error?) ...[
            AuthErrorBox(message: error),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _verify,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_loading ? 'Đang kiểm tra…' : 'Xác nhận'),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _countdown?.cancel();
                          _resendIn = 0;
                          _error = null;
                          _debugCode = null;
                          _step = _Step.email;
                        }),
                child: const Text('Đổi email'),
              ),
              TextButton(
                onPressed: _loading || _resendIn > 0 ? null : _sendCode,
                child: Text(_resendLabel),
              ),
            ],
          ),
        ],
      _Step.password => [
          Text('Tạo mật khẩu mới', style: context.textStyles.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Dùng mật khẩu mới cho lần đăng nhập sau.',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 20),
          Form(
            key: _passwordForm,
            child: Column(
              children: [
                PasswordField(
                  controller: _password,
                  label: 'Mật khẩu mới',
                  autofillHints: const [AutofillHints.newPassword],
                  helperText: 'Ít nhất 8 ký tự, gồm chữ và số',
                  validator: AuthValidators.newPassword,
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: _confirm,
                  label: 'Nhập lại mật khẩu mới',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _reset(),
                  validator: (v) =>
                      AuthValidators.confirmPassword(v, _password.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error case final error?) ...[
            AuthErrorBox(message: error),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _reset,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_loading ? 'Đang đổi…' : 'Đổi mật khẩu'),
          ),
        ],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Quên mật khẩu')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            _StepDots(current: _step.index),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      label: 'Bước ${current + 1}/3',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
