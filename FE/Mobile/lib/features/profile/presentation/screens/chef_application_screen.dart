// lib/features/profile/presentation/screens/chef_application_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/domain/chef_specialties.dart';
import '../../data/profile_api_service.dart';
import '../../domain/entities/user_profile.dart';
import '../controllers/profile_controller.dart';

/// Member → verified chef application. Reviewed by an admin on the web
/// console; the account stays a member (`User`) until then.
///
/// Also step 2 of "Tạo tài khoản" as Chuyên gia ([fromRegistration]): the
/// new member is already signed in and may skip it ("Để sau") and apply
/// later from Tôi.
class ChefApplicationScreen extends ConsumerStatefulWidget {
  const ChefApplicationScreen({super.key, this.fromRegistration = false});

  final bool fromRegistration;

  static Route<void> route({bool fromRegistration = false}) =>
      MaterialPageRoute<void>(
          builder: (_) =>
              ChefApplicationScreen(fromRegistration: fromRegistration));

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

  // Used to bring the first invalid field into view after "Gửi hồ sơ".
  final _specialtiesKey = GlobalKey();
  final _certificatesKey = GlobalKey();
  final _yearsFocus = FocusNode();
  final _cityFocus = FocusNode();
  final _bioFocus = FocusNode();
  final _certificateFocus = FocusNode();

  @override
  void dispose() {
    _years.dispose();
    _city.dispose();
    _bio.dispose();
    _certificate.dispose();
    _yearsFocus.dispose();
    _cityFocus.dispose();
    _bioFocus.dispose();
    _certificateFocus.dispose();
    super.dispose();
  }

  static String? _validateYears(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < 1 || n > 60 ? 'Từ 1 đến 60 năm' : null;
  }

  static String? _validateCity(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null;

  static String? _validateBio(String? v) => (v ?? '').trim().length < 50
      ? 'Viết ít nhất 50 ký tự để học viên hiểu về bạn.'
      : null;

  /// Scrolls to the first invalid field (top to bottom), focuses it when it is
  /// a text field, and sums up what is missing — otherwise an error far below
  /// the button would look like nothing happened.
  Future<void> _revealErrors() async {
    final invalid = <(String, BuildContext?, FocusNode?)>[
      if (_specialties.isEmpty)
        ('chuyên môn', _specialtiesKey.currentContext, null),
      if (_validateYears(_years.text) != null)
        ('số năm kinh nghiệm', _yearsFocus.context, _yearsFocus),
      if (_validateCity(_city.text) != null)
        ('thành phố', _cityFocus.context, _cityFocus),
      if (_validateBio(_bio.text) != null)
        ('giới thiệu', _bioFocus.context, _bioFocus),
      if (_certificates.isEmpty)
        ('chứng chỉ', _certificatesKey.currentContext, _certificateFocus),
    ];
    if (invalid.isEmpty) return;

    final names = invalid.map((e) => e.$1).join(', ');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Hồ sơ chưa hợp lệ: $names.')));

    final (_, target, focus) = invalid.first;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0.2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    if (mounted) focus?.requestFocus();
  }

  void _addCertificate() {
    final text = _certificate.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _certificates.add(text);
      _certificate.clear();
    });
  }

  /// The real BE has no chef applications yet.
  bool get _savedOnDeviceOnly => BackendModules.isReal(BackendModule.profile);

  Future<void> _submit() async {
    final valid = _form.currentState?.validate() ?? false;
    if (!valid || _specialties.isEmpty || _certificates.isEmpty) {
      setState(() =>
          _attempted = true); // show hints below the chips / certificate list
      await _revealErrors();
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
        SnackBar(
            content: Text(_savedOnDeviceOnly
                ? chefApplicationLocalNote
                : 'Đã gửi hồ sơ. Ban quản trị sẽ phản hồi trong 1–3 ngày làm việc.')),
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
      appBar: AppBar(
        title: Text(widget.fromRegistration
            ? 'Hồ sơ chuyên gia'
            : 'Đăng ký chuyên gia'),
        actions: [
          if (widget.fromRegistration)
            TextButton(
              onPressed: _sending ? null : () => Navigator.of(context).pop(),
              child: const Text('Để sau'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        autovalidateMode: _attempted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        // Not a lazy ListView: every field must be built to be validated and
        // scrolled to.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.fromRegistration) ...[
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 20, color: context.vl.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Bước 2/2: Hồ sơ chuyên gia',
                          style: context.textStyles.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Đã tạo tài khoản. Điền hồ sơ để Ban quản trị duyệt bạn thành chuyên gia.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted),
                ),
                const SizedBox(height: 12),
              ],
              VLCard(
                color: context.colors.secondaryContainer,
                borderColor: Colors.transparent,
                child: Text(
                  'Hồ sơ được Ban quản trị kiểm tra chứng chỉ trước khi hiển thị trong tab Chuyên gia. '
                  'Sau khi duyệt, bạn nhận yêu cầu thiết kế thực đơn từ thành viên và nhận thanh toán qua VeganLife.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.colors.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: 16),
              Text('Chuyên môn',
                  key: _specialtiesKey, style: context.textStyles.titleSmall),
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
                      focusNode: _yearsFocus,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Số năm kinh nghiệm',
                          border: OutlineInputBorder()),
                      validator: _validateYears,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      focusNode: _cityFocus,
                      decoration: const InputDecoration(
                          labelText: 'Thành phố', border: OutlineInputBorder()),
                      validator: _validateCity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bio,
                focusNode: _bioFocus,
                minLines: 4,
                maxLines: 8,
                maxLength: 800,
                decoration: const InputDecoration(
                  labelText: 'Giới thiệu',
                  hintText: 'Kinh nghiệm, nơi từng làm, phong cách tư vấn…',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: _validateBio,
              ),
              const SizedBox(height: 8),
              Text('Chứng chỉ',
                  key: _certificatesKey, style: context.textStyles.titleSmall),
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
                      focusNode: _certificateFocus,
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
              if (!_savedOnDeviceOnly) ...[
                const SizedBox(height: 6),
                Text(
                  'Ảnh chụp chứng chỉ sẽ được yêu cầu qua email sau khi gửi hồ sơ.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ],
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
      ),
    );
  }
}
