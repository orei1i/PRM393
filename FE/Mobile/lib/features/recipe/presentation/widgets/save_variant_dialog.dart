// lib/features/recipe/presentation/widgets/save_variant_dialog.dart
import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../data/models/recipe_variant_model.dart';
import '../../domain/entities/recipe_detail.dart';

/// "Lưu công thức đã chỉnh": name the customized recipe (2–80 chars) and
/// save it with [onSave]. Errors stay in the dialog with the name kept.
/// Returns the saved recipe, or `null` when cancelled.
Future<RecipeDetail?> showSaveVariantDialog(
  BuildContext context, {
  required String defaultName,
  required Future<RecipeDetail> Function(String name) onSave,
}) =>
    showDialog<RecipeDetail>(
      context: context,
      builder: (_) =>
          _SaveVariantDialog(defaultName: defaultName, onSave: onSave),
    );

class _SaveVariantDialog extends StatefulWidget {
  const _SaveVariantDialog({required this.defaultName, required this.onSave});

  final String defaultName;
  final Future<RecipeDetail> Function(String name) onSave;

  @override
  State<_SaveVariantDialog> createState() => _SaveVariantDialogState();
}

class _SaveVariantDialogState extends State<_SaveVariantDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.defaultName);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(_name.text.trim());
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is ApiException ? e.message : describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lưu công thức đã chỉnh'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _name,
              enabled: !_saving,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'Tên công thức',
                helperText:
                    'Lưu vào Công thức của tôi để dùng khi lên Thực đơn.',
                helperMaxLines: 2,
              ),
              validator: (v) => validateVariantName(v ?? ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
        ),
      ],
    );
  }
}
