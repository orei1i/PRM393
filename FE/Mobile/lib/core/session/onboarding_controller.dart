// lib/core/session/onboarding_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_controller.dart';

/// Whether the first-launch Welcome screen was left (`vl.onboarded`).
///
/// Set by "Khám phá không cần đăng nhập" and by any sign-in, sign-up or
/// sign-out, so Welcome shows once: signing out lands on Trang chủ as a
/// guest. Installs that were already signed in count as onboarded.
class OnboardingController extends Notifier<bool> {
  static const storageKey = 'vl.onboarded';

  @override
  bool build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return (prefs.getBool(storageKey) ?? false) ||
        prefs.getString(SessionController.accessTokenKey) != null;
  }

  Future<void> complete() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(storageKey, true);
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
