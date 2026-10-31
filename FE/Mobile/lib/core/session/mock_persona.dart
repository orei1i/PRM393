// lib/core/session/mock_persona.dart
import '../config/backend_modules.dart';
import 'mock_accounts.dart';
import 'session_controller.dart';

/// Who the signed-in user is inside the mock modules.
///
/// The mock stores (bookings, wallet, restaurants…) are seeded for the mock
/// accounts, while a real user has an ObjectId. So in a hybrid build a real
/// member acts as Minh Anh and a real chef as Tâm, instead of getting empty
/// dead ends. Mock modules show `DemoDataBanner` to stay honest about it.
///
/// Anything compared against a mock store's ids must use this, not
/// `session.userId`. With mock auth it is simply `session.userId`.
String? mockPersonaId(AuthSession session) {
  if (BackendModules.isMock(BackendModule.auth)) return session.userId;
  if (session.isGuest) return null;
  return session.isChef ? tamChefAccount.userId : minhAnhAccount.userId;
}
