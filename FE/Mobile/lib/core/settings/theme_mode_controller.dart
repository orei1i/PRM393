// lib/core/settings/theme_mode_controller.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/session_controller.dart';

/// Light / dark / follow system — chosen in Tôi › Cài đặt, persisted locally.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'vl.theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values
        .firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'Theo hệ thống',
        ThemeMode.light => 'Sáng',
        ThemeMode.dark => 'Tối',
      };
}
