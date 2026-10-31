// lib/features/recipe/presentation/widgets/note_editor_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/recipe_review.dart';

enum NoteEditResult { saved, deleted }

/// "Ghi chú của tôi": edit the private note (≤ 2000 chars). "Lưu" with an
/// empty text deletes it; "Xoá ghi chú" asks first. Errors stay in the
/// sheet with the text kept. `null` when dismissed.
Future<NoteEditResult?> showNoteEditorSheet(
  BuildContext context, {
  RecipeNote? note,
  required Future<RecipeNote?> Function(String content) onSave,
  required Future<void> Function() onDelete,
}) =>
    showModalBottomSheet<NoteEditResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _NoteEditor(note: note, onSave: onSave, onDelete: onDelete),
    );

class _NoteEditor extends StatefulWidget {
  const _NoteEditor(
      {required this.note, required this.onSave, required this.onDelete});

  final RecipeNote? note;
  final Future<RecipeNote?> Function(String content) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _text = TextEditingController(text: widget.note?.content ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<NoteEditResult> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeError(e);
      });
    }
  }

  Future<void> _save() => _run(() async {
        final saved = await widget.onSave(_text.text);
        return saved == null ? NoteEditResult.deleted : NoteEditResult.saved;
      });

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá ghi chú?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await widget.onDelete();
      return NoteEditResult.deleted;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: context.vl.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Ghi chú của tôi',
                      style: context.textStyles.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              enabled: !_busy,
              autofocus: true,
              maxLength: noteContentMax,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Mẹo nêm nếm, điều chỉnh cho lần sau…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.error)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (widget.note != null)
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: context.colors.error),
                    child: const Text('Xoá ghi chú'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Đang lưu…' : 'Lưu'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
