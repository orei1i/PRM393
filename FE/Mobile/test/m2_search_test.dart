// test/m2_search_test.dart
// The mock repositories wait like a network (0.4–1.1 s per call).
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/text_search.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/data/location_service.dart';
import 'package:veganlife_mobile/features/restaurant/data/mock_restaurant_repository.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/search/data/mock_search_repository.dart';
import 'package:veganlife_mobile/features/search/data/models/search_models.dart';
import 'package:veganlife_mobile/features/search/data/search_api_service.dart';
import 'package:veganlife_mobile/features/search/domain/entities/search_result.dart';
import 'package:veganlife_mobile/features/search/presentation/controllers/global_search_controller.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';

const _q1 = MockLocationService.point;

MockSearchRepository _search({bool signedIn = false}) => MockSearchRepository(
      community: MockCommunityRepository(
        currentUserName: () => 'Minh Anh',
        isSignedIn: () => signedIn,
        currentUserId: () => 'u_me',
      ),
      restaurants: MockRestaurantRepository(
        isSignedIn: () => signedIn,
        currentUserId: () => 'u_me',
        currentUserName: () => 'Minh Anh',
      ),
    );

Map<String, dynamic> _postJson(String id,
        {String type = 'recipe',
        String title = 'Bài',
        String status = 'Published',
        int hoursAgo = 1}) =>
    {
      'id': id,
      'type': type,
      'author': {'id': 'u_x', 'fullName': 'X'},
      'title': title,
      'body': '',
      'status': status,
      'createdAt': DateTime.now()
          .subtract(Duration(hours: hoursAgo))
          .toUtc()
          .toIso8601String(),
      if (type == 'video')
        'video': {'id': 'vid_$id', 'durationSeconds': 60, 'aiStatus': 'ready'},
    };

/// Records queries; each call waits for the test to complete it.
class _FakeSearchApi implements SearchApiService {
  final calls = <String>[];
  final pending = <String, Completer<SearchResultDto>>{};

  @override
  Future<SearchResultDto> search(String query,
      {SearchType type = SearchType.all, GeoPoint? near, int limit = 10}) {
    calls.add(query);
    return (pending[query] = Completer<SearchResultDto>()).future;
  }

  void answer(String query) => pending[query]!.complete(SearchResultDto(
      query: query, recipes: [RecipeSummaryDto(id: 'r_$query', name: query)]));
}

Future<SharedPreferences> _prefs(
    {bool signedIn = false, List<String>? recent}) async {
  SharedPreferences.setMockInitialValues({
    if (signedIn) ...{
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh'
    },
    if (recent != null) 'vl.recent_searches': recent,
  });
  return SharedPreferences.getInstance();
}

Future<SharedPreferences> _pumpApp(WidgetTester tester, Widget home,
    {bool signedIn = false,
    List<String>? recent,
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(signedIn: signedIn, recent: recent);
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: home,
        ),
      ),
    ),
  ));
  return prefs;
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(MockRestaurantRepository.reset);

  group('matching', () {
    test('folded matching ignores case and accents', () {
      expect(matchesQuery('Bún riêu chay cà chua', 'bun rieu'), isTrue);
      expect(matchesQuery('Bún riêu chay', 'BÚN RIÊU'), isTrue);
      expect(matchesQuery('Bún riêu chay', 'bun bo'), isFalse);
    });

    test('recipe catalogue has every planner dish once', () {
      final all = MockSearchRepository.recipeCatalogue();
      final ids = all.map((r) => r.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, containsAll(['l5', 'menu_2', 'b1', 'ls3', 'pd_nam_rom_kho']));
      expect(all.firstWhere((r) => r.id == 'b1').caloriesCache, 420);
    });
  });

  group('MockSearchRepository', () {
    test('"bun rieu" (guest): recipe, post, suggestion block, restaurants',
        () async {
      final r = (await _search().search('bun rieu', near: _q1)).toEntity();
      expect(r.query, 'bun rieu');
      expect(r.recipes.first.id, 'l5');
      expect(r.recipes.first.name, 'Bún riêu chay');
      expect(r.posts.map((p) => p.id), contains('p_bun_rieu'));
      expect(r.videos, isEmpty);
      expect(
          r.restaurants.map((x) => x.id).toSet(), {'rs_an_lac', 'rs_hanh_tam'});
      expect(r.restaurants.first.distanceKm, isNotNull);

      final s = r.suggestion!;
      expect(s.recipe.name, 'Bún riêu chay');
      expect(s.relatedPosts.map((p) => p.id), contains('p_bun_rieu'));
      expect(s.restaurants.map((x) => x.id), ['rs_an_lac', 'rs_hanh_tam']);
    });

    test('groups videos apart from posts', () async {
      final r = (await _search().search('sữa', near: _q1)).toEntity();
      expect(r.videos.map((p) => p.id), contains('p_video_sua_hat'));
      expect(r.posts.map((p) => p.id), contains('p_sua_chua_dua'));
      expect(r.videos.every((p) => p.videoId != null), isTrue);
      expect(r.posts.any((p) => p.videoId != null), isFalse);
      expect(r.restaurants.map((x) => x.id), contains('rs_lanh'));
      expect(r.recipes.map((x) => x.name),
          contains('Sữa đậu nành & bánh bao chay'));
    });

    test('nothing for xyzxyz; 1 letter; #fail → 503', () async {
      final repo = _search();
      expect(
          (await repo.search('xyzxyz', near: _q1)).toEntity().isEmpty, isTrue);
      expect((await repo.search('b')).toEntity().isEmpty, isTrue);
      await expectLater(repo.search('bún #fail'),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 503)));
    });

    test('pending and rejected posts never appear, even to their author',
        () async {
      final repo = _search(signedIn: true);
      final pending = (await repo.search('cần tây')).toEntity();
      expect([...pending.posts, ...pending.videos], isEmpty);
      final rejected = (await repo.search('detox')).toEntity();
      expect([...rejected.posts, ...rejected.videos], isEmpty);

      final parsed = SearchResultDto.fromJson({
        'query': 'x',
        'posts': [
          _postJson('p_ok'),
          _postJson('p_wait', status: 'Pending'),
          _postJson('p_no', status: 'Rejected'),
        ],
        'suggestion': {
          'recipe': {'id': 'l5', 'name': 'Bún riêu chay'},
          'relatedPosts': [_postJson('p_wait2', status: 'Pending')],
        },
      }).toEntity();
      expect(parsed.posts.map((p) => p.id), ['p_ok']);
      expect(parsed.suggestion!.relatedPosts, isEmpty);
    });

    test('related posts: videos first, at most 6', () {
      final posts = [
        for (var i = 0; i < 8; i++)
          PostDto.fromJson(_postJson('p_$i',
              title: 'Bún riêu chay nhà làm $i', hoursAgo: i)),
        PostDto.fromJson(_postJson('p_vid',
            type: 'video', title: 'Video bún riêu 10 phút', hoursAgo: 99)),
        PostDto.fromJson(_postJson('p_other', title: 'Phở chay')),
      ];
      final related = MockSearchRepository.relatedPosts(posts, 'Bún riêu chay');
      expect(related, hasLength(MockSearchRepository.maxRelatedPosts));
      expect(related.first.id, 'p_vid');
      expect(related.map((p) => p.id), isNot(contains('p_other')));
      expect(related[1].id, 'p_0', reason: 'then newest');
    });

    test('DTO parsing: full shape, recipe summary aliases', () {
      final r = SearchResultDto.fromJson({
        'query': 'bún riêu',
        'videos': [_postJson('p_v', type: 'video')],
        'recipes': [
          {'id': 5, 'name': 'Bún riêu chay', 'caloriesCache': 520},
          {'id': 'b1', 'name': 'Yến mạch', 'calories': 420, 'isVegan': true},
        ],
        'restaurants': [
          {'id': 21, 'name': 'Quán', 'address': 'A', 'latitude': null}
        ],
        'suggestion': null,
      }).toEntity();
      expect(r.videos.single.videoId, 'vid_p_v');
      expect(r.recipes.first.id, '5');
      expect(r.recipes.first.calories, 520);
      expect(r.recipes.last.calories, 420);
      expect(r.restaurants.single.location, isNull);
      expect(r.suggestion, isNull);
      expect(r.isEmpty, isFalse);
    });
  });

  group('GlobalSearchController', () {
    late _FakeSearchApi api;
    late ProviderContainer container;

    setUp(() async {
      api = _FakeSearchApi();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        searchApiProvider.overrideWithValue(api),
      ]);
      container.listen(globalSearchProvider, (_, __) {}); // keep alive
    });
    tearDown(() => container.dispose());

    GlobalSearchController notifier() =>
        container.read(globalSearchProvider.notifier);

    test('under 2 characters stays idle and sends nothing', () async {
      notifier().onQueryChanged('b');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(api.calls, isEmpty);
      expect(container.read(globalSearchProvider).isIdle, isTrue);
    });

    test('debounced: only the last keystroke is searched', () async {
      notifier()
        ..onQueryChanged('bu')
        ..onQueryChanged('bun')
        ..onQueryChanged('bun ');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(api.calls, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(api.calls, ['bun']);
      expect(container.read(globalSearchProvider).loading, isTrue);
      api.answer('bun');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(globalSearchProvider).result?.query, 'bun');
    });

    test('a stale response is dropped', () async {
      final first = notifier().submit('bun');
      await Future<void>.delayed(Duration.zero);
      final second = notifier().submit('bun rieu');
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['bun', 'bun rieu']);
      api.answer('bun rieu');
      await second;
      api.answer('bun');
      await first;
      final state = container.read(globalSearchProvider);
      expect(state.query, 'bun rieu');
      expect(state.result?.query, 'bun rieu');
      expect(state.result?.recipes.single.id, 'r_bun rieu');
    });

    test('errors keep the query for "Thử lại"; clear goes idle', () async {
      final run = notifier().submit('bun');
      await Future<void>.delayed(Duration.zero);
      api.pending['bun']!
          .completeError(const ApiException(message: 'Bận', statusCode: 503));
      await run;
      var state = container.read(globalSearchProvider);
      expect(state.error, isA<ApiException>());
      expect(state.query, 'bun');

      notifier().retry();
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['bun', 'bun']);
      notifier().clear();
      state = container.read(globalSearchProvider);
      expect(state.isIdle, isTrue);
      api.answer('bun');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(globalSearchProvider).isIdle, isTrue,
          reason: 'cleared, so the late answer is dropped');
    });
  });

  group('recent searches', () {
    test('newest first, folded duplicates merged, max 8, survive a restart',
        () async {
      final prefs = await _prefs();
      var container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      final recent = container.read(recentSearchesProvider.notifier);
      await recent.add('Bún riêu');
      await recent.add('đậu hũ');
      await recent.add('bun rieu ');
      await recent.add('a');
      expect(container.read(recentSearchesProvider), ['bun rieu', 'đậu hũ']);
      for (var i = 0; i < 10; i++) {
        await recent.add('món $i');
      }
      expect(container.read(recentSearchesProvider), hasLength(8));
      expect(container.read(recentSearchesProvider).first, 'món 9');
      container.dispose();

      // A new app session reads the same preferences.
      container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      expect(container.read(recentSearchesProvider), hasLength(8));
      expect(prefs.getStringList(RecentSearchesController.prefsKey),
          container.read(recentSearchesProvider));
      await container.read(recentSearchesProvider.notifier).remove('món 9');
      expect(container.read(recentSearchesProvider).first, 'món 8');
      await container.read(recentSearchesProvider.notifier).clear();
      expect(container.read(recentSearchesProvider), isEmpty);
      expect(prefs.containsKey(RecentSearchesController.prefsKey), isFalse);
      container.dispose();
    });
  });

  group('SearchScreen', () {
    testWidgets('idle: recent searches, suggestions, "Xoá lịch sử"',
        (tester) async {
      await _pumpApp(tester, const SearchScreen(),
          recent: ['phở chay', 'bánh xèo']);
      expect(
          find.text('Tìm công thức, video, bài viết, quán…'), findsOneWidget);
      expect(find.text('Tìm gần đây'), findsOneWidget);
      expect(find.text('bánh xèo'), findsOneWidget);
      expect(find.text('phở chay'), findsNWidgets(2), reason: 'recent + idea');
      for (final idea in SearchScreen.suggestions) {
        expect(find.text(idea), findsWidgets);
      }
      expect(find.text('Quán chay gần bạn'), findsOneWidget);

      await tester.tap(find.text('Xoá lịch sử'));
      await tester.pump();
      expect(find.text('Tìm gần đây'), findsNothing);
      expect(find.text('bánh xèo'), findsNothing);
      expect(find.text('Gợi ý tìm kiếm'), findsOneWidget);
    });

    testWidgets('empty state; one letter stays idle', (tester) async {
      await _pumpApp(tester, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'x');
      await _wait(tester, 1000);
      expect(find.text('Gợi ý tìm kiếm'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'xyzxyz');
      await _wait(tester, 2500);
      expect(find.text('Không tìm thấy «xyzxyz»'), findsOneWidget);
      expect(find.text('Thử từ khoá ngắn hơn hoặc không dấu'), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('guest "bun rieu": 5 tabs, suggestion block, opens results',
        (tester) async {
      final prefs = await _pumpApp(
          tester, const SearchScreen(initialQuery: 'bun rieu'),
          size: const Size(411, 2400));
      await _wait(tester, 3000);
      for (final label in [
        'Tất cả',
        'Công thức',
        'Video',
        'Bài viết',
        'Quán'
      ]) {
        expect(find.widgetWithText(Tab, label), findsOneWidget, reason: label);
      }
      expect(find.text('Gợi ý cho «Bún riêu chay»'), findsOneWidget);
      expect(find.text('Video & bài viết liên quan'), findsOneWidget);
      expect(find.text('Quán gợi ý'), findsOneWidget);
      expect(find.text('Xem tất cả quán'), findsOneWidget);
      expect(find.text('Bún Riêu Chay Hạnh Tâm'), findsWidgets);
      expect(prefs.getStringList('vl.recent_searches'), ['bun rieu']);

      // Recipe → recipe detail.
      await tester.tap(find.text('Bún riêu chay').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RecipeDetailScreen), findsOneWidget);
      await _wait(tester);
      await tester.pageBack();
      await _wait(tester, 500);

      // Restaurant tab → restaurant detail.
      await tester.tap(find.widgetWithText(Tab, 'Quán'));
      await _wait(tester, 500);
      await tester.tap(find.text('Quán Chay An Lạc').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      await _wait(tester);
      await tester.pageBack();
      await _wait(tester, 500);

      // Post tab → post detail.
      await tester.tap(find.widgetWithText(Tab, 'Bài viết'));
      await _wait(tester, 500);
      await tester.tap(find.textContaining('Bún riêu chay cà chua').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PostDetailScreen), findsOneWidget);
      await _wait(tester, 3000);
    });

    testWidgets('large text on a small phone: results without overflow',
        (tester) async {
      await _pumpApp(tester, const SearchScreen(initialQuery: 'bun rieu'),
          size: const Size(360, 780), textScale: 2);
      await _wait(tester, 3000);
      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
    });
  });
}
