import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../auth/presentation/widgets/auth_sheet.dart';
import '../../../community/presentation/widgets/recipe_card.dart';
import '../view_models/explore_view_model.dart';

class ExploreView extends StatelessWidget {
  const ExploreView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ExploreViewModel>();
    return PageBody(
      children: [
        const PageHeading(
          eyebrow: 'Welcome to VeganLife',
          title: 'A greener kind of everyday.',
          subtitle: 'Find your inspiration. Start with one delicious meal.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusBadge(
                'A LITTLE HELP FROM AI',
                icon: Icons.auto_awesome,
              ),
              const SizedBox(height: 14),
              Text(
                'Curious about plant-based living?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Try three questions with our demo nutrition assistant. No sign-up needed.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.go('/trial'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Try the assistant'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          initialValue: vm.query,
          onChanged: vm.setQuery,
          decoration: const InputDecoration(
            hintText: 'Find a recipe or ingredient',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in vm.guestFilters)
              ChoiceChip(
                label: Text(filter),
                selected: vm.filter == filter,
                onSelected: (_) => vm.setFilter(filter),
              ),
          ],
        ),
        const SectionTitle('Discover something delicious'),
        if (vm.posts.isEmpty)
          const EmptyState(
            title: 'No recipes found',
            message: 'Try a different ingredient or filter.',
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
            padding: const EdgeInsets.only(top: 20),
            child: Center(
              child: OutlinedButton(
                onPressed: vm.loadMore,
                child: const Text('Explore more'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Center(
          child: TextButton(
            onPressed: () => showAuthSheet(context),
            child: const Text('Find your people. Join VeganLife →'),
          ),
        ),
      ],
    );
  }
}
