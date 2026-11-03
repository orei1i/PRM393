// test/search/client_search_test.dart
// Search while the BE has no `/search`: real posts, recipes and ingredients on
// the client, restaurants labelled as sample data, nothing silently missing.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/community/data/community_api_service.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/ingredient/data/ingredient_api_service.dart';
import 'package:veganlife_mobile/features/ingredient/data/models/ingredient_model.dart';
import 'package:veganlife_mobile/features/ingredient/presentation/screens/ingredient_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/search/data/client_search_service.dart';
import 'package:veganlife_mobile/features/search/data/mock_search_repository.dart';
import 'package:veganlife_mobile/features/search/data/models/search_models.dart';
import 'package:veganlife_mobile/features/search/data/search_api_service.dart';
import 'package:veganlife_mobile/features/search/domain/entities/search_result.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

PostDto _post(
  String id,
  String title, {
  String body = '',
  String status = 'Published',
  String mediaType = 'Text',
}) =>
    PostDto(
      id: id,
      type: 'discussion',
      author: const AuthorSummary(id: 'u_x', name: 'Thành viên'),
      title: title,
      body: body,
      createdAt: DateTime(2026, 10, 31),
      status: status,
      mediaType: mediaType,
      mediaUrl: mediaType == 'Text' ? null : 'https://cdn.test/$id',
    );

/// A feed of [pages] pages of 2 posts each.
class _Feed implements CommunityApiService {
  _Feed(this.pages, {this.failing = false});

  final List<List<PostDto>> pages;
  final bool failing;
  int calls = 0;

  @override
  Future<FeedPageDto> getFeed({
    PostType? type,
    PostMediaType? mediaType,
    String? cursor,
    int limit = 6,
  }) async {
    calls++;
    if (failing) {
      throw const ApiException(message: 'Mất kết nối.', statusCode: 503);
    }
    final page = cursor == null ? 0 : int.parse(cursor);
    return FeedPageDto(
      items: pages[page],
      nextCursor: page + 1 < pages.length ? '${page + 1}' : null,
    );
  }

  @override
  Future<PostDto> getPost(String id) async =>
      pages.expand((p) => p).firstWhere((p) => p.id == id);

  @override
  Future<CommentPageDto> getComments(String postId,
          {String? cursor, int limit = 10}) async =>
      const CommentPageDto(items: []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Ingredients implements IngredientApiService {
  final queries = <String>[];

  @override
  Future<List<IngredientSummaryDto>> search(String query) async {
    queries.add(query);
    return foldedHas(query)
        ? const [
            IngredientSummaryDto(
                id: 'ing_dau_hu', name: 'Đậu hũ', caloriesPer100g: 76)
          ]
        : const [];
  }

  static bool foldedHas(String query) =>
      'đậu hũ dau hu'.contains(query.toLowerCase());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

MockRestaurantRepository _restaurants() => MockRestaurantRepository(
      isSignedIn: () => true,
      currentUserId: () => 'u_me',
      currentUserName: () => 'Minh Anh',
    );

const _bunRieu = RecipeSummaryDto(
    id: '6ae595c7aaaaaaaaaaaaaaaa', name: 'Bún riêu chay', caloriesCache: 520);
const _pho = RecipeSummaryDto(id: '6ae595c7bbbbbbbbbbbbbbbb', name: 'Phở nấm');

ClientSearchService _service({
  CommunityApiService? community,
  RecipeSearchScope scope = RecipeSearchScope.full,
  List<RecipeSummaryDto> recipes = const [_bunRieu, _pho],
  _Ingredients? ingredients,
  DateTime Function()? now,
}) =>
    ClientSearchService(
      community: community ??
          _Feed([
            [
              _post('p1', 'Mình nấu bún riêu lần đầu'),
              _post('p2', 'Hỏi về B12', body: 'Có nên uống bổ sung không?'),
            ],
            [
              _post('p3', 'Video bún riêu', mediaType: 'Video'),
              _post('p4', 'Bún riêu đang chờ', status: 'Pending'),
            ],
          ]),
      restaurants: _restaurants(),
      ingredients: ingredients ?? _Ingredients(),
      recipes: () async => (recipes, scope),
      now: now,
    );

Future<void> _pump(WidgetTester tester, SearchApiService service,
    {bool signedIn = true,
    Size size = const Size(411, 1200),
    String? query,
    List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      'vl.access_token': 'token',
      'vl.user_id': 'u_me',
      'vl.display_name': 'Minh Anh',
    },
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      searchApiProvider.overrideWithValue(service),
      ...overrides,
    ],
    child: MaterialApp(home: SearchScreen(initialQuery: query)),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(() {
    MockRestaurantRepository.reset();
    BackendModules.debugOverride({...BackendModules.supportedByBackend}
      ..removeAll({BackendModule.search, BackendModule.restaurants}));
  });
  tearDown(() => BackendModules.debugOverride(null));

  group('ClientSearchService', () {
    test('accents and partial words: posts, videos and recipes apart',
        () async {
      for (final q in ['bun rieu', 'BÚN RIÊU', 'bun rie']) {
        final r = (await _service().search(q)).toEntity();
        expect(r.posts.map((p) => p.id), ['p1'], reason: q);
        expect(r.videos.map((p) => p.id), ['p3'], reason: q);
        expect(r.recipes.map((x) => x.name), ['Bún riêu chay'], reason: q);
      }
    });

    test('never a post that is not Published', () async {
      final r = (await _service().search('dang cho')).toEntity();
      expect(r.posts, isEmpty);
      expect(r.videos, isEmpty);
    });

    test('searches inside the body', () async {
      final r = (await _service().search('bo sung')).toEntity();
      expect(r.posts.map((p) => p.id), ['p2']);
    });

    test('restaurants come from the sample data, by distance rules', () async {
      final r = (await _service().search('bun rieu')).toEntity();
      expect(r.restaurants.map((x) => x.id),
          containsAll(['rs_an_lac', 'rs_hanh_tam']));
    });

    test('at most 5 pages of the feed, and it says so', () async {
      final feed = _Feed(List.generate(
          8,
          (p) => [
                _post('p${p}a', 'Bài trang $p'),
                _post('p${p}b', 'Bài khác $p'),
              ]));
      final r = (await _service(community: feed).search('bai')).toEntity();
      expect(feed.calls, ClientSearchService.maxFeedPages);
      expect(r.postsTruncated, isTrue);

      final small = (await _service().search('bun')).toEntity();
      expect(small.postsTruncated, isFalse);
    });

    test('a failed feed is an error; failed ingredients are not', () async {
      await expectLater(
          _service(community: _Feed(const [], failing: true)).search('bun'),
          throwsA(isA<ApiException>()));
      final failing = ClientSearchService(
        community: _Feed([
          [_post('p1', 'Bún riêu')]
        ]),
        restaurants: _restaurants(),
        ingredients: _FailingIngredients(),
        recipes: () async =>
            (const <RecipeSummaryDto>[], RecipeSearchScope.full),
      );
      expect((await failing.search('bun')).toEntity().posts.map((p) => p.id),
          ['p1']);
    });

    test('the scope of the recipes comes back with the result', () async {
      for (final scope in RecipeSearchScope.values) {
        final r =
            (await _service(scope: scope, recipes: const []).search('bun'))
                .toEntity();
        expect(r.recipeScope, scope);
      }
    });

    test('typing reuses the last walk of the feed; a search does not',
        () async {
      var clock = DateTime(2026, 11, 1, 8);
      final feed = _Feed([
        [_post('p1', 'Bún riêu')]
      ]);
      final service = _service(community: feed, now: () => clock);
      await service.suggest('bun');
      await service.suggest('bun r');
      expect(feed.calls, 1);
      await service.search('bun');
      expect(feed.calls, 2);
      clock = clock.add(ClientSearchService.postCacheFor);
      await service.suggest('bun');
      expect(feed.calls, 3);
    });

    test(
        'suggest: recipes, posts, ingredients, sample places; no made-up queries',
        () async {
      final rows = await _service().suggest('bun');
      expect(rows.where((r) => r.kind == 'query'), isEmpty);
      expect(rows.first.kind, 'recipe');
      expect(rows.first.id, _bunRieu.id);
      expect(rows.map((r) => r.kind), contains('post'));
      final dish = await _service().suggest('dau');
      expect(dish.where((r) => r.kind == 'ingredient').map((r) => r.text),
          ['Đậu hũ']);
      final place = (await _service().suggest('an lac'))
          .firstWhere((r) => r.kind == 'restaurant');
      expect(place.subtitle, contains('dữ liệu mẫu'));
    });

    test('discover: nothing sample; categories only when they find something',
        () async {
      final page = (await _service(
              recipes: const [RecipeSummaryDto(id: 'r1', name: 'Bún chả chay')],
              community: _Feed([
                [_post('p1', 'Sữa hạt tại nhà')]
              ])).discover())
          .toEntity();
      expect(page.trending, isEmpty);
      expect(page.seasonal, isEmpty);
      expect(page.popularRecipes, isEmpty);
      expect(page.categories.map((c) => c.label),
          unorderedEquals(['Bún & phở', 'Đồ uống']));
      expect(page.nearbyRestaurants, hasLength(3));
    });

    test('the build decides who searches', () async {
      final c = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(await _emptyPrefs()),
      ]);
      addTearDown(c.dispose);
      BackendModules.debugOverride(const {});
      expect(c.read(searchApiProvider), isA<MockSearchRepository>());
      c.invalidate(searchApiProvider);
      BackendModules.debugOverride({BackendModule.community});
      expect(c.read(searchApiProvider), isA<ClientSearchService>());
      c.invalidate(searchApiProvider);
      BackendModules.debugOverride({BackendModule.search});
      expect(c.read(searchApiProvider), isA<RemoteSearchApiService>());
    });
  });

  group('screen', () {
    testWidgets('idle: no sample trending; the banner only on the restaurants',
        (tester) async {
      await _pump(tester, _service());
      await _wait(tester);
      expect(find.text('Xu hướng tìm kiếm'), findsNothing);
      expect(find.text('Món theo mùa'), findsNothing);
      expect(find.text('Công thức được yêu thích'), findsNothing);
      expect(find.text('Quán chay gần bạn'), findsOneWidget);
      expect(find.byType(DemoDataBanner), findsOneWidget);
      final banner = tester.getTopLeft(find.byType(DemoDataBanner)).dy;
      expect(banner,
          greaterThan(tester.getTopLeft(find.text('Quán chay gần bạn')).dy));
      await _dispose(tester);
    });

    testWidgets('a fully mock build keeps its page and has no banner',
        (tester) async {
      BackendModules.debugOverride(const {});
      await _pump(
        tester,
        MockSearchRepository(
          community: _Feed(const [[]]),
          restaurants: _restaurants(),
        ),
      );
      await _wait(tester);
      expect(find.text('Xu hướng tìm kiếm'), findsOneWidget);
      expect(find.byType(DemoDataBanner), findsNothing);
      await _dispose(tester);
    });

    testWidgets('results: real rows without a banner, the banner on Quán',
        (tester) async {
      await _pump(tester, _service(),
          query: 'dau hu', size: const Size(411, 1600));
      await _wait(tester);
      expect(find.widgetWithText(Tab, 'Nguyên liệu'), findsOneWidget);
      expect(find.text('Đậu hũ'), findsOneWidget);
      expect(find.text('76 kcal/100 g'), findsOneWidget);

      await tester.tap(find.text('Đậu hũ'));
      await _wait(tester, 800);
      expect(find.byType(IngredientDetailScreen), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('no place matches: nothing on the screen is sample data',
        (tester) async {
      await _pump(tester, _service(), query: 'b12');
      await _wait(tester);
      expect(find.text('Hỏi về B12'), findsOneWidget);
      expect(find.byType(DemoDataBanner), findsNothing);
      await _dispose(tester);
    });

    testWidgets('a place in the results carries the banner', (tester) async {
      await _pump(tester, _service(),
          query: 'an lac', size: const Size(411, 1600));
      await _wait(tester, 2000);
      expect(find.text('Quán Chay An Lạc'), findsOneWidget);
      expect(find.byType(DemoDataBanner), findsOneWidget);
      final banner = tester.getTopLeft(find.byType(DemoDataBanner)).dy;
      expect(banner,
          lessThan(tester.getTopLeft(find.text('Quán Chay An Lạc')).dy));
      await _dispose(tester);
    });

    testWidgets('a result opens the real post', (tester) async {
      await _pump(tester, _service(), query: 'bo sung');
      await _wait(tester);
      await tester.tap(find.text('Hỏi về B12'));
      await _wait(tester, 800);
      expect(find.byType(PostDetailScreen), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a guest is told why there are no recipes, and can sign in',
        (tester) async {
      await _pump(tester,
          _service(scope: RecipeSearchScope.signedOut, recipes: const []),
          query: 'bun rieu', signedIn: false);
      await _wait(tester);
      expect(
          find.textContaining('Khách chưa xem được công thức'), findsOneWidget);
      expect(find.text('Đăng nhập'), findsOneWidget);
      await tester.tap(find.widgetWithText(Tab, 'Công thức'));
      await _wait(tester, 800);
      expect(
          find.textContaining('Khách chưa xem được công thức'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a guest with no hits at all still gets the reason',
        (tester) async {
      await _pump(tester,
          _service(scope: RecipeSearchScope.signedOut, recipes: const []),
          query: 'zzzzz', signedIn: false);
      await _wait(tester);
      expect(find.text('Không tìm thấy «zzzzz»'), findsOneWidget);
      expect(
          find.textContaining('Khách chưa xem được công thức'), findsOneWidget);
      expect(find.text('Đăng nhập'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a member with no plan is told the catalogue is small',
        (tester) async {
      await _pump(tester, _service(scope: RecipeSearchScope.fridgeOnly),
          query: 'bun rieu');
      await _wait(tester);
      expect(
          find.textContaining('Bạn chưa có thực đơn tuần này'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a scanned feed says how far it went', (tester) async {
      final feed = _Feed(List.generate(
          8,
          (p) => [
                _post('p${p}a', 'Bún riêu số $p'),
                _post('p${p}b', 'Bài khác $p'),
              ]));
      await _pump(tester, _service(community: feed), query: 'bun rieu');
      await _wait(tester);
      expect(find.text('Chỉ tìm trong 250 bài mới nhất của bảng tin.'),
          findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('no overflow at 360 dp with font scale 1.3', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          searchApiProvider
              .overrideWithValue(_service(scope: RecipeSearchScope.signedOut)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: const SearchScreen(initialQuery: 'bun rieu'),
            ),
          ),
        ),
      ));
      await _wait(tester);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });
}

class _FailingIngredients implements IngredientApiService {
  @override
  Future<List<IngredientSummaryDto>> search(String query) async =>
      throw const ApiException(message: 'Lỗi', statusCode: 503);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}
