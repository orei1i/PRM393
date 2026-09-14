import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../view_models/create_post_view_model.dart';

class CreatePostView extends StatelessWidget {
  const CreatePostView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CreatePostViewModel>();
    return PageBody(
      maxWidth: 720,
      children: [
        PageHeading(
          title: vm.editing ? 'Make it your own.' : 'Something worth sharing.',
          subtitle: 'A good recipe is even better when shared.',
        ),
        TextFormField(
          initialValue: vm.title,
          onChanged: vm.setTitle,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Recipe title'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: vm.description,
          onChanged: vm.setDescription,
          maxLength: 2000,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'The story behind your recipe',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in vm.categories)
              ChoiceChip(
                label: Text(category),
                selected: vm.category == category,
                onSelected: (_) => vm.setCategory(category),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: vm.ingredients,
          onChanged: vm.setIngredients,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Ingredients',
            helperText: 'Separate ingredients with commas',
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          initialValue: vm.steps,
          onChanged: vm.setSteps,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Cooking steps',
            helperText: 'One step per line',
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cooking video demo'),
          subtitle: const Text(
            'Uses the built-in mock player; no video is uploaded.',
          ),
          value: vm.isVideo,
          onChanged: vm.editing ? null : vm.setVideo,
        ),
        ErrorNotice(vm.error),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () {
                final id = vm.save();
                if (id != null) context.go('/post/$id');
              },
              icon: const Icon(Icons.publish_outlined),
              label: Text(vm.editing ? 'Save changes' : 'Publish recipe'),
            ),
            OutlinedButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/community'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
