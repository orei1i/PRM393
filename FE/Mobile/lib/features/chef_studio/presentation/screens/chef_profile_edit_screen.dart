// lib/features/chef_studio/presentation/screens/chef_profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../chef/domain/chef_specialties.dart';
import '../../../chef/presentation/controllers/chef_controllers.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_studio_api_service.dart';
import '../../data/models/chef_studio_models.dart';
import '../../domain/chef_studio_rules.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_only_gate.dart';

/// Tôi › Chuyên gia › "Hồ sơ & bảng giá": main specialty, bio and the
/// booking prices shown on the public profile ("Giá mỗi ngày", "Giá có phản
/// hồi mỗi ngày", plan length, "Đang nhận yêu cầu"). Creates the profile
/// when there is none yet.
class ChefProfileEditScreen extends StatelessWidget {
  const ChefProfileEditScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefProfileEditScreen());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ & bảng giá')),
      body: const ChefOnlyGate(child: _Loader()),
    );
  }
}

class _Loader extends ConsumerWidget {
  const _Loader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chefStudioProfileProvider);
    return async.when(
      // Keep the form (and what was typed) while lists refetch after saving.
      skipLoadingOnReload: true,
      data: (profile) => _Form(initial: profile),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(chefStudioProfileProvider)),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.initial});

  /// `null`: no profile yet, saving creates it.
  final ChefProfileDto? initial;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _form = GlobalKey<FormState>();
  late final _bio = TextEditingController(text: widget.initial?.bio);
  late final _price =
      TextEditingController(text: '${widget.initial?.pricePerDay ?? 120000}');
  late final _feedbackPrice = TextEditingController(
      text: '${widget.initial?.feedbackPricePerDay ?? 180000}');
  late final _minDays =
      TextEditingController(text: '${widget.initial?.minPlanDays ?? 3}');
  late final _maxDays =
      TextEditingController(text: '${widget.initial?.maxPlanDays ?? 30}');
  late bool _accepting = widget.initial?.acceptingBookings ?? true;
  late String? _specialty = chefSpecialties.contains(widget.initial?.specialty)
      ? widget.initial!.specialty
      : null;
  bool _attempted = false;
  bool _saving = false;

  @override
  void dispose() {
    _bio.dispose();
    _price.dispose();
    _feedbackPrice.dispose();
    _minDays.dispose();
    _maxDays.dispose();
    super.dispose();
  }

  static int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  String? get _daysError =>
      ChefProfileRules.planDays(_int(_minDays), _int(_maxDays));

  Future<void> _save() async {
    final valid = _form.currentState?.validate() ?? false;
    final specialty = _specialty;
    if (!valid || specialty == null || _daysError != null) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(chefStudioApiProvider)
          .updateMyProfile(ChefProfileRequestDto(
            specialty: specialty,
            bio: _bio.text.trim(),
            pricePerDay: _int(_price)!,
            feedbackPricePerDay: _int(_feedbackPrice)!,
            minPlanDays: _int(_minDays)!,
            maxPlanDays: _int(_maxDays)!,
            acceptingBookings: _accepting,
          ));
      ref
        ..invalidate(chefDirectoryProvider)
        ..read(commerceRevisionProvider.notifier).bump();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu hồ sơ & bảng giá.')));
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
    final specialtyError =
        _attempted ? ChefProfileRules.specialty(_specialty) : null;
    return Form(
      key: _form,
      autovalidateMode: _attempted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.initial == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Bạn chưa có hồ sơ chuyên gia. Lưu để xuất hiện trong tab Chuyên gia.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted),
                ),
              ),
            DropdownMenu<String>(
              initialSelection: _specialty,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Chuyên môn chính'),
              errorText: specialtyError,
              dropdownMenuEntries: [
                for (final s in chefSpecialties)
                  DropdownMenuEntry(value: s, label: s),
              ],
              onSelected: (v) => setState(() => _specialty = v),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bio,
              minLines: 5,
              maxLines: 12,
              maxLength: ChefProfileRules.maxBio,
              decoration: const InputDecoration(
                labelText: 'Giới thiệu',
                hintText: 'Kinh nghiệm, nơi từng làm, phong cách tư vấn…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => ChefProfileRules.bio(v ?? ''),
            ),
            const SizedBox(height: 8),
            Text('Bảng giá thiết kế thực đơn',
                style: context.textStyles.titleMedium),
            Text(
              'Giá tham khảo hiện trên hồ sơ công khai; giá cuối do bạn và thành viên thoả thuận trong chat.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
            const SizedBox(height: 12),
            _PriceField(controller: _price, label: 'Giá mỗi ngày'),
            const SizedBox(height: 12),
            _PriceField(
              controller: _feedbackPrice,
              label: 'Giá có phản hồi mỗi ngày',
              validator: (v) => ChefProfileRules.feedbackDayPrice(
                  int.tryParse(v ?? ''), _int(_price)),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Số ngày tối thiểu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxDays,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Số ngày tối đa',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            if (_attempted && _daysError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_daysError!,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.colors.error)),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepting,
              onChanged: (v) => setState(() => _accepting = v),
              title: const Text('Đang nhận yêu cầu'),
              subtitle: Text(_accepting
                  ? 'Thành viên đặt được bạn từ hồ sơ công khai.'
                  : 'Hồ sơ hiện "Chuyên gia đang tạm ngưng nhận yêu cầu".'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_saving ? 'Đang lưu…' : 'Lưu hồ sơ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField(
      {required this.controller, required this.label, this.validator});

  final TextEditingController controller;
  final String label;

  /// Instead of the plain price range check.
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'đ/ngày',
        helperText:
            'Từ ${formatVnd(ChefProfileRules.minDayPrice)} đến ${formatVnd(ChefProfileRules.maxDayPrice)}',
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ?? (v) => ChefProfileRules.dayPrice(int.tryParse(v ?? '')),
    );
  }
}
