// lib/features/profile/presentation/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';

/// Same fields and rules as the backend `UpdateUserRequest`.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  static Route<void> route(UserProfile profile) => MaterialPageRoute<void>(
      builder: (_) => EditProfileScreen(profile: profile));

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(text: widget.profile.phone);
  bool _saving = false;

  static final _vnPhone = RegExp(r'^(0|\+84)(3|5|7|8|9)\d{8}$');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileControllerProvider.notifier).updateInfo(
            fullName: _name.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã lưu thông tin.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thông tin cá nhân')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Họ tên', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Họ tên là bắt buộc.'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                hintText: '09xx xxx xxx',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final value = (v ?? '').replaceAll(' ', '');
                if (value.isEmpty) return null;
                return _vnPhone.hasMatch(value)
                    ? null
                    : 'Số điện thoại không hợp lệ.';
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: widget.profile.email,
              enabled: false,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Text(
              widget.profile.signedInWithGoogle
                  ? 'Email gắn với tài khoản Google nên không đổi được ở đây.'
                  : 'Liên hệ hỗ trợ nếu cần đổi email đăng nhập.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_saving ? 'Đang lưu…' : 'Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );
  }
}
