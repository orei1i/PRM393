import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/auth_view_model.dart';

Future<void> showAuthSheet(BuildContext context) {
  final auth = context.read<AuthViewModel>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          28 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.spa_outlined,
              size: 42,
              color: Theme.of(sheetContext).colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              'A little greener, together.',
              style: Theme.of(sheetContext).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Join the community to save recipes, share your ideas, and explore your weekly meal plan.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Demo sign-in · no email or password collected',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  auth.signInAsMember();
                },
                child: const Text('Continue as demo member'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
