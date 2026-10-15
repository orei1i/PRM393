// lib/features/chef_studio/presentation/screens/service_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/data/models/service_model.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../../chef/presentation/controllers/chef_controllers.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_studio_api_service.dart';
import '../../domain/chef_studio_rules.dart';
import '../widgets/chef_only_gate.dart';

/// "Thêm dịch vụ" / "Sửa dịch vụ". Pops with a confirmation message for the
/// list's snackbar.
class ServiceFormScreen extends ConsumerStatefulWidget {
  const ServiceFormScreen({super.key, this.editing});

  final ServiceDto? editing;

  static Route<String> route({ServiceDto? editing}) =>
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => ServiceFormScreen(editing: editing),
      );

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.editing?.title);
  late final _price =
      TextEditingController(text: widget.editing?.price.toString());
  late final _minutes = TextEditingController(
      text: (widget.editing?.durationMinutes ?? 60).toString());
  late final _description =
      TextEditingController(text: widget.editing?.description);
  late final _contentUrl =
      TextEditingController(text: widget.editing?.contentUrl);
  late ServiceType _type = widget.editing?.type ?? ServiceType.consult;
  bool _saving = false;
  bool _attempted = false;

  bool get _editing => widget.editing != null;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _minutes.dispose();
    _description.dispose();
    _contentUrl.dispose();
    super.dispose();
  }

  void _done(String message) {
    ref.read(commerceRevisionProvider.notifier).bump();
    ref.invalidate(chefDirectoryProvider); // starting price, services
    Navigator.of(context).pop(message);
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(describeError(error))));
  }

  Future<void> _save() async {
    final invalid = _form.currentState?.validateGranularly() ?? const {};
    if (invalid.isNotEmpty) {
      setState(() => _attempted = true);
      final target = invalid.first.context;
      if (target.mounted) {
        await Scrollable.ensureVisible(target,
            alignment: 0.2, duration: const Duration(milliseconds: 250));
      }
      return;
    }
    final request = ServiceRequestDto(
      title: _title.text.trim(),
      type: _type,
      price: int.parse(_price.text.trim()),
      description: _description.text.trim(),
      durationMinutes: _type == ServiceType.consult
          ? int.tryParse(_minutes.text.trim())
          : null,
      contentUrl: _type.isPackage ? _contentUrl.text.trim() : null,
    );
    setState(() => _saving = true);
    try {
      final api = ref.read(chefStudioApiProvider);
      if (_editing) {
        await api.updateService(widget.editing!.id, request);
      } else {
        await api.createService(request);
      }
      if (mounted) _done(_editing ? 'Đã lưu dịch vụ.' : 'Đã thêm dịch vụ.');
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xoá dịch vụ?'),
        content: const Text(
            'Dịch vụ sẽ không còn hiển thị trên trang của bạn. Dịch vụ đã có đơn hàng thì không xoá được.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Giữ lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Xoá')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(chefStudioApiProvider).deleteService(widget.editing!.id);
      if (mounted) _done('Đã xoá dịch vụ.');
    } catch (e) {
      _fail(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = int.tryParse(_price.text.trim());
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Sửa dịch vụ' : 'Thêm dịch vụ'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Xoá dịch vụ',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ChefOnlyGate(
        child: Form(
          key: _form,
          autovalidateMode: _attempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          // Not lazy: every field must exist to be validated and scrolled to.
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: ServiceRules.maxTitle,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tên dịch vụ',
                    hintText: 'VD: Tư vấn thực đơn gia đình 7 ngày',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => ServiceRules.title(v ?? ''),
                ),
                const SizedBox(height: 8),
                Text('Loại', style: context.textStyles.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ServiceType>(
                  showSelectedIcon: false,
                  segments: [
                    for (final t in ServiceType.values)
                      ButtonSegment(
                        value: t,
                        label: Text(t.label,
                            textAlign: TextAlign.center, maxLines: 2),
                      ),
                  ],
                  selected: {_type},
                  onSelectionChanged:
                      _editing ? null : (s) => setState(() => _type = s.first),
                ),
                if (_editing)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Không đổi được loại sau khi tạo.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Giá (đ)',
                    hintText: '350000',
                    helperText: price == null ? null : formatVnd(price),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      ServiceRules.price(int.tryParse(v?.trim() ?? '')),
                ),
                if (_type == ServiceType.consult) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Thời lượng (phút)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => ServiceRules.minutes(
                        _type, int.tryParse(v?.trim() ?? '')),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: ServiceRules.maxDescription,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (không bắt buộc)',
                    hintText: 'Khách nhận được gì, hình thức, chuẩn bị gì…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => ServiceRules.description(v ?? ''),
                ),
                if (_type.isPackage) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _contentUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Đường dẫn nội dung',
                      hintText: 'https://…',
                      helperText:
                          'Khách mở được sau khi thanh toán, trong thời gian truy cập.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => ServiceRules.contentUrl(_type, v ?? ''),
                  ),
                ],
                const SizedBox(height: 16),
                VLCard(
                  color: context.colors.secondaryContainer,
                  borderColor: Colors.transparent,
                  child: Text(
                    _type.isPackage
                        ? 'Khách có quyền truy cập ${_type.accessDays} ngày kể từ khi thanh toán. Đổi giá không ảnh hưởng các đơn đã đặt.'
                        : 'Khách chọn giờ trên lịch của bạn và thanh toán khi đặt. Đổi giá không ảnh hưởng các đơn đã đặt.',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.colors.onSecondaryContainer),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
