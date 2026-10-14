// lib/core/config/env.dart

/// Build-time configuration, overridable with `--dart-define`:
///
/// ```bash
/// flutter run \
///   --dart-define=USE_MOCK_DATA=false \
///   --dart-define=API_BASE_URL=https://api.veganlife.vn/api/v1
/// ```
abstract final class Env {
  /// `true` → every feature uses its Mock repository (no backend needed).
  static const bool useMockData =
      bool.fromEnvironment('USE_MOCK_DATA', defaultValue: true);

  /// ASP.NET Core API root. 10.0.2.2 is the host machine from the Android emulator.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5080/api/v1',
  );

  /// Free AI questions for guests (the server is the source of truth).
  static const int guestTrialLimit =
      int.fromEnvironment('GUEST_TRIAL_LIMIT', defaultValue: 3);

  /// Mock-only switch for the scanner: `normal` | `empty` | `error`.
  static const String mockScanScenario =
      String.fromEnvironment('MOCK_SCAN_SCENARIO', defaultValue: 'normal');

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 45);
}
