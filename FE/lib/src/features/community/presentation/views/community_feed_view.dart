import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../auth/presentation/widgets/auth_sheet.dart';
import '../view_models/community_feed_view_model.dart';
import '../widgets/recipe_card.dart';

class CommunityFeedView extends StatelessWidget {
  const CommunityFeedView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CommunityFeedViewModel>();
    return PageBody(
      children: [
        PageHeading(
          eyebrow: 'Made of good things',
          title: 'Your daily dose of green.',
          subtitle: 'Real recipes. Kind people. A healthier planet.',
          action: FilledButton.icon(
            onPressed: () => context.push('/create'),
            icon: const Icon(Icons.add),
            label: const Text('Share a recipe'),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusBadge('THE WEEKLY EDIT', icon: Icons.auto_awesome),
              const SizedBox(height: 16),
              Text(
                'Small swaps.\nDelicious possibilities.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Meet your next favorite plant-powered meal.'),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => vm.setFilter('Quick recipes'),
                label: const Text('Explore quick recipes'),
                icon: const Icon(Icons.arrow_forward, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          initialValue: vm.query,
          onChanged: vm.setQuery,
          decoration: const InputDecoration(
            hintText: 'Search recipes, ingredients, and inspiration',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in vm.filters)
              FilterChip(
                label: Text(filter),
                selected: vm.filter == filter,
                onSelected: (_) => vm.setFilter(filter),
              ),
          ],
        ),
        SectionTitle(
          'Fresh from the community',
          trailing: IconButton(
            tooltip: 'Refresh feed',
            onPressed: vm.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        ErrorNotice(vm.error, onRetry: vm.refresh),
        if (vm.posts.isEmpty)
          const EmptyState(
            title: 'Nothing here just yet',
            message: 'Try another search or share the first recipe.',
          ),
        AdaptiveCards(
          minWidth: 330,
          children: [
            for (final post in vm.posts)
              RecipeCard(
                post: post,
                votes: vm.votes(post),
                saved: vm.saved(post),
                onOpen: () => context.push('/post/${post.id}'),
                onSave: () {
                  if (!vm.toggleSave(post)) showAuthSheet(context);
                },
              ),
          ],
        ),
        if (vm.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: vm.loadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('More inspiration'),
              ),
            ),
          ),
      ],
    );
  }
}
