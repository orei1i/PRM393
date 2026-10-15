// lib/features/search/presentation/controllers/global_search_controller.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/utils/text_search.dart';
import '../../../restaurant/data/location_service.dart';
import '../../data/search_api_service.dart';
import '../../domain/entities/search_result.dart';

/// What the search screen shows. Idle while [query] is empty.
class SearchState {
  const SearchState({
    this.query = '',
    this.result,
    this.loading = false,
    this.error,
  });

  /// The query being searched or last searched; '' = idle.
  final String query;

  /// Last loaded result. While [loading] it may still belong to the
  /// previous query, so the screen keeps it visible under a progress bar.
  final SearchResult? result;
  final bool loading;
  final Object? error;

  bool get isIdle => query.isEmpty;
}

/// One per search screen (dropped when it closes).
final globalSearchProvider =
    NotifierProvider.autoDispose<GlobalSearchController, SearchState>(
        GlobalSearchController.new);

class GlobalSearchController extends AutoDisposeNotifier<SearchState> {
  static const debounce = Duration(milliseconds: 350);

  /// Shorter queries keep the screen idle and send nothing.
  static const minLength = 2;

  /// Per group; the "Tất cả" tab shows 3 of each.
  static const resultLimit = 20;

  static bool isSearchable(String query) => query.trim().length >= minLength;

  Timer? _timer;
  int _requestId = 0;

  @override
  SearchState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _requestId++; // drop anything still in flight
    });
    return const SearchState();
  }

  /// While typing: idle under [minLength] characters, otherwise searches
  /// [debounce] after the last keystroke.
  void onQueryChanged(String raw) {
    _timer?.cancel();
    final q = raw.trim();
    if (!isSearchable(q)) return clear();
    _timer = Timer(debounce, () => _run(q));
  }

  /// Keyboard "search", a chip, or a pre-filled query: search right away.
  Future<void> submit(String raw) {
    _timer?.cancel();
    final q = raw.trim();
    if (!isSearchable(q)) {
      clear();
      return Future.value();
    }
    return _run(q);
  }

  Future<void> retry() =>
      state.query.isEmpty ? Future.value() : _run(state.query);

  void clear() {
    _timer?.cancel();
    _requestId++;
    state = const SearchState();
  }

  Future<void> _run(String q) async {
    final id = ++_requestId;
    state = SearchState(query: q, result: state.result, loading: true);
    try {
      final location = await ref.read(userLocationProvider.future);
      final dto = await ref
          .read(searchApiProvider)
          .search(q, near: location.point, limit: resultLimit);
      if (id != _requestId) return; // a newer query won
      state = SearchState(query: q, result: dto.toEntity());
    } catch (e) {
      if (id != _requestId) return;
      state = SearchState(query: q, error: e);
    }
  }
}

/// "Tìm gần đây": newest first, at most [RecentSearchesController.max],
/// kept in SharedPreferences (`vl.recent_searches`) across restarts.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
        RecentSearchesController.new);

class RecentSearchesController extends Notifier<List<String>> {
  static const prefsKey = 'vl.recent_searches';
  static const max = 8;

  @override
  List<String> build() =>
      ref.read(sharedPreferencesProvider).getStringList(prefsKey) ??
      const <String>[];

  Future<void> _save(List<String> next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (next.isEmpty) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setStringList(prefsKey, next);
    }
  }

  /// Moves [raw] to the front; "Bun rieu" and "bún riêu" count as one.
  Future<void> add(String raw) {
    final q = raw.trim();
    if (!GlobalSearchController.isSearchable(q)) return Future.value();
    final key = foldVietnamese(q);
    return _save([
      q,
      ...state.where((s) => foldVietnamese(s) != key),
    ].take(max).toList());
  }

  Future<void> remove(String query) =>
      _save(state.where((s) => s != query).toList());

  Future<void> clear() => _save(const []);
}
