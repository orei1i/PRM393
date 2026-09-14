import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/food_art.dart';
import '../../../auth/presentation/widgets/auth_sheet.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../../domain/entities/community_entities.dart';
import '../view_models/post_detail_view_model.dart';

class PostDetailView extends StatefulWidget {
  const PostDetailView({super.key});
  @override
  State<PostDetailView> createState() => _PostDetailViewState();
}

class _PostDetailViewState extends State<PostDetailView> {
  final _comment = TextEditingController();
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PostDetailViewModel>();
    final post = vm.post;
    if (post == null) {
      return const EmptyState(
        title: 'Recipe unavailable',
        message: 'This recipe may have been removed or is awaiting review.',
      );
    }
    return PageBody(
      maxWidth: 780,
      children: [
        TextButton.icon(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(context.read<AuthViewModel>().homeRoute),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        FoodArt(variant: post.art, height: 260),
        const SizedBox(height: 24),
        StatusBadge(post.category),
        const SizedBox(height: 16),
        Text(post.title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 10),
        Text('By ${post.author} · ${post.minutes} minutes'),
        const SizedBox(height: 18),
        Text(post.description, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: () {
                if (!vm.toggleVote(VoteState.up)) showAuthSheet(context);
              },
              isSelected: vm.vote == VoteState.up,
              icon: const Icon(Icons.thumb_up_outlined),
              selectedIcon: const Icon(Icons.thumb_up),
              tooltip: 'Upvote recipe',
            ),
            Text('${vm.votes} votes'),
            IconButton(
              onPressed: () {
                if (!vm.toggleVote(VoteState.down)) showAuthSheet(context);
              },
              isSelected: vm.vote == VoteState.down,
              icon: const Icon(Icons.thumb_down_outlined),
              selectedIcon: const Icon(Icons.thumb_down),
              tooltip: 'Downvote recipe',
            ),
            OutlinedButton.icon(
              onPressed: () {
                if (!vm.toggleSaved()) showAuthSheet(context);
              },
              icon: Icon(vm.saved ? Icons.bookmark : Icons.bookmark_border),
              label: Text(vm.saved ? 'Saved' : 'Save recipe'),
            ),
            if (post.isVideo)
              FilledButton.icon(
                onPressed: () => context.push('/video/${post.id}'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Watch demo'),
              ),
          ],
        ),
        const SectionTitle('Good things inside'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ingredient in post.ingredients)
              Chip(
                label: Text(ingredient),
                avatar: const Icon(Icons.check, size: 16),
              ),
          ],
        ),
        const SectionTitle('Let’s make it'),
        for (final (index, step) in post.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 17,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(step)),
              ],
            ),
          ),
        const SectionTitle('Around the table'),
        for (final comment in vm.comments)
          _CommentBranch(comment: comment, vm: vm),
        if (vm.comments.isEmpty) const Text('Be the first to share a thought.'),
        const SizedBox(height: 18),
        if (vm.replyTo != null)
          Row(
            children: [
              const Expanded(child: Text('Replying to a comment')),
              TextButton(
                onPressed: () => vm.reply(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        TextField(
          controller: _comment,
          onChanged: vm.setDraft,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Share a tip or a little appreciation…',
          ),
        ),
        ErrorNotice(vm.error),
        FilledButton.icon(
          onPressed: vm.canWrite
              ? (vm.canSubmit
                    ? () {
                        if (vm.submitComment()) _comment.clear();
                      }
                    : null)
              : () => showAuthSheet(context),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(vm.canWrite ? 'Post comment' : 'Sign in to comment'),
        ),
      ],
    );
  }
}

class _CommentBranch extends StatelessWidget {
  const _CommentBranch({
    required this.comment,
    required this.vm,
    this.depth = 0,
  });
  final Comment comment;
  final PostDetailViewModel vm;
  final int depth;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: depth > 0 && depth < 4 ? 12 : 0, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comment.author,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(comment.text),
              TextButton(
                onPressed: () {
                  if (vm.canWrite) {
                    vm.reply(comment.id);
                  } else {
                    showAuthSheet(context);
                  }
                },
                child: const Text('Reply'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final reply in vm.replies(comment.id))
          _CommentBranch(comment: reply, vm: vm, depth: depth + 1),
      ],
    ),
  );
}
