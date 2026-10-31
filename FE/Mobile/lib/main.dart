// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const VeganLifeApp(),
    ),
  );
  // After the first frame, so a sign-out can show its snackbar.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    container.read(sessionControllerProvider.notifier).revalidate();
  });
}
