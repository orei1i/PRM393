// test/community/m3_widgets_test.dart
// PostAuthorRow, PostCard (entry callbacks, restaurant tag), CreatePostScreen
// (Facebook-like: 2 categories, "Thêm vào bài viết", photo/video upload,
// restaurant and tags) and "Nội dung của tôi".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/media_api_service.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/create_post_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/restaurant_tag.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_posts_screen.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/screens/restaurant_detail_screen.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

Future<void> _pumpApp(WidgetTester tester, Widget home,
    {bool signedIn = true,
    List<Override> overrides = const [],
    Size size = const Size(411, 900),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(signedIn ? _minhAnh : {});
  final prefs = await SharedPreferences.getInstance();
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

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

const _anLac = TaggedRestaurant(
    id: 'rs_an_lac',
    name: 'Quán Chay An Lạc',
    district: 'Q.1',
    isCertified: true);

Post _post({
  String id = 'p_test',
  String authorId = 'u_hoang_nam',
  String body = 'Nội dung ngắn.',
  PostStatus status = PostStatus.published,
  int likes = 214,
  int comments = 27,
  TaggedRestaurant? restaurant,
  PostMediaType? media,
  String? mediaUrl,
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
      restaurant: restaurant,
      mediaType: media,
      mediaUrl: mediaUrl,
    );

class _InstantPicker implements MediaPickerService {
  _InstantPicker(this.media);

  PickedMedia media;

  @override
  Future<PickedMedia?> pick(BuildContext context,
          {Set<MediaKind> kinds = const {
            MediaKind.image,
            MediaKind.video
          }}) async =>
      media;
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

    testWidgets('the author line says "— tại {quán}" and the category',
        (tester) async {
      await _pumpApp(tester,
          Scaffold(body: PostAuthorRow(post: _post(restaurant: _anLac))));
      expect(find.textContaining('— tại Quán Chay An Lạc', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('· Công thức'), findsOneWidget);
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
        expect(find.text('Chia sẻ'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Thích'));
        expect(liked, 1);

        await tester.ensureVisible(find.text('Xem thêm'));
        await tester.tap(find.text('Xem thêm'));
        await tester.pump();
        expect(find.text('Xem thêm'), findsNothing);
      });
    }

    testWidgets(
        '"Bình luận" writes, "N bình luận" opens the comments, the body opens '
        'the post', (tester) async {
      final calls = <String>[];
      await _pumpApp(
        tester,
        Scaffold(
          body: ListView(children: [
            PostCard(
              post: _post(),
              onOpen: () => calls.add('open'),
              onLike: () {},
              onComment: () => calls.add('write'),
              onOpenComments: () => calls.add('comments'),
              onSave: () {},
            ),
          ]),
        ),
      );
      await tester.tap(find.text('Bình luận'));
      await tester.tap(find.text('27 bình luận'));
      await tester.tap(find.text('Bún riêu chay cà chua đậu hũ'));
      expect(calls, ['write', 'comments', 'open']);
    });

    testWidgets('a tagged post shows the chip; it opens the restaurant',
        (tester) async {
      await _pumpApp(
        tester,
        Scaffold(
          body: ListView(children: [
            PostCard(
              post: _post(restaurant: _anLac),
              onOpen: () {},
              onLike: () {},
              onComment: () {},
              onSave: () {},
            ),
          ]),
        ),
        signedIn: false,
      );
      final chip = find.byType(RestaurantTagChip);
      expect(chip, findsOneWidget);
      expect(find.textContaining('· Q.1', findRichText: true), findsOneWidget);
      expect(
          find.descendant(
              of: chip, matching: find.byIcon(Icons.verified_rounded)),
          findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RestaurantDetailScreen), findsOneWidget);
      await _wait(tester, 2000);
      await _dispose(tester);
    });

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

  group('CreatePostScreen', () {
    late _InstantPicker picker;

    FilledButton postButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Đăng'));

    Future<void> open(WidgetTester tester, PickedMedia media) async {
      picker = _InstantPicker(media);
      await _pumpApp(tester, const CreatePostScreen(), overrides: [
        mediaPickerProvider.overrideWithValue(picker),
        mediaApiProvider.overrideWithValue(
            MockMediaRepository(tick: const Duration(milliseconds: 100))),
      ]);
    }

    Future<void> attach(WidgetTester tester) async {
      await tester.tap(find.text('Ảnh/Video'));
      await tester.pump();
    }

    testWidgets(
        'Facebook-like: ✕ · Tạo bài viết · Đăng, 2 categories, '
        '"Thêm vào bài viết" bar, no link mode', (tester) async {
      await open(tester, MockMediaPickerService.imageSamples.first);
      expect(find.byTooltip('Đóng'), findsOneWidget);
      expect(find.text('Tạo bài viết'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Đăng'), findsOneWidget);
      expect(find.text('Minh Anh'), findsOneWidget);
      expect(find.widgetWithText(SegmentedButton<PostType>, 'Công thức'),
          findsOneWidget);
      expect(find.widgetWithText(SegmentedButton<PostType>, 'Hỏi đáp'),
          findsOneWidget);
      expect(find.text('Video'), findsNothing);
      expect(find.text('Dán đường dẫn'), findsNothing);
      for (final label in [
        'Thêm vào bài viết',
        'Ảnh/Video',
        'Gắn quán',
        'Gắn thẻ'
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
          find.text(
              'Nguyên liệu, cách làm… Có link video thì dán luôn vào đây'),
          findsOneWidget);
      await tester.tap(find.text('Hỏi đáp'));
      await tester.pump();
      expect(find.text('Bạn muốn hỏi gì về ăn chay?'), findsOneWidget);
    });

    testWidgets(
        'a video uploads with progress; "Đăng" waits; the AI note is for '
        'Công thức only', (tester) async {
      await open(tester, MockMediaPickerService.videoSamples[0]);
      await attach(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.textContaining('Đang tải lên'), findsOneWidget);
      expect(find.text('Huỷ tải lên'), findsOneWidget);
      expect(postButton(tester).onPressed, isNull);
      expect(find.textContaining('AI sẽ nghe lời thoại'), findsOneWidget);
      await tester.tap(find.text('Hỏi đáp'));
      await tester.pump();
      expect(find.textContaining('AI sẽ nghe lời thoại'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Đã tải lên'), findsOneWidget);
      expect(postButton(tester).onPressed, isNotNull);
      expect(find.text('Đổi'), findsOneWidget);

      // ✕ on the preview removes it.
      await tester.tap(find.byTooltip('Bỏ tệp đính kèm'));
      await tester.pump();
      expect(find.text('Đã tải lên'), findsNothing);
    });

    testWidgets('a lost connection offers "Thử lại"; too big never uploads',
        (tester) async {
      await open(tester, MockMediaPickerService.videoSamples[1]);
      await attach(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Mất kết nối'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(postButton(tester).onPressed, isNull);

      picker.media = MockMediaPickerService.videoSamples[2];
      await tester.tap(find.text('Đổi'));
      await tester.pump();
      expect(find.text('Video vượt quá 200 MB'), findsOneWidget);
      expect(find.textContaining('Đang tải lên'), findsNothing);
      expect(postButton(tester).onPressed, isNull);

      picker.media = MockMediaPickerService.imageSamples[1];
      await tester.tap(find.text('Đổi'));
      await tester.pump();
      expect(find.text('Ảnh vượt quá 10 MB'), findsOneWidget);
      expect(postButton(tester).onPressed, isNull);
    });

    testWidgets('a photo, a restaurant and tags: posts and pops the saved post',
        (tester) async {
      Post? created;
      picker = _InstantPicker(MockMediaPickerService.imageSamples.first);
      await _pumpApp(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => created =
                    await Navigator.of(context).push(CreatePostScreen.route()),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
        overrides: [
          mediaPickerProvider.overrideWithValue(picker),
          mediaApiProvider.overrideWithValue(
              MockMediaRepository(tick: const Duration(milliseconds: 50))),
        ],
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hỏi đáp'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Tiêu đề'),
          'Quán chay An Lạc có món gì ngon?');
      await tester.enterText(find.widgetWithText(TextFormField, 'Nội dung'),
          'Mình sắp ghé quán, mọi người gợi ý món nhé. Review: https://example.vn/an-lac');
      await attach(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Đã tải lên'), findsOneWidget);

      await tester.tap(find.text('Gắn quán'));
      await _wait(tester, 2500);
      expect(find.text('Quán gần bạn'), findsOneWidget);
      await tester.tap(find.text('Quán Chay An Lạc').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(RestaurantTagChip), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.byType(RestaurantTagChip), findsOneWidget);
      expect(find.byTooltip('Bỏ gắn quán'), findsOneWidget);

      await tester.tap(find.text('Gắn thẻ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhanh gọn'));
      await tester.pump();
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      expect(find.text('Gắn thẻ (1)'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Nhanh gọn'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Đăng'));
      await _wait(tester, 2000);
      await tester.pumpAndSettle();
      expect(find.byType(CreatePostScreen), findsNothing);
      expect(created, isNotNull);
      expect(created!.type, PostType.discussion);
      expect(created!.mediaType, PostMediaType.image);
      expect(created!.restaurant?.id, 'rs_an_lac');
      expect(created!.restaurant?.district, 'Q.1');
      expect(created!.tags, ['quick']);
      expect(created!.body, contains('https://example.vn/an-lac'));
      await _dispose(tester);
    });

    testWidgets('✕ with a draft asks before dropping it', (tester) async {
      await open(tester, MockMediaPickerService.imageSamples.first);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tiêu đề'), 'Bản nháp');
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('Bỏ bài viết?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục viết'));
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp'), findsOneWidget);
    });

    testWidgets('edit mode: "Sửa bài viết · Lưu", the attachment is locked',
        (tester) async {
      await _pumpApp(
        tester,
        CreatePostScreen(
            editing: _post(
                authorId: 'u_me',
                media: PostMediaType.image,
                mediaUrl: 'https://x/a.jpg',
                restaurant: _anLac)),
      );
      expect(find.text('Sửa bài viết'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Lưu'), findsOneWidget);
      expect(find.text('Ảnh đã đăng'), findsOneWidget);
      expect(find.byType(RestaurantTagChip), findsOneWidget);
      expect(find.byTooltip('Không đổi được ảnh/video khi sửa bài'),
          findsOneWidget);
    });
  });

  testWidgets(
      '"Nội dung của tôi": status filters, banners; a video post opens the '
      'post detail', (tester) async {
    await _pumpApp(tester, const MyPostsScreen(), size: const Size(411, 2400));
    await _wait(tester);
    // The composer test above may have added a published post of hers.
    expect(find.textContaining(RegExp(r'^Tất cả \((4|5)\)$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Đã đăng \((2|3)\)$')), findsOneWidget);
    expect(find.text('Chờ duyệt (1)'), findsOneWidget);
    expect(find.text('Bị từ chối (1)'), findsOneWidget);
    expect(
        find.text(
            'Đang chờ Ban quản trị xem xét — bài chưa hiển thị trên bảng tin'),
        findsOneWidget);
    expect(find.textContaining('Bị từ chối: Bài khẳng định'), findsOneWidget);
    expect(find.text('Sửa & gửi lại'), findsOneWidget);

    await tester
        .tap(find.text('Bánh xèo chay nhân nấm — video đầu tay của mình'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(find.text('Video công thức'), findsNothing);
    await _wait(tester);
    await tester.pageBack();
    await _wait(tester, 800);

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
    await _dispose(tester);
  });
}
