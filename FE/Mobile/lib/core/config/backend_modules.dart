// lib/core/config/backend_modules.dart
import 'package:flutter/foundation.dart';

import 'env.dart';

/// One switchable part of the app: either its Remote service (real BE) or
/// its Mock repository.
enum BackendModule {
  auth,
  profile,
  community,
  media,
  reels,
  video,
  planner,
  pantry,
  ingredients,
  allergens,
  recipes,
  recipeSocial,
  scanner,
  chatbot,
  search,
  restaurants,
  geocoding,
  ads,
  chefs,
  bookings,
  commerce,
  chefStudio,
  chefWallet,
}

/// The one place that decides which modules talk to the real BE:
///
/// ```bash
/// flutter run --dart-define=USE_MOCK_DATA=false                  # hybrid
/// flutter run --dart-define=USE_MOCK_DATA=false \
///   --dart-define=BACKEND_MOCK_MODULES=community,scanner \
///   --dart-define=BACKEND_REAL_MODULES=video
/// ```
///
/// - `USE_MOCK_DATA=true` (the default): every module is mock.
/// - `USE_MOCK_DATA=false`: [supportedByBackend] is real, then
///   `BACKEND_REAL_MODULES` adds and `BACKEND_MOCK_MODULES` removes (a module
///   named in both ends up mock).
/// - `auth` mock means every module is mock: real modules need a JWT, and a
///   mock session has none (it would be a 401 loop).
///
/// Module names are the [BackendModule] names, case-insensitive. Unknown names
/// are ignored, with a debug log.
abstract final class BackendModules {
  /// What the BE supports today.
  static const Set<BackendModule> supportedByBackend = {
    BackendModule.auth,
    BackendModule.profile,
    BackendModule.community,
    BackendModule.media,
    BackendModule.reels,
    BackendModule.planner,
    BackendModule.pantry,
    BackendModule.ingredients,
    BackendModule.allergens,
    BackendModule.recipes,
    BackendModule.scanner,
  };

  static final Set<BackendModule> _configured = resolveRealModules(
    useMockData: Env.useMockData,
    mockModules: const String.fromEnvironment('BACKEND_MOCK_MODULES'),
    realModules: const String.fromEnvironment('BACKEND_REAL_MODULES'),
  );

  static Set<BackendModule>? _override;

  static Set<BackendModule> get _real => _override ?? _configured;

  static bool isMock(BackendModule module) => !_real.contains(module);

  static bool isReal(BackendModule module) => _real.contains(module);

  /// At least one module talks to the real BE, so a mock module is a degraded
  /// one (see `DemoDataBanner`). False in a fully mock build.
  static bool get isHybrid => _real.isNotEmpty;

  /// Makes exactly [real] the real modules, or restores the build's
  /// configuration when null. Reset it in `tearDown`.
  ///
  /// Taken literally: unlike the dart-defines it does not apply the "auth mock
  /// means all mock" rule, so a widget test can check a label with
  /// `{BackendModule.community}` while still signing in on the mock auth.
  @visibleForTesting
  static void debugOverride(Set<BackendModule>? real) => _override = real;

  /// The real modules for one configuration (see the class comment).
  @visibleForTesting
  static Set<BackendModule> resolveRealModules({
    required bool useMockData,
    String mockModules = '',
    String realModules = '',
  }) {
    if (useMockData) return const {};
    final real = {...supportedByBackend, ..._parse(realModules)}
      ..removeAll(_parse(mockModules));
    return real.contains(BackendModule.auth) ? real : const {};
  }

  static Set<BackendModule> _parse(String csv) {
    final byName = {
      for (final m in BackendModule.values) m.name.toLowerCase(): m
    };
    final modules = <BackendModule>{};
    for (final raw in csv.split(',')) {
      final name = raw.trim().toLowerCase();
      if (name.isEmpty) continue;
      final module = byName[name];
      if (module == null) {
        debugPrint('BackendModules: unknown module "$name" ignored.');
      } else {
        modules.add(module);
      }
    }
    return modules;
  }

  // ---- capabilities ---------------------------------------------------------
  // What the UI asks instead of testing module names. When the BE ships one,
  // its getter changes here and nowhere else.

  /// PUT `/posts/{id}` ("Sửa bài").
  static bool get postEdit => isMock(BackendModule.community);

  /// PUT on a comment ("Sửa").
  static bool get commentEdit => isMock(BackendModule.community);

  /// GET `/posts/{id}/comments/{cid}/replies` ("Xem thêm N phản hồi").
  static bool get commentReplyPaging => isMock(BackendModule.community);

  /// GET `/users/me/comments` (the "Bình luận" tab of "Nội dung của tôi").
  static bool get myComments => isMock(BackendModule.community);

  /// `restaurantId` on a post ("Gắn quán").
  static bool get restaurantTag => isMock(BackendModule.community);

  /// POST `/meal-plans/current/adjust` ("Chỉnh thực đơn với AI").
  static bool get planAdjust => isMock(BackendModule.planner);

  /// Emptying a week that already has meals ("Tự lên thực đơn"): POST
  /// `/meal-plans` returns that week as it is (B29). A week can still be
  /// started empty when there is none.
  static bool get planClear => isMock(BackendModule.planner);

  /// `waistCm` and `bodyFatPct` on a body measurement.
  static bool get checkInExtras => isMock(BackendModule.planner);

  /// `servings` on POST `/recipes` ("Số phần ăn" of an own recipe).
  static bool get recipeServings => isMock(BackendModule.recipes);

  /// Macros of a typed dish on POST `/meal-plans/current/meals`.
  static bool get manualMealMacros => isMock(BackendModule.planner);
}
