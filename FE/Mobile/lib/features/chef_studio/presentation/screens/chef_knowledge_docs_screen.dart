// lib/features/chef_studio/presentation/screens/chef_knowledge_docs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/models/chef_studio_models.dart';
import '../controllers/chef_studio_controllers.dart';
import '../widgets/chef_only_gate.dart';
import 'knowledge_doc_form_screen.dart';

/// "Tài liệu kiến thức": documents the chef contributes to the chatbot. The
/// AI only cites one after an admin approves it (web console › Tài liệu).
class ChefKnowledgeDocsScreen extends ConsumerWidget {
  const ChefKnowledgeDocsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ChefKnowledgeDocsScreen());

  static Future<void> _openForm(BuildContext context) async {
    final sent =
        await Navigator.of(context).push(KnowledgeDocFormScreen.route());
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã gửi tài liệu. Ban quản trị sẽ duyệt sớm.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChef = ref.watch(sessionControllerProvider.select((s) => s.isChef));
    return Scaffold(
      appBar: AppBar(title: const Text('Tài liệu kiến thức')),
      floatingActionButton: isChef
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Đóng góp tài liệu'),
            )
          : null,
      body: const ChefOnlyGate(child: _Body(onAdd: _openForm)),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.onAdd});

  final Future<void> Function(BuildContext) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(knowledgeDocsProvider);
    return async.when(
      skipLoadingOnReload: true,
      data: (docs) => docs.isEmpty
          ? Center(
              child: SingleChildScrollView(
                child: EmptyStateView(
                  icon: Icons.menu_book_outlined,
                  title: 'Chưa có tài liệu',
                  message:
                      'Chia sẻ tài liệu chuyên môn để trợ lý AI trả lời chính xác hơn, kèm trích dẫn tên bạn.',
                  actionLabel: 'Đóng góp tài liệu',
                  onAction: () => onAdd(context),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(knowledgeDocsProvider.future),
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _DocCard(doc: docs[i]),
              ),
            ),
      error: (error, _) => Center(
        child: SingleChildScrollView(
          child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(knowledgeDocsProvider)),
        ),
      ),
      loading: () => const ListSkeleton(height: 88),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc});

  final KnowledgeDocDto doc;

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(doc.fileUrl),
        mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Không mở được tệp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final Widget status = switch (doc.status) {
      KnowledgeDocStatus.pending => StatusPill(
          label: 'Chờ duyệt',
          icon: Icons.hourglass_top_rounded,
          background: vl.cautionContainer,
          foreground: vl.onCautionContainer,
        ),
      KnowledgeDocStatus.approved => StatusPill(
          label: 'Đã duyệt · AI đang dùng · ${doc.chunkCount} đoạn',
          icon: Icons.check_circle_outline_rounded,
          background: vl.successContainer,
          foreground: vl.onSuccessContainer,
        ),
      KnowledgeDocStatus.rejected => StatusPill(
          label: 'Bị từ chối',
          icon: Icons.warning_amber_rounded,
          background: vl.cautionContainer,
          foreground: vl.onCautionContainer,
        ),
    };
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doc.title,
              style: context.textStyles.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Nguồn: ${doc.source} · ${formatFullDate(doc.createdAt)}',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          const SizedBox(height: 8),
          status,
          if (doc.status == KnowledgeDocStatus.rejected &&
              doc.reviewNote != null) ...[
            const SizedBox(height: 8),
            Text('Ban quản trị: ${doc.reviewNote}',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: vl.onCautionContainer)),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Mở tệp'),
            ),
          ),
        ],
      ),
    );
  }
}
