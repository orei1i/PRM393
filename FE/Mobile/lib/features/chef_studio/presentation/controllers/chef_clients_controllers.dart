// lib/features/chef_studio/presentation/controllers/chef_clients_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../meal_planner/data/chef_suggestion_api_service.dart';
import '../../data/chef_clients_api_service.dart';
import '../../data/models/chef_client_models.dart';

/// Bumped after the chef sends a suggestion, so client cards ("Đề xuất gần
/// nhất") and the sent lists refetch.
final chefSuggestionRevisionProvider =
    NotifierProvider<ChefSuggestionRevision, int>(ChefSuggestionRevision.new);

class ChefSuggestionRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Same scope as the other chef-studio lists: refetch on account changes
/// (sign-out, Minh Anh ↔ Tâm), any commerce change and new suggestions.
void _watchScope(Ref ref) {
  ref
    ..watch(commerceAccountProvider)
    ..watch(commerceRevisionProvider)
    ..watch(chefSuggestionRevisionProvider);
}

/// "Khách hàng": everyone who bought one of my services.
final chefClientsProvider =
    FutureProvider.autoDispose<List<ChefClientDto>>((ref) async {
  _watchScope(ref);
  return ref.watch(chefClientsApiProvider).myClients();
});

final chefClientProvider =
    FutureProvider.autoDispose.family<ChefClientDto, String>((ref, userId) {
  _watchScope(ref);
  return ref.watch(chefClientsApiProvider).client(userId);
});

/// Dishes I suggested to one client, newest first.
final sentSuggestionsProvider = FutureProvider.autoDispose
    .family<List<SentSuggestionDto>, String>((ref, userId) {
  _watchScope(ref);
  return ref.watch(chefSuggestionApiProvider).sentTo(userId);
});
