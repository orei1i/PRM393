// lib/features/chef/presentation/controllers/chef_controllers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chef_api_service.dart';
import '../../domain/entities/chef.dart';

class ChefDirectoryState {
  const ChefDirectoryState({
    required this.chefs,
    this.query = '',
    this.specialty,
    this.searching = false,
  });

  final List<Chef> chefs;
  final String query;
  final String? specialty;

  /// A new query is in flight; the previous results stay on screen.
  final bool searching;

  ChefDirectoryState copyWith({bool? searching}) => ChefDirectoryState(
        chefs: chefs,
        query: query,
        specialty: specialty,
        searching: searching ?? this.searching,
      );
}

final chefDirectoryProvider =
    AsyncNotifierProvider<ChefDirectoryController, ChefDirectoryState>(
        ChefDirectoryController.new);

class ChefDirectoryController extends AsyncNotifier<ChefDirectoryState> {
  String _query = '';
  String? _specialty;
  int _requestId = 0;

  @override
  Future<ChefDirectoryState> build() => _fetch(ref.watch(chefApiProvider));

  Future<ChefDirectoryState> _fetch(ChefApiService api) async {
    final list = await api.listChefs(query: _query, specialty: _specialty);
    return ChefDirectoryState(
      chefs: list.map((c) => c.toEntity()).toList(),
      query: _query,
      specialty: _specialty,
    );
  }

  Future<void> search(String query) =>
      _reload(query: query.trim(), specialty: _specialty);

  Future<void> setSpecialty(String? specialty) =>
      _reload(query: _query, specialty: specialty);

  Future<void> _reload(
      {required String query, required String? specialty}) async {
    if (query == _query && specialty == _specialty && state.hasValue) return;
    _query = query;
    _specialty = specialty;
    final id = ++_requestId;
    if (state.hasValue) {
      state = AsyncData(state.requireValue.copyWith(searching: true));
    }
    final next =
        await AsyncValue.guard(() => _fetch(ref.read(chefApiProvider)));
    if (id == _requestId) state = next; // drop stale responses while typing
  }
}
