import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/validated_editor.dart';
import '../../domain/entities/user_profile.dart';
import '../view_models/user_profile_view_model.dart';

class UserContentList extends StatelessWidget {
  const UserContentList({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UserProfileViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (tab, label) in const [
              (ContentTab.posts, 'My Posts'),
              (ContentTab.videos, 'My Videos'),
              (ContentTab.comments, 'My Comments'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: vm.tab == tab,
                onSelected: (_) => vm.setTab(tab),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ErrorNotice(vm.error),
        if (vm.tab == ContentTab.comments) ...[
          if (vm.comments.isEmpty)
            const EmptyState(
              title: 'Start a conversation',
              message: 'Your comments will appear here.',
            ),
          for (final comment in vm.comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(comment.text),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () =>
                              context.push('/post/${comment.postId}'),
                          child: const Text('View thread'),
                        ),
                        TextButton(
                          onPressed: () => _editComment(
                            context,
                            vm,
                            comment.id,
                            comment.text,
                          ),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirmed = await confirmAction(
                              context,
                              title: 'Delete comment?',
                              message:
                                  'This also removes replies in this demo.',
                            );
                            if (confirmed) vm.deleteComment(comment.id);
                          },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ] else ...[
          if (vm.posts.isEmpty)
            const EmptyState(
              title: 'Your next recipe starts here',
              message: 'Share something you love to cook.',
            ),
          for (final post in vm.posts)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(post.hidden ? 'Hidden by moderation' : post.category),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => context.push('/post/${post.id}'),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => context.push('/edit/${post.id}'),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final confirmed = await confirmAction(
                              context,
                              title: 'Delete your recipe?',
                              message:
                                  'The recipe and its comments will be removed from this demo session.',
                            );
                            if (confirmed) vm.deletePost(post.id);
                          },
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _editComment(
    BuildContext context,
    UserProfileViewModel vm,
    String id,
    String text,
  ) async {
    var draft = text;
    await showValidatedEditor(
      context,
      viewModel: vm,
      title: 'Edit your comment',
      onSave: () => vm.editComment(id, draft),
      content: TextFormField(
        initialValue: text,
        onChanged: (value) => draft = value,
        maxLines: 4,
        maxLength: 1000,
      ),
    );
  }
}
