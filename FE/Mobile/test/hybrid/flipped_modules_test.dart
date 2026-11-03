// test/hybrid/flipped_modules_test.dart
// What the screens do once chatbot, search, restaurants, ads and recipeSocial
// talk to the BE: the sample banners go, the real account is recognised, and a
// server with no AI gets a clear message instead of an answer.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/demo_data_banner.dart';
import 'package:veganlife_mobile/features/chatbot/data/chat_api_service.dart';
import 'package:veganlife_mobile/features/chatbot/data/models/chat_models.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/screens/chat_screen.dart';
import 'package:veganlife_mobile/features/recipe/data/mock_recipe_community_repository.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_detail_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_review_model.dart';
import 'package:veganlife_mobile/features/recipe/data/models/recipe_variant_model.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_community_api_service.dart';
import 'package:veganlife_mobile/features/recipe/domain/entities/recipe_review.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/data/models/restaurant_model.dart';
import 'package:veganlife_mobile/features/restaurant/data/restaurant_api_service.dart';
import 'package:veganlife_mobile/features/restaurant/domain/geo.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/location_picker_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';

const _me = '6ae5962396695f5c139fa9b0';
const _recipeId = '6ae595c796695f5c139fa99b';
const _placeId = '6ae595c796695f5c139fa9aa';

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(411, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: 'test-token',
    'vl.user_id': _me,
    'vl.display_name': 'Thành viên thật',
    'vl.role': 'User',
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides,
    ],
    child: MaterialApp(home: home),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

class _RefusingChat implements ChatApiService {
  _RefusingChat(this.error);

  final ApiException error;
  var calls = 0;

  @override
  Future<TrialStatusDto> getGuestTrialStatus() async =>
      const TrialStatusDto(limit: 3, used: 0);

  @override
  Stream<ChatStreamEvent> streamReply({
    required String sessionId,
    required ChatRequestDto request,
    CancelToken? cancelToken,
  }) {
    calls++;
    return Stream.error(error);
  }
}

class _Recipes implements RecipeApiService {
  @override
  Future<RecipeDetailDto> getRecipe(String id) async {
    if (id == 'snapshot') {
      return RecipeDetailDto.fromJson(
          const {'id': 'snapshot', 'name': 'Món gõ tay', 'isSnapshot': true});
    }
    return recipeFromBackend(const {
      'id': _recipeId,
      'name': 'Bún riêu chay đậu hũ cà chua',
      'calories': 430,
      'allergens': ['soy'],
      'prepMinutes': 25,
      'ingredients': ['Bún tươi', 'Đậu hũ', 'Cà chua'],
      'instructions': ['Sơ chế nguyên liệu sạch sẽ.'],
      'averageRating': 4.5,
      'ratingCount': 2,
    });
  }
}

class _Reviews implements RecipeCommunityApiService {
  final asked = <String>[];

  @override
  Future<RecipeReviewsPageDto> getReviews(String recipeId,
      {String? cursor, int limit = recipeReviewsPageSize}) async {
    asked.add(recipeId);
    return RecipeReviewsPageDto.fromJson({
      'recipeId': recipeId,
      'averageRating': 4.5,
      'ratingCount': 2,
      'distribution': {'5': 1, '4': 1},
      'myReview': null,
      'items': [
        {
          'id': 'rv_1',
          'rating': 5,
          'content': 'Một đánh giá thật từ máy chủ.',
          'author': {'id': 'u1', 'fullName': 'Người khác'},
          'createdAt': '2026-11-01T00:00:00Z',
        },
      ],
    });
  }

  @override
  Future<RecipeNoteDto?> getMyNote(String recipeId) async => null;

  @override
  Future<RecipeNoteDto?> saveMyNote(String recipeId, String content) async =>
      null;

  @override
  Future<void> deleteMyNote(String recipeId) async {}

  @override
  Future<RatingTotalsDto> deleteMyReview(String recipeId) async =>
      const RatingTotalsDto(ratingCount: 0);

  @override
  Future<ReviewWriteResultDto> upsertMyReview(
          String recipeId, UpsertReviewRequestDto request) =>
      throw UnimplementedError();

  @override
  Future<RecipeDetailDto> createVariant(
          String recipeId, CreateVariantRequestDto request) =>
      throw UnimplementedError();
}

class _Places implements RestaurantApiService {
  @override
  Future<RestaurantDto> getRestaurant(String id, {GeoPoint? near}) async =>
      const RestaurantDto(
          id: _placeId,
          name: 'Quán thật',
          address: '12 Lê Lợi, Q.1, TP.HCM',
          reviewCount: 1,
          averageRating: 4);

  @override
  Future<List<ReviewDto>> getReviews(String restaurantId) async => [
        ReviewDto(
          id: 'r1',
          restaurantId: _placeId,
          userId: _me,
          userName: 'Thành viên thật',
          rating: 4,
          comment: 'Đánh giá của chính tôi.',
          createdAt: DateTime(2026, 11),
        ),
      ];

  @override
  Future<List<RestaurantMediaDto>> getMedia(String restaurantId) async =>
      const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  test('a banner only where the data is still a sample', () {
    for (final m in [
      BackendModule.chatbot,
      BackendModule.search,
      BackendModule.restaurants,
      BackendModule.ads,
      BackendModule.recipeSocial,
    ]) {
      expect(DemoDataBanner.visibleFor(m), isFalse, reason: m.name);
    }
    expect(DemoDataBanner.visibleFor(BackendModule.geocoding), isTrue);
    expect(DemoDataBanner.visibleFor(BackendModule.video), isTrue);
  });

  group('chat on a server with no AI', () {
    for (final (code, text) in const [
      ('ai_unavailable', 'Trợ lý AI chưa được cấu hình trên máy chủ.'),
      ('ai_disabled', 'Chatbot đang tạm tắt.'),
    ]) {
      testWidgets('$code: the reason and "Thử lại", no answer', (tester) async {
        final chat = _RefusingChat(
            ApiException(message: text, statusCode: 503, code: code));
        await _pump(tester, const ChatScreen(),
            overrides: [chatApiProvider.overrideWithValue(chat)]);
        expect(find.byType(DemoDataBanner), findsNothing);

        await tester.enterText(
            find.byType(TextField), 'Đậu lăng có đạm không?');
        await tester.pump();
        await tester.tap(find.byTooltip('Gửi'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }

        expect(chat.calls, 1);
        expect(find.text('Đậu lăng có đạm không?'), findsOneWidget,
            reason: 'the question stays');
        expect(find.text(text), findsOneWidget);
        expect(find.text('Thử lại'), findsOneWidget);
        await tester.tap(find.text('Thử lại'));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(chat.calls, 2);
        expect(find.text(text), findsOneWidget);
        await _drain(tester);
      });
    }
  });

  group('recipe page', () {
    testWidgets('a BE recipe has reviews and a note, from the BE, no banner',
        (tester) async {
      final reviews = _Reviews();
      await _pump(tester, const RecipeDetailScreen(recipeId: _recipeId),
          overrides: [
            recipeApiProvider.overrideWithValue(_Recipes()),
            recipeCommunityApiProvider.overrideWithValue(reviews),
          ]);
      expect(find.byType(DemoDataBanner), findsNothing);
      expect(find.widgetWithText(Tab, 'Đánh giá'), findsOneWidget);
      expect(find.textContaining('2 đánh giá'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Cách làm'));
      await tester.pumpAndSettle();
      expect(find.text('Ghi chú của tôi'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Đánh giá'));
      await tester.pumpAndSettle();
      expect(reviews.asked, contains(_recipeId));
      expect(find.text('Một đánh giá thật từ máy chủ.'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('a dish only known through a plan has neither', (tester) async {
      await _pump(tester, const RecipeDetailScreen(recipeId: 'snapshot'),
          overrides: [
            recipeApiProvider.overrideWithValue(_Recipes()),
            recipeCommunityApiProvider.overrideWithValue(_Reviews()),
          ]);
      expect(find.widgetWithText(Tab, 'Đánh giá'), findsNothing);
      expect(find.textContaining('đánh giá'), findsNothing);
      await _drain(tester);
    });

    testWidgets('a sample recipe stays labelled as one', (tester) async {
      await _pump(tester, const RecipeDetailScreen(recipeId: 'l5'));
      expect(find.byType(DemoDataBanner), findsOneWidget);
      expect(find.text(DemoDataBanner.label), findsOneWidget);
      await _drain(tester);
    });

    test('the provider routes by id', () async {
      SharedPreferences.setMockInitialValues({
        SessionController.accessTokenKey: 'test-token',
        'vl.user_id': _me,
        'vl.display_name': 'Thành viên thật',
        'vl.role': 'User',
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(c.dispose);
      final api = c.read(recipeCommunityApiProvider);
      expect(api, isA<RoutedRecipeCommunityApiService>());
      final routed = api as RoutedRecipeCommunityApiService;
      expect(routed.mock, isA<MockRecipeCommunityRepository>());
      expect(routed.remote, isA<RemoteRecipeCommunityApiService>());
      final sample = await routed.getReviews('l5');
      expect(sample.summary, isA<RatingSummary>());
      expect(sample.recipeId, 'l5');
    });
  });

  group('restaurant page', () {
    testWidgets('"my review" is found by the real id, not a sample persona',
        (tester) async {
      await _pump(
          tester,
          const RestaurantDetailScreen(
              restaurantId: _placeId, name: 'Quán thật'),
          overrides: [restaurantApiProvider.overrideWithValue(_Places())]);
      expect(find.text('Sửa đánh giá của bạn'), findsOneWidget);
      expect(find.text('Viết đánh giá'), findsNothing);
      expect(find.byType(DemoDataBanner), findsNothing);
      await _drain(tester);
    });

    test('a photo from the server opens from its host; the upload goes back',
        () {
      final media = RestaurantMediaDto.fromJson(const {
        'id': 'm1',
        'mediaType': 'Image',
        'mediaUrl': '/uploads/images/a.png',
      });
      expect(media.mediaUrl, startsWith('http'));
      expect(media.mediaUrl, endsWith('/uploads/images/a.png'));
      final sent = NewRestaurantMediaDto(
              mediaType: RestaurantMediaType.image, mediaUrl: media.mediaUrl)
          .toJson();
      expect(sent['mediaUrl'], '/uploads/images/a.png');
      final absolute = const NewRestaurantMediaDto(
              mediaType: RestaurantMediaType.image,
              mediaUrl: 'https://res.cloudinary.com/x/a.png')
          .toJson();
      expect(absolute['mediaUrl'], 'https://res.cloudinary.com/x/a.png');
    });
  });

  testWidgets('the address list says it is a sample', (tester) async {
    await _pump(tester, const LocationPickerScreen());
    expect(find.byType(DemoDataBanner), findsOneWidget);
    expect(find.text('Dùng vị trí hiện tại (mô phỏng)'), findsOneWidget);
    await _drain(tester);
  });
}
