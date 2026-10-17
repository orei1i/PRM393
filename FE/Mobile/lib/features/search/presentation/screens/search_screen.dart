// lib/features/search/presentation/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/text_search.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/data/community_api_service.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/screens/post_detail_screen.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../../restaurant/domain/entities/restaurant.dart';
import '../../../restaurant/domain/geo.dart';
import '../../../restaurant/presentation/screens/restaurant_detail_screen.dart';
import '../../../restaurant/presentation/screens/restaurant_nearby_screen.dart';
import '../../../restaurant/presentation/widgets/restaurant_tile.dart';
import '../../domain/entities/search_result.dart';
import '../controllers/global_search_controller.dart';
import '../widgets/search_tiles.dart';

/// Global search (posts, videos, recipes, restaurants). Guests allowed.
///
/// Three states: **idle** (empty field) shows what to look for: "Tìm gần
/// đây", "Xu hướng tìm kiếm", "Danh mục", "Món theo mùa", "Công thức được
/// yêu thích", "Đã xem gần đây" and "Quán chay gần bạn". **Typing** shows
/// autocomplete rows only ("Tìm «…»" first). **Results** (after Enter or
/// "Tìm «…»") shows the tabs Tất cả · Công thức · Video · Bài viết · Quán;
/// when a recipe matches, "Gợi ý cho «món»" leads with related videos/posts
/// and nearby restaurants serving the dish. Editing the query goes back to
/// typing; ✕ back to idle.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Pre-filled query, e.g. a recipe name from "Tìm video & quán liên quan":
  /// opens straight on the results.
  final String? initialQuery;

  static Route<void> route({String? initialQuery}) => MaterialPageRoute<void>(
        builder: (_) => SearchScreen(initialQuery: initialQuery),
      );

  static const tabLabels = ['Tất cả', 'Công thức', 'Video', 'Bài viết', 'Quán'];

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final _field =
      TextEditingController(text: widget.initialQuery?.trim() ?? '');
  final _focus = FocusNode();
  late final TabController _tabs;

  /// A post picked from autocomplete or "Đã xem gần đây" is being fetched.
  bool _opening = false;

  GlobalSearchController get _search => ref.read(globalSearchProvider.notifier);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: SearchScreen.tabLabels.length, vsync: this);
    final initial = _field.text;
    if (GlobalSearchController.isSearchable(initial)) {
      // Providers can't change while the tree builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(initial);
      });
    }
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _search.onQueryChanged(value);
    setState(() {}); // toggles the clear button
  }

  void _submit(String value) {
    final q = value.trim();
    if (GlobalSearchController.isSearchable(q)) {
      ref.read(recentSearchesProvider.notifier).add(q);
      _tabs.index = 0;
      _focus.unfocus();
    }
    _search.submit(q);
  }

  /// A recent, trending, category or "query" row: fill the field and search.
  void _pick(String query) {
    _field
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    _submit(query);
    setState(() {});
  }

  void _clear() {
    _field.clear();
    _search.clear();
    _focus.requestFocus();
    setState(() {});
  }

  /// Opening a result counts as a search worth remembering.
  void _rememberQuery() {
    final state = ref.read(globalSearchProvider);
    if (state.showsResults && state.query.isNotEmpty) {
      ref.read(recentSearchesProvider.notifier).add(state.query);
    }
  }

  void _viewed(RecentView view) =>
      ref.read(recentViewsProvider.notifier).add(view);

  void _openPost(Post post) {
    _rememberQuery();
    _viewed(RecentView(
      kind: SuggestKind.post,
      id: post.id,
      title: post.title,
      subtitle: '${post.hasVideo ? 'Video' : post.type.label} · '
          '${post.author.name}',
    ));
    Navigator.of(context).push(PostDetailScreen.route(post));
  }

  Future<void> _openPostById(String id) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final post =
          (await ref.read(communityApiProvider).getPost(id)).toEntity();
      if (mounted) _openPost(post);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openRecipe(String id, String name) {
    _rememberQuery();
    _viewed(RecentView(
        kind: SuggestKind.recipe, id: id, title: name, subtitle: 'Công thức'));
    Navigator.of(context).push(RecipeDetailScreen.route(id, name: name));
  }

  void _openRestaurantById(String id, String name, {String? subtitle}) {
    _rememberQuery();
    _viewed(RecentView(
        kind: SuggestKind.restaurant,
        id: id,
        title: name,
        subtitle: subtitle ?? 'Quán'));
    Navigator.of(context).push(RestaurantDetailScreen.route(id, name: name));
  }

  void _openRestaurant(Restaurant r) =>
      _openRestaurantById(r.id, r.name, subtitle: r.address);

  void _openNearby({String? food}) {
    if (food != null) _rememberQuery();
    Navigator.of(context)
        .push(RestaurantNearbyScreen.route(initialQuery: food));
  }

  /// An autocomplete row: a query searches, anything else opens directly.
  void _onSuggestion(SearchSuggestItem item) {
    final id = item.id;
    switch (item.kind) {
      case SuggestKind.query:
        _pick(item.text);
      case SuggestKind.recipe when id != null:
        _openRecipe(id, item.text);
      case SuggestKind.post when id != null:
        _openPostById(id);
      case SuggestKind.restaurant when id != null:
        _openRestaurantById(id, item.text, subtitle: item.subtitle);
      default:
        _pick(item.text);
    }
  }

  void _openRecentView(RecentView view) => switch (view.kind) {
        SuggestKind.recipe => _openRecipe(view.id, view.title),
        SuggestKind.restaurant =>
          _openRestaurantById(view.id, view.title, subtitle: view.subtitle),
        _ => _openPostById(view.id),
      };

  @override
  Widget build(BuildContext context) {
    // Keeps the discover page loaded while typing, so ✕ shows it at once.
    ref.listen(searchDiscoverProvider, (_, __) {});
    final state = ref.watch(globalSearchProvider);
    final result = state.result;
    final showTabs = state.showsResults &&
        state.error == null &&
        result != null &&
        !result.isEmpty;
    final busy =
        _opening || (state.showsResults && state.loading && result != null);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          focusNode: _focus,
          autofocus: widget.initialQuery == null,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _submit,
          decoration: const InputDecoration(
            hintText: 'Tìm công thức, video, bài viết, quán…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [
          if (_field.text.isNotEmpty)
            IconButton(
              tooltip: 'Xoá',
              onPressed: _clear,
              icon: const Icon(Icons.close_rounded),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(showTabs ? 48 + 2 : 2),
          child: Column(
            children: [
              if (showTabs)
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final label in SearchScreen.tabLabels)
                      Tab(text: label),
                  ],
                ),
              SizedBox(
                height: 2,
                child:
                    busy ? const LinearProgressIndicator(minHeight: 2) : null,
              ),
            ],
          ),
        ),
      ),
      body: switch (state.phase) {
        SearchPhase.idle => _DiscoverView(
            onPick: _pick,
            onRecipe: _openRecipe,
            onRestaurant: _openRestaurant,
            onRecentView: _openRecentView,
            onAllNearby: () => _openNearby(),
          ),
        SearchPhase.typing => _SuggestionsView(
            state: state,
            onSearch: _pick,
            onSuggestion: _onSuggestion,
          ),
        SearchPhase.results => _results(state),
      },
    );
  }

  Widget _results(SearchState state) {
    final result = state.result;
    if (state.error != null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorStateView(error: state.error!, onRetry: _search.retry),
        ),
      );
    }
    if (result == null) return const SearchResultsSkeleton();
    if (result.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.search_off_rounded,
            title: 'Không tìm thấy «${result.query}»',
            message: 'Thử từ khoá ngắn hơn hoặc không dấu',
          ),
        ),
      );
    }
    void openRecipe(RecipeSummary r) => _openRecipe(r.id, r.name);
    return TabBarView(
      controller: _tabs,
      children: [
        _AllTab(
          result: result,
          onMore: (tab) => _tabs.animateTo(tab),
          onPost: _openPost,
          onRecipe: openRecipe,
          onRestaurant: _openRestaurant,
          onAllRestaurants: (food) => _openNearby(food: food),
        ),
        _ResultList(
          query: result.query,
          what: 'công thức',
          children: [
            for (final r in result.recipes)
              SearchRecipeTile(recipe: r, onTap: () => openRecipe(r)),
          ],
        ),
        _ResultList(
          query: result.query,
          what: 'video',
          children: [
            for (final p in result.videos)
              SearchPostTile(post: p, onTap: () => _openPost(p)),
          ],
        ),
        _ResultList(
          query: result.query,
          what: 'bài viết',
          children: [
            for (final p in result.posts)
              SearchPostTile(post: p, onTap: () => _openPost(p)),
          ],
        ),
        _ResultList(
          query: result.query,
          what: 'quán',
          dividerIndent: 92,
          children: [
            for (final r in result.restaurants)
              RestaurantTile(restaurant: r, onTap: () => _openRestaurant(r)),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- typing --

/// "Tìm «…»" first, then the autocomplete rows (type icon, text, subtitle).
/// Under 2 characters: the matching recent searches.
class _SuggestionsView extends ConsumerWidget {
  const _SuggestionsView({
    required this.state,
    required this.onSearch,
    required this.onSuggestion,
  });

  final SearchState state;
  final ValueChanged<String> onSearch;
  final ValueChanged<SearchSuggestItem> onSuggestion;

  static IconData iconFor(SuggestKind kind) => switch (kind) {
        SuggestKind.query => Icons.search_rounded,
        SuggestKind.recipe => Icons.rice_bowl_outlined,
        SuggestKind.post => Icons.article_outlined,
        SuggestKind.restaurant => Icons.storefront_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = state.query;
    final muted = context.vl.muted;
    if (!GlobalSearchController.isSearchable(q)) {
      final folded = foldVietnamese(q);
      final recent = ref
          .watch(recentSearchesProvider)
          .where((s) => foldVietnamese(s).contains(folded))
          .toList();
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          for (final s in recent)
            ListTile(
              leading: Icon(Icons.history_rounded, color: muted),
              title: Text(s),
              trailing: Icon(Icons.north_west_rounded, size: 18, color: muted),
              onTap: () => onSearch(s),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Nhập thêm để xem gợi ý',
                style: context.textStyles.bodyMedium?.copyWith(color: muted)),
          ),
        ],
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding:
          EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        ListTile(
          key: const ValueKey('search-submit-row'),
          leading: Icon(Icons.search_rounded, color: context.colors.primary),
          title: Text('Tìm «$q»',
              style: context.textStyles.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          onTap: () => onSearch(q),
        ),
        if (state.suggesting && state.suggestions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
                child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        for (final item in state.suggestions)
          ListTile(
            leading: Icon(iconFor(item.kind), color: muted),
            title:
                Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: item.subtitle == null ? null : Text(item.subtitle!),
            trailing: item.kind == SuggestKind.query
                ? Icon(Icons.north_west_rounded, size: 18, color: muted)
                : Icon(Icons.chevron_right_rounded, color: muted),
            onTap: () => onSuggestion(item),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------- idle --

/// What to look for before typing anything (no large empty area).
class _DiscoverView extends ConsumerWidget {
  const _DiscoverView({
    required this.onPick,
    required this.onRecipe,
    required this.onRestaurant,
    required this.onRecentView,
    required this.onAllNearby,
  });

  final ValueChanged<String> onPick;
  final void Function(String id, String name) onRecipe;
  final ValueChanged<Restaurant> onRestaurant;
  final ValueChanged<RecentView> onRecentView;
  final VoidCallback onAllNearby;

  static IconData categoryIcon(String id) => switch (id) {
        'main' => Icons.rice_bowl_rounded,
        'breakfast' => Icons.free_breakfast_outlined,
        'noodles' => Icons.ramen_dining_rounded,
        'drinks' => Icons.local_drink_outlined,
        'dessert' => Icons.icecream_outlined,
        'quick' => Icons.timer_outlined,
        _ => Icons.category_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider);
    final views = ref.watch(recentViewsProvider);
    final discover = ref.watch(searchDiscoverProvider);
    final data = discover.valueOrNull;
    final muted = context.vl.muted;

    Widget title(String text) => Text(text,
        style: context.textStyles.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700));
    const gap = SizedBox(height: 22);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (recent.isNotEmpty) ...[
          _HeaderRow(
            title: title('Tìm gần đây'),
            actionLabel: 'Xoá lịch sử',
            onAction: () => ref.read(recentSearchesProvider.notifier).clear(),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in recent)
                InputChip(
                  avatar: const Icon(Icons.history_rounded, size: 18),
                  label: Text(q),
                  onPressed: () => onPick(q),
                  onDeleted: () =>
                      ref.read(recentSearchesProvider.notifier).remove(q),
                  deleteButtonTooltipMessage: 'Xoá «$q»',
                ),
            ],
          ),
          gap,
        ],
        if (data == null)
          discover.hasError
              ? Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, color: muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Chưa tải được gợi ý',
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: muted)),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(searchDiscoverProvider),
                      child: const Text('Thử lại'),
                    ),
                  ],
                )
              : const _DiscoverSkeleton()
        else ...[
          if (data.trending.isNotEmpty) ...[
            title('Xu hướng tìm kiếm'),
            const SizedBox(height: 4),
            for (final (i, q) in data.trending.take(6).indexed)
              InkWell(
                onTap: () => onPick(q),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('${i + 1}',
                            style: context.textStyles.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: i < 3 ? context.colors.primary : muted)),
                      ),
                      Expanded(
                          child: Text(q, style: context.textStyles.bodyLarge)),
                      Icon(Icons.trending_up_rounded,
                          size: 18, color: context.colors.primary),
                    ],
                  ),
                ),
              ),
            gap,
          ],
          if (data.categories.isNotEmpty) ...[
            title('Danh mục'),
            const SizedBox(height: 10),
            _CategoryGrid(categories: data.categories, onPick: onPick),
            gap,
          ],
          if (data.seasonal.isNotEmpty) ...[
            title('Món theo mùa'),
            Text(
              'Tháng ${DateTime.now().month}: '
              '${{for (final s in data.seasonal) s.ingredient}.join(', ')}…',
              style: context.textStyles.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: data.seasonal.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final s = data.seasonal[i];
                  return SizedBox(
                    width: 156,
                    child: VLCard(
                      padding: EdgeInsets.zero,
                      onTap: () => onRecipe(s.recipeId, s.name),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FoodCover(seed: s.coverSeed, height: 92),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                            child: Text(s.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.textStyles.titleSmall),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            gap,
          ],
          if (data.popularRecipes.isNotEmpty) ...[
            title('Công thức được yêu thích'),
            const SizedBox(height: 4),
            for (final r in data.popularRecipes.take(5))
              SearchRecipeTile(
                  recipe: r, dense: true, onTap: () => onRecipe(r.id, r.name)),
            gap,
          ],
        ],
        if (views.isNotEmpty) ...[
          _HeaderRow(
            title: title('Đã xem gần đây'),
            actionLabel: 'Xoá',
            onAction: () => ref.read(recentViewsProvider.notifier).clear(),
          ),
          for (final v in views)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: context.colors.secondaryContainer,
                child: Icon(_SuggestionsView.iconFor(v.kind),
                    size: 20, color: context.colors.primary),
              ),
              title:
                  Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: v.subtitle == null
                  ? null
                  : Text(v.subtitle!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onRecentView(v),
            ),
          gap,
        ],
        _HeaderRow(
          title: title('Quán chay gần bạn'),
          actionKey: const ValueKey('search-nearby-all'),
          actionLabel: 'Xem tất cả',
          onAction: onAllNearby,
        ),
        if (data != null && data.nearbyRestaurants.isNotEmpty)
          for (final r in data.nearbyRestaurants.take(3))
            _NearbyRow(restaurant: r, onTap: () => onRestaurant(r))
        else if (data != null)
          VLCard(
            onTap: onAllNearby,
            child: Text('Xem quán gần nhất, quán đã chứng nhận và đánh giá.',
                style: context.textStyles.bodyMedium?.copyWith(color: muted)),
          ),
      ],
    );
  }
}

/// One of the 3 nearest restaurants on the idle page.
class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.restaurant, required this.onTap});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final km = r.distanceKm;
    final meta = [
      if (km != null) formatDistance(km),
      r.address,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: context.colors.secondaryContainer,
        child: Icon(Icons.storefront_outlined, color: context.colors.primary),
      ),
      title: Row(
        children: [
          Flexible(
              child:
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (r.isVeganCertified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified_rounded, size: 16, color: context.vl.success),
          ],
        ],
      ),
      subtitle: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: context.vl.muted),
      onTap: onTap,
    );
  }
}

/// "Danh mục": 3 per row on phones (2 with large text), icon over label.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.onPick});

  final List<SearchCategory> categories;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final perRow = scale > 1.3 ? 2 : 3;
      const spacing = 8.0;
      final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final c in categories)
            SizedBox(
              width: width,
              child: VLCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                color: context.colors.secondaryContainer.withValues(alpha: 0.5),
                onTap: () => onPick(c.query),
                child: Column(
                  children: [
                    Icon(_DiscoverView.categoryIcon(c.id),
                        color: context.colors.primary),
                    const SizedBox(height: 6),
                    Text(c.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _DiscoverSkeleton extends StatelessWidget {
  const _DiscoverSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 160, height: 18),
          const SizedBox(height: 12),
          for (var i = 0; i < 4; i++) ...[
            const SkeletonBox(height: 16),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 10),
          const SkeletonBox(width: 100, height: 18),
          const SizedBox(height: 12),
          const SkeletonBox(height: 72),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- results --
/// "Tất cả": the suggestion block, then 3 results per group with
/// "Xem thêm" switching to that group's tab.
class _AllTab extends StatelessWidget {
  const _AllTab({
    required this.result,
    required this.onMore,
    required this.onPost,
    required this.onRecipe,
    required this.onRestaurant,
    required this.onAllRestaurants,
  });

  static const perGroup = 3;

  final SearchResult result;
  final ValueChanged<int> onMore;
  final ValueChanged<Post> onPost;
  final ValueChanged<RecipeSummary> onRecipe;
  final ValueChanged<Restaurant> onRestaurant;
  final ValueChanged<String> onAllRestaurants;

  List<Widget> _group<T>({
    required String title,
    required int tab,
    required List<T> items,
    required Widget Function(T item) tile,
    double dividerIndent = 16,
  }) {
    if (items.isEmpty) return const [];
    return [
      _GroupHeader(
        title: title,
        count: items.length,
        onMore: items.length > perGroup ? () => onMore(tab) : null,
      ),
      for (final (i, item) in items.take(perGroup).indexed) ...[
        if (i > 0) SearchRowDivider(indent: dividerIndent),
        tile(item),
      ],
      const _GroupGap(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final suggestion = result.suggestion;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding:
          EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (suggestion != null) ...[
          _SuggestionBlock(
            suggestion: suggestion,
            onRecipe: onRecipe,
            onPost: onPost,
            onRestaurant: onRestaurant,
            onAllRestaurants: onAllRestaurants,
          ),
          const _GroupGap(),
        ],
        ..._group(
          title: 'Công thức',
          tab: 1,
          items: result.recipes,
          tile: (r) => SearchRecipeTile(recipe: r, onTap: () => onRecipe(r)),
        ),
        ..._group(
          title: 'Video',
          tab: 2,
          items: result.videos,
          tile: (p) => SearchPostTile(post: p, onTap: () => onPost(p)),
        ),
        ..._group(
          title: 'Bài viết',
          tab: 3,
          items: result.posts,
          tile: (p) => SearchPostTile(post: p, onTap: () => onPost(p)),
        ),
        ..._group(
          title: 'Quán',
          tab: 4,
          items: result.restaurants,
          dividerIndent: 92,
          tile: (r) =>
              RestaurantTile(restaurant: r, onTap: () => onRestaurant(r)),
        ),
      ],
    );
  }
}

/// "Gợi ý cho «Bún riêu chay»": the recipe, "Video & bài viết liên quan"
/// (horizontal cards) and "Quán gợi ý" (up to 3 + "Xem tất cả quán").
class _SuggestionBlock extends StatelessWidget {
  const _SuggestionBlock({
    required this.suggestion,
    required this.onRecipe,
    required this.onPost,
    required this.onRestaurant,
    required this.onAllRestaurants,
  });

  final SearchSuggestion suggestion;
  final ValueChanged<RecipeSummary> onRecipe;
  final ValueChanged<Post> onPost;
  final ValueChanged<Restaurant> onRestaurant;
  final ValueChanged<String> onAllRestaurants;

  @override
  Widget build(BuildContext context) {
    final recipe = suggestion.recipe;
    return ColoredBox(
      color: context.colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_outlined,
                    color: context.colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Gợi ý cho «${recipe.name}»',
                      style: context.textStyles.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          SearchRecipeTile(recipe: recipe, onTap: () => onRecipe(recipe)),
          if (suggestion.relatedPosts.isNotEmpty) ...[
            const _SubHeader('Video & bài viết liên quan'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              // Equal-height cards, however long each title is.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, post)
                        in suggestion.relatedPosts.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      RelatedPostCard(post: post, onTap: () => onPost(post)),
                    ],
                  ],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: _HeaderRow(
              title: Text('Quán gợi ý', style: context.textStyles.titleSmall),
              actionKey: const ValueKey('search-all-restaurants'),
              actionLabel: 'Xem tất cả quán',
              onAction: () => onAllRestaurants(recipe.name),
            ),
          ),
          if (suggestion.restaurants.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Chưa thấy quán nào quanh bạn nhắc tới món này.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              ),
            )
          else
            for (final (i, r) in suggestion.restaurants.indexed) ...[
              if (i > 0) const RestaurantTileDivider(),
              RestaurantTile(restaurant: r, onTap: () => onRestaurant(r)),
            ],
        ],
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(text, style: context.textStyles.titleSmall),
      );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count, this.onMore});

  final String title;
  final int count;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 8, onMore == null ? 8 : 0),
        child: _HeaderRow(
          title: Text('$title · $count',
              style: context.textStyles.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          actionLabel: 'Xem thêm',
          onAction: onMore,
        ),
      ),
    );
  }
}

/// A section title with an optional text action pinned to the right end of
/// the row ("Xem tất cả quán", "Xem thêm"). The title takes the rest of the
/// row; the action may use up to half of it and wraps there with large text
/// instead of overflowing.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final Widget title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(child: title),
          if (label != null && onAction != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
              child: TextButton(
                key: actionKey,
                onPressed: onAction,
                child: Text(label, textAlign: TextAlign.end),
              ),
            ),
        ],
      ),
    );
  }
}

/// The surface-tone band between groups, like the feed's post gap.
class _GroupGap extends StatelessWidget {
  const _GroupGap();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.surfaceContainerHigh,
        child: const SizedBox(height: 8, width: double.infinity),
      );
}

/// One group's full list (Công thức / Video / Bài viết / Quán tabs).
class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.query,
    required this.what,
    required this.children,
    this.dividerIndent = 16,
  });

  final String query;

  /// "công thức", "video"… for the empty message.
  final String what;
  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: EmptyStateView(
            icon: Icons.search_off_rounded,
            title: 'Không có $what nào khớp «$query»',
            message: 'Xem các mục khác ở tab Tất cả.',
          ),
        ),
      );
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding:
          EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      itemCount: children.length,
      separatorBuilder: (_, __) => SearchRowDivider(indent: dividerIndent),
      itemBuilder: (_, i) => children[i],
    );
  }
}
