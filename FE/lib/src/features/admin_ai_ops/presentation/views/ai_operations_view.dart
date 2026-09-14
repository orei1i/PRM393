import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/validated_editor.dart';
import '../../domain/entities/ai_ops_entities.dart';
import '../view_models/ai_operations_view_model.dart';

class AiOperationsView extends StatelessWidget {
  const AiOperationsView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AiOperationsViewModel>();
    return PageBody(
      children: [
        const PageHeading(
          eyebrow: 'Thoughtful by design',
          title: 'Keep AI accountable.',
          subtitle:
              'Sample telemetry and manual review · no live model connected',
        ),
        AdaptiveCards(
          minWidth: 250,
          children: [
            for (final metric in vm.metrics)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.label),
                    const SizedBox(height: 12),
                    Text(
                      '${metric.value} ${metric.unit}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in AiOperationsViewModel.filters)
              ChoiceChip(
                label: Text(filter),
                selected: vm.filter == filter,
                onSelected: (_) => vm.setFilter(filter),
              ),
          ],
        ),
        ErrorNotice(vm.error),
        const SizedBox(height: 20),
        const Text(
          'Confidence scores are fabricated review signals, not calibrated probabilities of correctness.',
        ),
        const SizedBox(height: 16),
        if (vm.logs.isEmpty)
          const EmptyState(
            title: 'Nothing to review',
            message: 'Choose another filter to see sample logs.',
          ),
        for (final log in vm.logs)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(
                    log.overridden
                        ? 'MANUALLY REVIEWED'
                        : log.needsReview
                        ? 'NEEDS REVIEW'
                        : 'SAMPLE RESPONSE',
                    warning: log.needsReview,
                    icon: log.overridden
                        ? Icons.fact_check_outlined
                        : Icons.info_outline,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    log.prompt,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(log.overrideText ?? log.response),
                  const SizedBox(height: 14),
                  Text(
                    'Sample confidence: ${(log.confidence * 100).toStringAsFixed(0)}% · ${log.latencyMs} ms',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (log.reason != null) ...[
                    const SizedBox(height: 10),
                    Text('Audit reason: ${log.reason}'),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _override(context, vm, log),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Manual override'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _override(
    BuildContext context,
    AiOperationsViewModel vm,
    AiModelLog log,
  ) async {
    var text = log.overrideText ?? log.response;
    var reason = '';
    await showValidatedEditor(
      context,
      viewModel: vm,
      title: 'Review sample response',
      saveLabel: 'Apply local override',
      onSave: () => vm.applyOverride(log.id, text, reason),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This changes only the local log, not a model or a sent response.',
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: text,
            onChanged: (v) => text = v,
            maxLines: 4,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Replacement response',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            onChanged: (v) => reason = v,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Audit reason'),
          ),
        ],
      ),
    );
  }
}
