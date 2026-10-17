// lib/features/auth/presentation/screens/register_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/auth_api_service.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../profile/presentation/screens/chef_application_screen.dart';
import '../../domain/auth_validators.dart';
import '../auth_navigation.dart';
import '../widgets/auth_widgets.dart';
import 'login_screen.dart';

enum RegisterRole { member, chef }

/// "Tạo tài khoản". The account is always a member; choosing "Chuyên gia"
/// continues to the chef application ("Bước 2/2"), which an admin approves
/// on the web console. Pops `true` once signed in (for a chef, the
/// application screen replaces this one and the opener still gets `true`).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.fromLogin = false});

  /// Opened from Đăng nhập: "Đăng nhập" at the bottom just goes back.
  final bool fromLogin;

  static Route<bool> route({bool fromLogin = false}) => MaterialPageRoute<bool>(
      builder: (_) => RegisterScreen(fromLogin: fromLogin));

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  RegisterRole _role = RegisterRole.member;
  bool _agreed = false;
  bool _attempted = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final valid = _form.currentState?.validate() ?? false;
    setState(() => _attempted = true);
    if (!valid || !_agreed) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final phone = _phone.text.replaceAll(' ', '');
    try {
      await ref.read(sessionControllerProvider.notifier).register(
            RegisterRequest(
              fullName: _name.text.trim(),
              email: _email.text.trim(),
              password: _password.text,
              phone: phone.isEmpty ? null : phone,
            ),
          );
      if (!mounted) return;
      TextInput.finishAutofillContext();
      final navigator = Navigator.of(context);
      if (_role == RegisterRole.chef) {
        navigator.pushReplacement<void, bool>(
            ChefApplicationScreen.route(fromRegistration: true),
            result: true);
      } else {
        navigator.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeError(e);
      });
    }
  }

  Future<void> _login() async {
    final navigator = Navigator.of(context);
    if (widget.fromLogin) {
      navigator.pop(false);
      return;
    }
    final route = ModalRoute.of(context);
    final ok = await navigator.push<bool>(LoginScreen.route(
        email: _email.text.trim().isEmpty ? null : _email.text.trim()));
    if (ok == true && route != null) {
      completeRoute<Object?>(navigator, route, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo tài khoản')),
      body: SafeArea(
        child: Form(
          key: _form,
          autovalidateMode: _attempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text('Bạn là', style: context.textStyles.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<RegisterRole>(
                  segments: const [
                    ButtonSegment(
                      value: RegisterRole.member,
                      label: Text('Thành viên'),
                      icon: Icon(Icons.person_outline_rounded),
                    ),
                    ButtonSegment(
                      value: RegisterRole.chef,
                      label: Text('Chuyên gia'),
                      icon: Icon(Icons.soup_kitchen_outlined),
                    ),
                  ],
                  selected: {_role},
                  showSelectedIcon: false,
                  onSelectionChanged:
                      _loading ? null : (s) => setState(() => _role = s.first),
                ),
                if (_role == RegisterRole.chef) ...[
                  const SizedBox(height: 12),
                  const AuthInfoBox(
                    icon: Icons.verified_outlined,
                    message:
                        'Tài khoản chuyên gia cần Ban quản trị duyệt hồ sơ. Sau khi đăng ký, bạn sẽ điền hồ sơ chuyên gia.',
                  ),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  maxLength: 100,
                  decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      border: OutlineInputBorder(),
                      counterText: ''),
                  validator: AuthValidators.fullName,
                ),
                const SizedBox(height: 14),
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
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại (không bắt buộc)',
                    hintText: '09xx xxx xxx',
                    border: OutlineInputBorder(),
                  ),
                  validator: AuthValidators.phone,
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: _password,
                  label: 'Mật khẩu',
                  autofillHints: const [AutofillHints.newPassword],
                  helperText: 'Ít nhất 8 ký tự, gồm chữ và số',
                  validator: AuthValidators.newPassword,
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: _confirm,
                  label: 'Nhập lại mật khẩu',
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  validator: (v) =>
                      AuthValidators.confirmPassword(v, _password.text),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Tôi đồng ý với Điều khoản sử dụng và Chính sách quyền riêng tư'),
                  subtitle: _attempted && !_agreed
                      ? Text('Bạn cần đồng ý để tạo tài khoản',
                          style: TextStyle(color: cs.error))
                      : null,
                ),
                const SizedBox(height: 8),
                if (_error case final error?) ...[
                  AuthErrorBox(message: error),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child:
                      Text(_loading ? 'Đang tạo tài khoản…' : 'Tạo tài khoản'),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Đã có tài khoản?',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: vl.muted)),
                    TextButton(
                      onPressed: _loading ? null : _login,
                      child: const Text('Đăng nhập'),
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
