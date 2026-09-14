/// Composition configuration only. The frontend never makes network requests.
abstract final class BackendConfig {
  static const usesMocks = true;
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const enableRoleSwitcher = bool.fromEnvironment('DEMO_ROLES');
}
