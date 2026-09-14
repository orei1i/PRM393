import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/validated_editor.dart';
import '../view_models/category_management_view_model.dart';

class CategoryManagementView extends StatelessWidget {
  const CategoryManagementView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CategoryManagementViewModel>();
    return PageBody(
      maxWidth: 880,
      children: [
        const PageHeading(
          eyebrow: 'A place for everything',
          title: 'Organize the good stuff.',
          subtitle: 'Categories and editorial recipe tags · demo data',
        ),
        ErrorNotice(vm.error),
        SectionTitle(
          'Food categories',
          trailing: IconButton(
            onPressed: () => _edit(context, vm),
            tooltip: 'Add category',
            icon: const Icon(Icons.add),
          ),
        ),
        const Text(
          'Renaming updates associated recipes. Categories in use cannot be deleted.',
        ),
        const SizedBox(height: 14),
        for (final category in vm.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SurfaceCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${vm.usage(category.name)} recipes',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _edit(
                      context,
                      vm,
                      id: category.id,
                      initial: category.name,
                    ),
                    tooltip: 'Edit category',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: () => _delete(context, vm, category.id),
                    tooltip: 'Delete category',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        SectionTitle(
          'Recipe tags',
          trailing: IconButton(
            onPressed: () => _edit(context, vm, tag: true),
            tooltip: 'Add tag',
            icon: const Icon(Icons.add),
          ),
        ),
        const Text(
          'Editorial tag catalog; tags are not yet attached to individual recipe records.',
        ),
        const SizedBox(height: 14),
        for (final tag in vm.tags)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SurfaceCard(
              child: Row(
                children: [
                  Expanded(child: Text(tag.name)),
                  IconButton(
                    onPressed: () => _edit(
                      context,
                      vm,
                      tag: true,
                      id: tag.id,
                      initial: tag.name,
                    ),
                    tooltip: 'Edit tag',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: () => _delete(context, vm, tag.id, tag: true),
                    tooltip: 'Delete tag',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    CategoryManagementViewModel vm, {
    String? id,
    String initial = '',
    bool tag = false,
  }) async {
    var draft = initial;
    await showValidatedEditor(
      context,
      viewModel: vm,
      title: '${id == null ? 'New' : 'Edit'} ${tag ? 'tag' : 'category'}',
      onSave: () => vm.save(draft, id: id, tag: tag),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        maxLength: 36,
        onChanged: (value) => draft = value,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    CategoryManagementViewModel vm,
    String id, {
    bool tag = false,
  }) async {
    if (await confirmAction(
      context,
      title: 'Delete ${tag ? 'tag' : 'category'}?',
      message: 'This removes the item from the demo catalog.',
    )) {
      vm.delete(id, tag: tag);
    }
  }
}
