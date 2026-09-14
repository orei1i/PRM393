import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../widgets/user_content_list.dart';

class UserContentManagementView extends StatelessWidget {
  const UserContentManagementView({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    maxWidth: 840,
    children: [
      PageHeading(
        title: 'Made by you.',
        subtitle: 'Edit your recipes, videos, and conversations.',
        action: FilledButton.icon(
          onPressed: () => context.push('/create'),
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ),
      const UserContentList(),
    ],
  );
}
