// lib/features/recipe/presentation/widgets/recipe_note_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/vl_card.dart';
import '../controllers/recipe_social_controllers.dart';
import 'note_editor_sheet.dart';

/// "Ghi chú của tôi" at the top of "Cách làm": the member's private note
/// on this recipe ("Chỉ mình bạn thấy"). Guests are asked to sign in when
/// they add one, then the editor opens.
class RecipeNoteCard extends ConsumerStatefulWidget {
  const RecipeNoteCard({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<RecipeNoteCard> createState() => _RecipeNoteCardState();
}

class _RecipeNoteCardState extends ConsumerState<RecipeNoteCard> {
  Future<void> _edit() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để lưu ghi chú riêng cho công thức.');
    if (!ok || !mounted) return;
    final provider = recipeNoteProvider(widget.recipeId);
    final note = await ref.read(provider.future);
    if (!mounted) return;
    final result = await showNoteEditorSheet(
      context,
      note: note,
      onSave: (content) => ref.read(provider.notifier).save(content),
      onDelete: () => ref.read(provider.notifier).delete(),
    );
    if (result == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(result == NoteEditResult.saved
              ? 'Đã lưu ghi chú'
              : 'Đã xoá ghi chú')));
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final async = ref.watch(recipeNoteProvider(widget.recipeId));
    final muted = context.textStyles.bodyMedium?.copyWith(color: vl.muted);

    final Widget body;
    if (!async.hasValue && async.hasError) {
      body = Row(
        children: [
          Expanded(child: Text('Chưa tải được ghi chú', style: muted)),
          TextButton(
            onPressed: () =>
                ref.invalidate(recipeNoteProvider(widget.recipeId)),
            child: const Text('Thử lại'),
          ),
        ],
      );
    } else if (!async.hasValue) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    } else if (async.value case final note?) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(note.content,
              style: context.textStyles.bodyLarge?.copyWith(height: 1.4)),
          Row(
            children: [
              Expanded(
                child: Text('Cập nhật ${relativeTime(note.updatedAt)}',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.muted)),
              ),
              TextButton(onPressed: _edit, child: const Text('Sửa')),
            ],
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Thêm ghi chú riêng: mẹo nêm nếm, điều chỉnh cho lần sau…',
              style: muted),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Thêm ghi chú'),
            ),
          ),
        ],
      );
    }

    return VLCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: vl.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Ghi chú của tôi',
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('Chỉ mình bạn thấy',
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted)),
            ],
          ),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}
