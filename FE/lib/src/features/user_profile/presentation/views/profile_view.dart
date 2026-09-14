import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/theme_view_model.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../auth/presentation/view_models/auth_view_model.dart';
import '../view_models/user_profile_view_model.dart';
import '../widgets/user_content_list.dart';

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UserProfileViewModel>();
    final theme = context.watch<ThemeViewModel>();
    return PageBody(
      maxWidth: 920,
      children: [
        const PageHeading(
          eyebrow: 'Your little corner',
          title: 'Growing, one day at a time.',
          subtitle: 'Your recipes, conversations, and plant-powered journey.',
        ),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.face_rounded, size: 42),
              ),
              const SizedBox(height: 18),
              Text(
                vm.profile.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(vm.profile.location),
              const SizedBox(height: 14),
              Text(vm.profile.bio),
              const SizedBox(height: 20),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  Text(
                    '${vm.summary.posts} recipes',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${vm.summary.videos} videos',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${vm.summary.comments} comments',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.push('/my-content'),
                icon: const Icon(Icons.edit_note),
                label: const Text('Manage my content'),
              ),
            ],
          ),
        ),
        const SectionTitle('Make yourself at home'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final mode in ThemeMode.values)
              ChoiceChip(
                label: Text(
                  '${mode.name[0].toUpperCase()}${mode.name.substring(1)} theme',
                ),
                selected: theme.mode == mode,
                onSelected: (_) => theme.setMode(mode),
              ),
          ],
        ),
        const SectionTitle('Your contributions'),
        const UserContentList(),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: context.read<AuthViewModel>().signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out of demo account'),
        ),
      ],
    );
  }
}
