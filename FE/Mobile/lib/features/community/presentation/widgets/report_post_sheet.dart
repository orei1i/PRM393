// lib/features/community/presentation/widgets/report_post_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';

/// Report → admin moderation queue (web). Pops `true` when sent.
class ReportPostSheet extends ConsumerStatefulWidget {
  const ReportPostSheet({super.key, required this.post});

  final Post post;

  @override
  ConsumerState<ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends ConsumerState<ReportPostSheet> {
  ReportReason? _reason;
  final _note = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(communityApiProvider)
          .reportPost(widget.post.id, reason: reason, note: _note.text.trim());
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Báo cáo bài viết', style: context.textStyles.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Tác giả sẽ không biết ai đã báo cáo.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              ),
              const SizedBox(height: 12),
              for (final r in ReportReason.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.label),
                  trailing: Icon(
                    _reason == r
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: _reason == r
                        ? context.colors.primary
                        : context.vl.muted,
                  ),
                  onTap: () => setState(() => _reason = r),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú thêm (không bắt buộc)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _reason == null || _sending ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(_sending ? 'Đang gửi…' : 'Gửi báo cáo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
