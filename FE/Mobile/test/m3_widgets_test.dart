// test/m3_widgets_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/video_picker.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/comments_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_tile.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_posts_screen.dart';
import 'package:veganlife_mobile/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:veganlife_mobile/features/search/presentation/screens/search_screen.dart';

Future<SharedPreferences> _prefs({bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues(signedIn
      ? {'vl.access_token': 'mock.jwt', 'vl.display_name': 'Minh Anh'}
      : {});
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {bool signedIn = true,
    List<Override> overrides = const [],
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(signedIn: signedIn);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...overrides
    ],
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
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 1500]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Post _post({
  String id = 'p_test',
  String authorId = 'u_hoang_nam',
  String body = 'Nội dung ngắn.',
  PostStatus status = PostStatus.published,
  int likes = 214,
  int comments = 27,
}) =>
    Post(
      id: id,
      type: PostType.recipe,
      author: AuthorSummary(id: authorId, name: 'Tác giả'),
      title: 'Bún riêu chay cà chua đậu hũ',
      body: body,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      coverSeed: id,
      likeCount: likes,
      commentCount: comments,
      status: status,
    );

class _InstantPicker implements VideoPickerService {
  const _InstantPicker(this.video);

  final PickedVideo video;

  @override
  Future<PickedVideo?> pick(BuildContext context) async => video;
}

void main() {
  // Real Roboto metrics (shipped with the SDK), like m0_ask_ai_entry_test:
  // the default test font draws every glyph as a wide square.
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  group('PostAuthorRow', () {
    Future<void> openMenu(WidgetTester tester, int index) async {
      await tester.tap(find.byTooltip('Tuỳ chọn').at(index));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> closeMenu(WidgetTester tester) async {
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('"Sửa bài" / "Xoá bài" only on the member\'s own post',
        (tester) async {
      await _pumpApp(
        tester,
        Scaffold(
          body: Column(children: [
            PostAuthorRow(post: _post(authorId: 'u_me'), onReport: () {}),
            PostAuthorRow(post: _post(), onReport: () {}),
          ]),
        ),
      );
      await openMenu(tester, 0);
      expect(find.text('Sửa bài'), findsOneWidget);
      expect(find.text('Xoá bài'), findsOneWidget);
      expect(find.text('Báo cáo bài viết'), findsNothing);
      await closeMenu(tester);

      await openMenu(tester, 1);
      expect(find.text('Báo cáo bài viết'), findsOneWidget);
      expect(find.text('Sửa bài'), findsNothing);
      await closeMenu(tester);
    });

    testWidgets('guests never get the author menu', (tester) async {
      await _pumpApp(
        tester,
        Scaffold(
            body:
                PostAuthorRow(post: _post(authorId: 'u_me'), onReport: () {})),
        signedIn: false,
      );
      await openMenu(tester, 0);
      expect(find.text('Sửa bài'), findsNothing);
      expect(find.text('Báo cáo bài viết'), findsOneWidget);
      await closeMenu(tester);
    });
  });

  group('PostCard (full width)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('edge to edge, stats line, 3 actions at text scale $scale',
          (tester) async {
        var liked = 0;
        await _pumpApp(
          tester,
          Scaffold(
            body: ListView(children: [
              PostCard(
                post: _post(body: 'Nấu nước dùng từ củ quả. ' * 40),
                onOpen: () {},
                onLike: () => liked++,
                onComment: () {},
                onSave: () {},
              ),
            ]),
          ),
          textScale: scale,
        );
        expect(tester.getSize(find.byType(PostCard)).width, 411);
        expect(find.text('214'), findsOneWidget);
        expect(find.text('27 bình luận'), findsOneWidget);
        for (final label in ['Thích', 'Bình luận', 'Lưu']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Thích'));
        expect(liked, 1);

        await tester.ensureVisible(find.text('Xem thêm'));
        await tester.tap(find.text('Xem thêm'));
        await tester.pump();
        expect(find.text('Xem thêm'), findsNothing);
      });
    }

    testWidgets('actions are disabled while the post waits for review',
        (tester) async {
      var taps = 0;
      await _pumpApp(
        tester,
        Scaffold(
          body: PostCard(
            post: _post(status: PostStatus.pending, likes: 0, comments: 0),
            onOpen: () {},
            onLike: () => taps++,
            onComment: () => taps++,
            onSave: () => taps++,
          ),
        ),
      );
      for (final label in ['Thích', 'Bình luận', 'Lưu']) {
        await tester.tap(find.text(label));
      }
      expect(taps, 0);
    });
  });

  group('CommentsScreen', () {
    testWidgets('own comment: edit shows "(đã sửa)", delete removes it',
        (tester) async {
      await _pumpApp(
          tester, CommentsScreen(post: _post(id: 'p_com_chien_hat_sen')));
      await _wait(tester);
      expect(find.text('4'), findsOneWidget, reason: 'seed thread');
      expect(find.byTooltip('Tuỳ chọn bình luận'), findsNothing);

      await tester.enterText(find.byType(TextField), 'Thêm chút tiêu nhé');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byTooltip('Tuỳ chọn bình luận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      expect(find.text('Đang sửa bình luận'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Thêm chút tiêu đen nhé');
      await tester.tap(find.byTooltip('Lưu'));
      await _wait(tester);
      expect(find.text('Thêm chút tiêu đen nhé'), findsOneWidget);
      expect(find.text('(đã sửa)'), findsOneWidget);

      await tester.tap(find.byTooltip('Tuỳ chọn bình luận'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá'));
      await tester.pumpAndSettle();
      expect(find.text('Xoá bình luận?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await _wait(tester);
      expect(find.text('Thêm chút tiêu đen nhé'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      await _wait(tester, 2500); // feed refetch timers
    });

    testWidgets('guests read; tapping the composer asks them to sign in',
        (tester) async {
      await _pumpApp(tester, CommentsScreen(post: _post(id: 'p_b12')),
          signedIn: false);
      await _wait(tester);
      expect(find.byType(CommentTile), findsWidgets);
      await tester.tap(find.byType(TextField));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    });
  });

  group('CreatePostScreen video upload', () {
    FilledButton postButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Đăng'));

    Future<void> pickVideo(WidgetTester tester, PickedVideo video) async {
      await _pumpApp(tester, const CreatePostScreen(), overrides: [
        videoPickerProvider.overrideWithValue(_InstantPicker(video))
      ]);
      await tester.tap(find.text('Video'));
      await tester.pump();
      expect(find.text('Tải video lên'), findsOneWidget);
      expect(find.text('Dán đường dẫn'), findsOneWidget);
      await tester.tap(find.text('Chọn video'));
      await tester.pump();
    }

    testWidgets('"Đăng" stays disabled until the upload finishes',
        (tester) async {
      await pickVideo(tester, MockVideoPickerService.samples[0]);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('Đang tải lên'), findsOneWidget);
      expect(find.text('Huỷ tải lên'), findsOneWidget);
      expect(postButton(tester).onPressed, isNull);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Đã tải lên'), findsOneWidget);
      expect(postButton(tester).onPressed, isNotNull);
    });

    testWidgets('a lost connection offers "Thử lại"; too big never uploads',
        (tester) async {
      await pickVideo(tester, MockVideoPickerService.samples[1]);
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Mất kết nối'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(postButton(tester).onPressed, isNull);
    });

    testWidgets('an 850 MB file is refused before uploading', (tester) async {
      await pickVideo(tester, MockVideoPickerService.samples[2]);
      expect(find.text('Video vượt quá 200 MB'), findsOneWidget);
      expect(find.textContaining('Đang tải lên'), findsNothing);
      expect(postButton(tester).onPressed, isNull);

      // The link mode still works as before.
      await tester.tap(find.text('Dán đường dẫn'));
      await tester.pump();
      expect(find.text('Đường dẫn video'), findsOneWidget);
      expect(postButton(tester).onPressed, isNotNull);
    });
  });

  group('HealthProfileEditScreen', () {
    Future<void> open(WidgetTester tester) async {
      await _pumpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(HealthProfileEditScreen.route()),
                child: const Text('Mở hồ sơ'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở hồ sơ'));
      await _wait(tester);
    }

    Finder field(String label) => find.widgetWithText(TextFormField, label);
    FilledButton save(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu'));

    testWidgets('BMI preview follows typing; validation blocks saving',
        (tester) async {
      await open(tester);
      expect(save(tester).onPressed, isNull, reason: 'nothing changed yet');

      await tester.enterText(field('Chiều cao (cm)'), '170');
      await tester.enterText(field('Cân nặng (kg)'), '65');
      await tester.pump();
      expect(
          find.text('BMI 22,5 · Bình thường (chuẩn châu Á)'), findsOneWidget);
      await tester.enterText(field('Cân nặng (kg)'), '60');
      await tester.pump();
      expect(
          find.text('BMI 20,8 · Bình thường (chuẩn châu Á)'), findsOneWidget);

      await tester.enterText(field('Chiều cao (cm)'), '90');
      await tester.pump();
      expect(find.text('Chiều cao từ 100 đến 230 cm'), findsOneWidget);
      expect(find.text('Nhập chiều cao và cân nặng hợp lệ để xem BMI'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester);
      expect(find.text('Hồ sơ sức khoẻ'), findsOneWidget, reason: 'blocked');

      await tester.enterText(field('Chiều cao (cm)'), '170');
      await tester.enterText(field('Cân nặng (kg)'), '65,55');
      await tester.pump();
      expect(find.text('Cân nặng chỉ lấy 1 chữ số thập phân'), findsOneWidget);
    });

    testWidgets(
        '99.9 kg fails and keeps the input; a valid save offers '
        '"Tạo lại thực đơn"', (tester) async {
      await open(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Cân nặng (kg)'), '99,9');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester, 2000);
      expect(
          find.textContaining('Chưa lưu được hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.text('99,9'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Cân nặng (kg)'), '60');
      await tester.tap(find.text('Đậu nành'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await _wait(tester, 2000);
      expect(find.text('Đã lưu hồ sơ sức khoẻ'), findsOneWidget);
      expect(find.text('Tạo lại thực đơn'), findsOneWidget);
      expect(find.text('Mở hồ sơ'), findsOneWidget, reason: 'popped');
      await _wait(tester, 7000); // snackbar + planner load timers
    });
  });

  group('RecipeDetailScreen', () {
    testWidgets('ingredients with quantity, numbered steps, related search',
        (tester) async {
      await _pumpApp(tester, const RecipeDetailScreen(recipeId: 'l5'),
          size: const Size(411, 2400));
      await _wait(tester);
      expect(find.text('Bún riêu chay'), findsWidgets);
      expect(find.text('580 kcal / phần'), findsOneWidget);
      expect(find.text('Thuần chay'), findsOneWidget);
      expect(find.text('Nguyên liệu'), findsOneWidget);
      expect(find.text('300 g'), findsOneWidget);
      expect(find.text('Cách làm'), findsOneWidget);
      expect(find.textContaining('Hầm củ cải và bắp ngô'), findsOneWidget);

      await tester.tap(find.text('Tìm video & quán liên quan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SearchScreen), findsOneWidget);
      expect(
          tester.widget<SearchScreen>(find.byType(SearchScreen)).initialQuery,
          'Bún riêu chay');
      // SearchScreen runs the real mock search now; let its delayed calls finish.
      await _wait(tester, 3000);
    });

    testWidgets('an unknown id shows "Không tìm thấy công thức"',
        (tester) async {
      await _pumpApp(tester,
          const RecipeDetailScreen(recipeId: 'khong_co', name: 'Món lạ'));
      expect(find.text('Món lạ'), findsOneWidget,
          reason: 'title while loading');
      await _wait(tester);
      expect(find.text('Không tìm thấy công thức'), findsOneWidget);
    });
  });

  testWidgets('"Nội dung của tôi": status filters, banners, comments tab',
      (tester) async {
    await _pumpApp(tester, const MyPostsScreen(), size: const Size(411, 2400));
    await _wait(tester);
    expect(find.text('Tất cả (4)'), findsOneWidget);
    expect(find.text('Đã đăng (2)'), findsOneWidget);
    expect(find.text('Chờ duyệt (1)'), findsOneWidget);
    expect(find.text('Bị từ chối (1)'), findsOneWidget);
    expect(
        find.text(
            'Đang chờ Ban quản trị xem xét — bài chưa hiển thị trên bảng tin'),
        findsOneWidget);
    expect(find.textContaining('Bị từ chối: Bài khẳng định'), findsOneWidget);
    expect(find.text('Sửa & gửi lại'), findsOneWidget);

    await tester.ensureVisible(find.text('Chờ duyệt (1)'));
    await tester.tap(find.text('Chờ duyệt (1)'));
    await tester.pump();
    expect(find.text('Nước ép cần tây có chữa khỏi tiểu đường không?'),
        findsOneWidget);
    expect(find.text('Mua tempeh ở đâu tại TP.HCM?'), findsNothing);

    await tester.tap(find.descendant(
        of: find.byType(TabBar), matching: find.text('Bình luận')));
    await _wait(tester);
    expect(find.text('Chưa có bình luận nào'), findsOneWidget);
  });

  testWidgets('Thực đơn: fill a slot from a chef suggestion and by hand',
      (tester) async {
    await _pumpApp(tester, const MealPlannerScreen(),
        size: const Size(411, 2600));
    await _wait(tester, 3000);
    expect(find.text('Nguyên liệu trong tủ'), findsOneWidget);
    expect(find.text('Tạo thực đơn từ tủ lạnh'), findsWidgets);

    await tester.tap(find.byTooltip('Đổi bữa sáng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    Finder tab(String label) =>
        find.descendant(of: find.byType(TabBar), matching: find.text(label));
    for (final label in [
      'AI gợi ý',
      'Công thức của tôi',
      'Từ chuyên gia',
      'Tự nhập món'
    ]) {
      expect(tab(label), findsOneWidget, reason: label);
    }
    await tester.tap(tab('Từ chuyên gia'));
    await _wait(tester);
    await tester.tap(find.text('Cháo yến mạch hạt sen táo đỏ'));
    await _wait(tester);
    expect(find.text('Cháo yến mạch hạt sen táo đỏ'), findsOneWidget);
    expect(find.text('Chuyên gia · Lê Quang Tâm'), findsOneWidget);

    await tester.tap(find.byTooltip('Đổi bữa trưa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(tab('Tự nhập món'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên món'), 'Cơm tấm chay nhà làm');
    await tester.tap(find.text('Thêm vào bữa trưa'));
    await _wait(tester);
    expect(find.text('Cơm tấm chay nhà làm'), findsOneWidget);
    expect(find.text('Tự nhập'), findsOneWidget);
    expect(find.textContaining('Chưa rõ kcal', findRichText: true),
        findsOneWidget);
    await _wait(tester, 6000); // snackbars
  });
}
