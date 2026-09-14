import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/entities/moderation_entities.dart';
import '../view_models/content_moderation_view_model.dart';

class ContentModerationView extends StatelessWidget {
  const ContentModerationView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ContentModerationViewModel>();
    return PageBody(
      children: [
        const PageHeading(
          eyebrow: 'Community care',
          title: 'Keep the conversation kind.',
          subtitle:
              'Review sample reports. Every action stays in this demo session.',
        ),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Pending')),
            ButtonSegment(value: true, label: Text('Resolved')),
          ],
          selected: {vm.showResolved},
          onSelectionChanged: (s) => vm.setResolved(s.first),
        ),
        ErrorNotice(vm.error),
        const SizedBox(height: 20),
        if (vm.flags.isEmpty)
          const EmptyState(
            title: 'All clear here',
            message: 'No reports in this queue.',
            icon: Icons.verified_outlined,
          ),
        for (final flag in vm.flags)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(
                    '${flag.reports} report(s)',
                    warning: true,
                    icon: Icons.flag_outlined,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    flag.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text('By ${flag.author}'),
                  const SizedBox(height: 12),
                  Text(flag.reason),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (flag.contentRemoved)
                        const StatusBadge('CONTENT REMOVED')
                      else
                        TextButton(
                          onPressed: () => context.push('/post/${flag.postId}'),
                          child: const Text('Review content'),
                        ),
                      if (flag.actionable) ...[
                        FilledButton.tonal(
                          onPressed: () => _act(
                            context,
                            vm,
                            flag.id,
                            ModerationDecision.approve,
                          ),
                          child: const Text('Approve'),
                        ),
                        OutlinedButton(
                          onPressed: () => _act(
                            context,
                            vm,
                            flag.id,
                            ModerationDecision.warn,
                          ),
                          child: const Text('Warn user'),
                        ),
                        TextButton(
                          onPressed: () => _act(
                            context,
                            vm,
                            flag.id,
                            ModerationDecision.delete,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SectionTitle('Action history'),
        for (final action in vm.actions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(
              '${action.decision.name.toUpperCase()} · ${action.title}',
            ),
            subtitle: const Text(
              'Recorded locally · no notification sent to a real person',
            ),
          ),
      ],
    );
  }

  Future<void> _act(
    BuildContext context,
    ContentModerationViewModel vm,
    String id,
    ModerationDecision decision,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: '${decision.name.toUpperCase()} content?',
      message: decision == ModerationDecision.delete
          ? 'This removes the recipe and comments from the shared demo feed.'
          : decision == ModerationDecision.warn
          ? 'Record a sample warning. Content remains visible and no real message is sent.'
          : 'Resolve this report and keep the content available.',
      confirmLabel: decision.name.toUpperCase(),
    );
    if (confirmed) vm.act(id, decision);
  }
}
