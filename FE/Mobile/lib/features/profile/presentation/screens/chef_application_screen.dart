// lib/features/profile/presentation/screens/chef_application_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/domain/chef_specialties.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';

/// Member → verified chef application. Reviewed by an admin on the web console.
class ChefApplicationScreen extends ConsumerStatefulWidget {
  const ChefApplicationScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefApplicationScreen());

  @override
  ConsumerState<ChefApplicationScreen> createState() =>
      _ChefApplicationScreenState();
}

class _ChefApplicationScreenState extends ConsumerState<ChefApplicationScreen> {
  final _form = GlobalKey<FormState>();
  final _years = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  final _certificate = TextEditingController();
  final Set<String> _specialties = {};
  final List<String> _certificates = [];
  bool _sending = false;
  bool _attempted = false;

  @override
  void dispose() {
    _years.dispose();
    _city.dispose();
    _bio.dispose();
    _certificate.dispose();
    super.dispose();
  }

  void _addCertificate() {
    final text = _certificate.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _certificates.add(text);
      _certificate.clear();
    });
  }

  Future<void> _submit() async {
    final valid = _form.currentState?.validate() ?? false;
    if (!valid || _specialties.isEmpty || _certificates.isEmpty) {
      setState(() =>
          _attempted = true); // show hints below the chips / certificate list
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(profileControllerProvider.notifier).submitChefApplication(
            ChefApplicationRequest(
              specialties: _specialties.toList(),
              yearsExperience: int.parse(_years.text.trim()),
              city: _city.text.trim(),
              bio: _bio.text.trim(),
              certificates: _certificates,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Đã gửi hồ sơ. Ban quản trị sẽ phản hồi trong 1–3 ngày làm việc.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký chuyên gia')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            VLCard(
              color: context.colors.secondaryContainer,
              borderColor: Colors.transparent,
              child: Text(
                'Hồ sơ được Ban quản trị kiểm tra chứng chỉ trước khi hiển thị trong tab Chuyên gia. '
                'Sau khi duyệt, bạn có thể tạo gói tư vấn và nhận đặt lịch.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.colors.onSecondaryContainer),
              ),
            ),
            const SizedBox(height: 16),
            Text('Chuyên môn', style: context.textStyles.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in chefSpecialties)
                  FilterChip(
                    label: Text(s),
                    selected: _specialties.contains(s),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _specialties.add(s);
                      } else {
                        _specialties.remove(s);
                      }
                    }),
                  ),
              ],
            ),
            if (_attempted && _specialties.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Chọn ít nhất một chuyên môn.',
                    style: TextStyle(color: context.colors.error)),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _years,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Số năm kinh nghiệm',
                        border: OutlineInputBorder()),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n < 1 || n > 60) {
                        return 'Từ 1 đến 60 năm';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(
                        labelText: 'Thành phố', border: OutlineInputBorder()),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bio,
              minLines: 4,
              maxLines: 8,
              maxLength: 800,
              decoration: const InputDecoration(
                labelText: 'Giới thiệu',
                hintText: 'Kinh nghiệm, nơi từng làm, phong cách tư vấn…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v ?? '').trim().length < 50
                  ? 'Viết ít nhất 50 ký tự để học viên hiểu về bạn.'
                  : null,
            ),
            const SizedBox(height: 8),
            Text('Chứng chỉ', style: context.textStyles.titleSmall),
            const SizedBox(height: 8),
            for (var i = 0; i < _certificates.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.workspace_premium_outlined,
                    color: context.colors.primary),
                title: Text(_certificates[i]),
                trailing: IconButton(
                  tooltip: 'Xoá',
                  onPressed: () => setState(() => _certificates.removeAt(i)),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _certificate,
                    onSubmitted: (_) => _addCertificate(),
                    decoration: const InputDecoration(
                      hintText:
                          'VD: Chứng chỉ Đầu bếp chuyên nghiệp — CĐ Du lịch Sài Gòn',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Thêm chứng chỉ',
                  onPressed: _addCertificate,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (_attempted && _certificates.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Thêm ít nhất một chứng chỉ.',
                    style: TextStyle(color: context.colors.error)),
              ),
            const SizedBox(height: 6),
            Text(
              'Ảnh chụp chứng chỉ sẽ được yêu cầu qua email sau khi gửi hồ sơ.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_sending ? 'Đang gửi…' : 'Gửi hồ sơ'),
            ),
          ],
        ),
      ),
    );
  }
}
