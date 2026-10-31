// lib/features/search/presentation/controllers/global_search_controller.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/utils/text_search.dart';
import '../../../restaurant/data/location_service.dart';
import '../../data/search_api_service.dart';
import '../../domain/entities/search_result.dart';

/// The search screen's three states.
enum SearchPhase {
  /// Empty field: the discover page (recent, trending, categories…).
  idle,

  /// Typing: autocomplete rows only, no result tabs.
  typing,

  /// After Enter or a "Tìm «…»" row: the result tabs.
  results,
}

/// What the search screen shows.
class SearchState {
  const SearchState({
    this.phase = SearchPhase.idle,
    this.query = '',
    this.suggestions = const [],
    this.suggesting = false,
    this.result,
    this.loading = false,
    this.error,
  });

  final SearchPhase phase;

  /// The text being typed ([SearchPhase.typing]) or the query searched
  /// ([SearchPhase.results]); '' when idle.
  final String query;

  /// Autocomplete rows for the typed text (may still belong to a shorter
  /// prefix while [suggesting]).
  final List<SearchSuggestItem> suggestions;
  final bool suggesting;

  /// Last loaded result. While [loading] it may still belong to the
  /// previous query, so the screen keeps it visible under a progress bar.
  final SearchResult? result;
  final bool loading;
  final Object? error;

  bool get isIdle => phase == SearchPhase.idle;
  bool get isTyping => phase == SearchPhase.typing;
  bool get showsResults => phase == SearchPhase.results;
}

/// One per search screen (dropped when it closes).
final globalSearchProvider =
    NotifierProvider.autoDispose<GlobalSearchController, SearchState>(
        GlobalSearchController.new);

class GlobalSearchController extends AutoDisposeNotifier<SearchState> {
  /// Autocomplete waits this long after the last keystroke.
  static const debounce = Duration(milliseconds: 250);

  /// Shorter text gets no autocomplete and no search.
  static const minLength = 2;

  /// Per group; the "Tất cả" tab shows 3 of each.
  static const resultLimit = 20;

  static bool isSearchable(String query) => query.trim().length >= minLength;

  Timer? _timer;
  int _searchId = 0;
  int _suggestId = 0;

  @override
  SearchState build() {
    ref.onDispose(() {
      _timer?.cancel();
      // Drop anything still in flight.
      _searchId++;
      _suggestId++;
    });
    return const SearchState();
  }

  /// Every keystroke: an empty field goes idle; anything else is typing,
  /// with autocomplete [debounce] after the last keystroke (2+ characters).
  /// Editing after results drops them and goes back to typing.
  void onQueryChanged(String raw) {
    _timer?.cancel();
    final q = raw.trim();
    if (q.isEmpty) return clear();
    _searchId++; // a search still running is for the old text
    final searchable = isSearchable(q);
    state = SearchState(
      phase: SearchPhase.typing,
      query: q,
      // Keep the previous rows while the new ones load (no flicker).
      suggestions: searchable && state.isTyping ? state.suggestions : const [],
      suggesting: searchable,
      result: state.result,
    );
    if (searchable) _timer = Timer(debounce, () => _suggest(q));
  }

  Future<void> _suggest(String q) async {
    final id = ++_suggestId;
    try {
      final rows = await ref.read(searchApiProvider).suggest(q);
      if (id != _suggestId || !state.isTyping || state.query != q) return;
      state = SearchState(
        phase: SearchPhase.typing,
        query: q,
        suggestions: [for (final r in rows) r.toEntity()],
        result: state.result,
      );
    } catch (_) {
      // Autocomplete is optional: "Tìm «…»" still works.
      if (id != _suggestId || !state.isTyping || state.query != q) return;
      state = SearchState(
          phase: SearchPhase.typing, query: q, result: state.result);
    }
  }

  /// Enter, a "Tìm «…»" row, a chip or a pre-filled query: the result tabs.
  /// Under [minLength] characters nothing happens (an empty field goes
  /// idle).
  Future<void> submit(String raw) {
    _timer?.cancel();
    _suggestId++;
    final q = raw.trim();
    if (q.isEmpty) {
      clear();
      return Future.value();
    }
    if (!isSearchable(q)) return Future.value();
    return _run(q);
  }

  Future<void> retry() => state.showsResults && state.query.isNotEmpty
      ? _run(state.query)
      : Future.value();

  /// ✕: back to the discover page.
  void clear() {
    _timer?.cancel();
    _searchId++;
    _suggestId++;
    state = const SearchState();
  }

  Future<void> _run(String q) async {
    final id = ++_searchId;
    state = SearchState(
        phase: SearchPhase.results,
        query: q,
        result: state.result,
        loading: true);
    try {
      final location = await ref.read(userLocationProvider.future);
      final dto = await ref
          .read(searchApiProvider)
          .search(q, near: location.point, limit: resultLimit);
      if (id != _searchId) return; // a newer query won
      state = SearchState(
          phase: SearchPhase.results, query: q, result: dto.toEntity());
    } catch (e) {
      if (id != _searchId) return;
      state = SearchState(phase: SearchPhase.results, query: q, error: e);
    }
  }
}

/// The discover page, refetched when the location changes.
final searchDiscoverProvider =
    FutureProvider.autoDispose<SearchDiscover>((ref) async {
  final location = await ref.watch(userLocationProvider.future);
  final dto = await ref.watch(searchApiProvider).discover(near: location.point);
  return dto.toEntity();
});

/// "Tìm gần đây": newest first, at most [RecentSearchesController.max],
/// kept in SharedPreferences (`vl.recent_searches`) across restarts.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
        RecentSearchesController.new);

class RecentSearchesController extends Notifier<List<String>> {
  static const prefsKey = UserDataKeys.recentSearches;
  static const max = 8;

  @override
  List<String> build() {
    ref.watch(sessionEndCountProvider);
    return ref.read(sharedPreferencesProvider).getStringList(prefsKey) ??
        const <String>[];
  }

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

/// "Đã xem gần đây": recipes, posts and restaurants opened from search,
/// newest first, at most [RecentViewsController.max], kept on the device
/// (`vl.recent_views`).
final recentViewsProvider =
    NotifierProvider<RecentViewsController, List<RecentView>>(
        RecentViewsController.new);

class RecentViewsController extends Notifier<List<RecentView>> {
  static const prefsKey = UserDataKeys.recentViews;
  static const max = 10;

  @override
  List<RecentView> build() {
    ref.watch(sessionEndCountProvider);
    final raw =
        ref.read(sharedPreferencesProvider).getStringList(prefsKey) ?? const [];
    return [
      for (final item in raw)
        if (_decode(item) case final view?) view,
    ];
  }

  static RecentView? _decode(String item) {
    try {
      final json = jsonDecode(item);
      if (json is! Map<String, dynamic>) return null;
      final view = RecentView.fromJson(json);
      return view.id.isEmpty || view.kind == SuggestKind.query ? null : view;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(List<RecentView> next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    if (next.isEmpty) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setStringList(
          prefsKey, [for (final v in next) jsonEncode(v.toJson())]);
    }
  }

  /// Moves [view] to the front (one entry per item).
  Future<void> add(RecentView view) => _save([
        view,
        ...state.where((v) => !(v.kind == view.kind && v.id == view.id)),
      ].take(max).toList());

  Future<void> clear() => _save(const []);
}
