// lib/features/chef_studio/presentation/screens/knowledge_doc_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../data/chef_studio_api_service.dart';
import '../../data/models/chef_studio_models.dart';
import '../../domain/chef_studio_rules.dart';
import '../widgets/chef_only_gate.dart';

enum _Source { file, link }

/// Sample files offered by the mock picker: a real picker needs
/// `file_picker` (not added; needs approval) and storage on the BE.
const _sampleFiles = [
  'huong-dan-bua-trua-chay-van-phong.pdf',
  'bang-dam-thuc-vat-cho-nguoi-tap.pdf',
];

/// "Đóng góp tài liệu". Pops `true` once sent (status Chờ duyệt).
class KnowledgeDocFormScreen extends ConsumerStatefulWidget {
  const KnowledgeDocFormScreen({super.key});

  static Route<bool> route() => MaterialPageRoute<bool>(
      fullscreenDialog: true, builder: (_) => const KnowledgeDocFormScreen());

  @override
  ConsumerState<KnowledgeDocFormScreen> createState() =>
      _KnowledgeDocFormScreenState();
}

class _KnowledgeDocFormScreenState
    extends ConsumerState<KnowledgeDocFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _link = TextEditingController();
  _Source _source = _Source.file;
  String? _file;
  bool _attempted = false;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    super.dispose();
  }

  String? get _fileUrl => switch (_source) {
        _Source.file =>
          _file == null ? null : 'https://files.veganlife.vn/mock/$_file',
        _Source.link => _link.text.trim(),
      };

  Future<void> _pickFile() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Chọn tệp PDF (mô phỏng)',
                    style: sheetContext.textStyles.titleMedium),
              ),
              for (final f in _sampleFiles)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(f),
                  onTap: () => Navigator.of(sheetContext).pop(f),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _file = picked);
  }

  Future<void> _submit() async {
    final valid = _form.currentState?.validate() ?? false;
    final url = _fileUrl;
    if (!valid || url == null || url.isEmpty) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(chefStudioApiProvider).submitKnowledgeDoc(
          KnowledgeDocRequestDto(title: _title.text.trim(), fileUrl: url));
      ref.read(commerceRevisionProvider.notifier).bump();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Scaffold(
      appBar: AppBar(title: const Text('Đóng góp tài liệu')),
      body: ChefOnlyGate(
        child: Form(
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
                TextFormField(
                  controller: _title,
                  maxLength: KnowledgeDocRules.maxTitle,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề',
                    hintText: 'VD: Bữa sáng chay đủ đạm cho người tập',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => KnowledgeDocRules.title(v ?? ''),
                ),
                const SizedBox(height: 8),
                Text('Tệp tài liệu', style: context.textStyles.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<_Source>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: _Source.file,
                        icon: Icon(Icons.picture_as_pdf_outlined),
                        label: Text('Chọn tệp PDF',
                            textAlign: TextAlign.center, maxLines: 2)),
                    ButtonSegment(
                        value: _Source.link,
                        icon: Icon(Icons.link_rounded),
                        label: Text('Dán đường dẫn',
                            textAlign: TextAlign.center, maxLines: 2)),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) => setState(() => _source = s.first),
                ),
                const SizedBox(height: 12),
                if (_source == _Source.file) ...[
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: Icon(_file == null
                        ? Icons.upload_file_rounded
                        : Icons.check_circle_rounded),
                    label: Text(_file ?? 'Chọn tệp PDF'),
                  ),
                  if (_attempted && _file == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Chọn một tệp PDF.',
                          style: TextStyle(color: context.colors.error)),
                    ),
                ] else
                  TextFormField(
                    controller: _link,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Đường dẫn tệp',
                      hintText: 'https://…/tai-lieu.pdf',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => KnowledgeDocRules.fileUrl(v ?? ''),
                  ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.person_outline_rounded, size: 18),
                    label: const Text('Nguồn: Chef'),
                    backgroundColor: context.colors.surfaceContainer,
                  ),
                ),
                const SizedBox(height: 12),
                VLCard(
                  color: vl.aiContainer,
                  borderColor: Colors.transparent,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.auto_awesome, color: vl.ai),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tài liệu chỉ được AI trích dẫn sau khi Ban quản trị duyệt.',
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: vl.onAiContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(_sending ? 'Đang gửi…' : 'Gửi duyệt'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
