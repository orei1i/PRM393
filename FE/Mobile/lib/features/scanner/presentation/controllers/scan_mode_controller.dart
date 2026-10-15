// lib/features/scanner/presentation/controllers/scan_mode_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/session/session_controller.dart';
import '../../domain/scan_mode.dart';

/// The scan mode a tap on the centre button opens, remembered across app
/// restarts. Picking a mode from the long-press menu makes it the default.
final scanModeProvider =
    NotifierProvider<ScanModeController, ScanMode>(ScanModeController.new);

class ScanModeController extends Notifier<ScanMode> {
  static const storageKey = 'vl.scan_mode';

  /// Bare test containers have no SharedPreferences: the mode then lives
  /// for the session only.
  SharedPreferences? get _prefs {
    try {
      return ref.read(sharedPreferencesProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  ScanMode build() => ScanMode.fromStorage(_prefs?.getString(storageKey));

  void remember(ScanMode mode) {
    if (mode == state) return;
    state = mode;
    _prefs?.setString(storageKey, mode.storageValue);
  }
}
