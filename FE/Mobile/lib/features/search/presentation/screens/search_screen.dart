// lib/features/search/presentation/screens/search_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/screens/post_detail_screen.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../../restaurant/domain/entities/restaurant.dart';
import '../../../restaurant/presentation/screens/restaurant_detail_screen.dart';
import '../../../restaurant/presentation/screens/restaurant_nearby_screen.dart';
import '../../../restaurant/presentation/widgets/restaurant_tile.dart';
import '../../../video/presentation/screens/video_detail_screen.dart';
import '../../domain/entities/search_result.dart';
import '../controllers/global_search_controller.dart';
import '../widgets/search_tiles.dart';

/// Global search (posts, videos, recipes, restaurants). Guests allowed.
///
/// Idle: recent searches + suggestions. Results: tabs Tất cả · Công thức ·
/// Video · Bài viết · Quán; when a recipe matches, "Gợi ý cho «món»" leads
/// with related videos/posts and nearby restaurants serving the dish.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Pre-filled query, e.g. a recipe name from "Tìm video & quán liên quan".
  final String? initialQuery;

  static Route<void> route({String? initialQuery}) => MaterialPageRoute<void>(
        builder: (_) => SearchScreen(initialQuery: initialQuery),
      );

  /// Shown while idle.
  static const suggestions = ['bún riêu', 'đậu hũ', 'sữa hạt', 'phở chay'];

  static const tabLabels = ['Tất cả', 'Công thức', 'Video', 'Bài viết', 'Quán'];

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final _field =
      TextEditingController(text: widget.initialQuery?.trim() ?? '');
  late final TabController _tabs;

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
    }
    _search.submit(q);
  }

  /// A recent or suggested query chip.
  void _pick(String query) {
    _field
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    FocusScope.of(context).unfocus();
    _submit(query);
    setState(() {});
  }

  void _clear() {
    _field.clear();
    _search.clear();
    setState(() {});
  }

  /// Opening a result counts as a search worth remembering.
  void _remember() {
    final q = ref.read(globalSearchProvider).query;
    if (q.isNotEmpty) ref.read(recentSearchesProvider.notifier).add(q);
  }

  void _openPost(Post post) {
    _remember();
    final videoId = post.videoId;
    Navigator.of(context).push(videoId != null && post.type == PostType.video
        ? VideoDetailScreen.route(videoId, post: post)
        : PostDetailScreen.route(post));
  }

  void _openRecipe(RecipeSummary recipe) {
    _remember();
    Navigator.of(context)
        .push(RecipeDetailScreen.route(recipe.id, name: recipe.name));
  }

  void _openRestaurant(Restaurant restaurant) {
    _remember();
    Navigator.of(context).push(
        RestaurantDetailScreen.route(restaurant.id, name: restaurant.name));
  }

  void _openNearby({String? food}) {
    if (food != null) _remember();
    Navigator.of(context)
        .push(RestaurantNearbyScreen.route(initialQuery: food));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalSearchProvider);
    final result = state.result;
    final showTabs = !state.isIdle &&
        state.error == null &&
        result != null &&
        !result.isEmpty;
    final busy = state.loading && result != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
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
      body: _body(state),
    );
  }

  Widget _body(SearchState state) {
    final result = state.result;
    if (state.isIdle) {
      return _IdleView(onPick: _pick, onOpenNearby: () => _openNearby());
    }
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
    return TabBarView(
      controller: _tabs,
      children: [
        _AllTab(
          result: result,
          onMore: (tab) => _tabs.animateTo(tab),
          onPost: _openPost,
          onRecipe: _openRecipe,
          onRestaurant: _openRestaurant,
          onAllRestaurants: (food) => _openNearby(food: food),
        ),
        _ResultList(
          query: result.query,
          what: 'công thức',
          children: [
            for (final r in result.recipes)
              SearchRecipeTile(recipe: r, onTap: () => _openRecipe(r)),
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

/// Recent searches ("Xoá lịch sử"), suggestion chips and a shortcut to the
/// nearby restaurants.
class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onPick, required this.onOpenNearby});

  final ValueChanged<String> onPick;
  final VoidCallback onOpenNearby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (recent.isNotEmpty) ...[
          _HeaderRow(
            title: Text('Tìm gần đây', style: context.textStyles.titleSmall),
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
          const SizedBox(height: 24),
        ],
        Text('Gợi ý tìm kiếm', style: context.textStyles.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in SearchScreen.suggestions)
              ActionChip(
                avatar: Icon(Icons.trending_up_rounded,
                    size: 18, color: context.colors.primary),
                label: Text(q),
                onPressed: () => onPick(q),
              ),
          ],
        ),
        const SizedBox(height: 24),
        VLCard(
          onTap: onOpenNearby,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.storefront_outlined,
                    color: context.colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quán chay gần bạn',
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Xem quán gần nhất, quán đã chứng nhận và đánh giá.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.vl.muted),
            ],
          ),
        ),
      ],
    );
  }
}

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
