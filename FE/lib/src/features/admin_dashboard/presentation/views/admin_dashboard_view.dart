import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../view_models/admin_dashboard_view_model.dart';
import '../widgets/activity_chart.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AdminDashboardViewModel>();
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'VeganLife / Admin workspace',
          title: 'A healthy community starts here.',
          subtitle:
              'Local session metrics and clearly labeled sample telemetry.',
          action: OutlinedButton.icon(
            onPressed: vm.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ),
        if (vm.showAlert) ...[
          SurfaceCard(
            child: Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(vm.alert)),
                IconButton(
                  onPressed: vm.dismissAlert,
                  tooltip: 'Dismiss alert',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        AdaptiveCards(
          minWidth: 230,
          children: [
            for (final metric in vm.metrics)
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      metric.value,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(fontSize: 40),
                    ),
                    const SizedBox(height: 8),
                    Text(metric.context, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Community contributions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: vm.toggleTable,
                    tooltip: vm.tableMode ? 'Show chart' : 'Show data table',
                    icon: Icon(
                      vm.tableMode
                          ? Icons.bar_chart
                          : Icons.table_chart_outlined,
                    ),
                  ),
                ],
              ),
              const Text(
                'Illustrative week · static sample counts, not live analytics',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 24),
              ActivityChart(samples: vm.activity, tableMode: vm.tableMode),
            ],
          ),
        ),
        const SectionTitle('Your workspace'),
        AdaptiveCards(
          minWidth: 260,
          children: [
            _WorkspaceLink(
              title: 'Content moderation',
              detail: 'Review reports and support the community.',
              icon: Icons.shield_outlined,
              onTap: () => context.go('/admin/moderation'),
            ),
            _WorkspaceLink(
              title: 'Categories & tags',
              detail: 'Keep recipes organized and discoverable.',
              icon: Icons.category_outlined,
              onTap: () => context.go('/admin/categories'),
            ),
            _WorkspaceLink(
              title: 'AI operations',
              detail: 'Inspect sample responses and review signals.',
              icon: Icons.auto_awesome,
              onTap: () => context.go('/admin/ai'),
            ),
          ],
        ),
        const SectionTitle('AI service snapshot'),
        SurfaceCard(
          child: Wrap(
            spacing: 30,
            runSpacing: 20,
            children: [
              for (final metric in vm.aiMetrics)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.label, style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SectionTitle('Recent activity'),
        for (final log in vm.logs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    log.warning
                        ? Icons.info_outline
                        : Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Text(log.detail),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkspaceLink extends StatelessWidget {
  const _WorkspaceLink({
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String title, detail;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(detail),
            const SizedBox(height: 14),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    ),
  );
}
