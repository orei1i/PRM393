// test/community/post_detail_test.dart
// Post detail (TestPRM p02–p04, p07, p11): lazy comments while scrolling,
// composer pinned at the bottom, one-level replies, inline edit/delete,
// entry focus vs no focus, guest prompt, no sponsored card, video posts
// with "Xem công thức", tappable links.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/data/models/post_model.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_tile.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/linkified_text.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

/// Same static DB as the app's repository.
final _repo = MockCommunityRepository(
    currentUserName: () => 'Minh Anh',
    isSignedIn: () => true,
    currentUserId: () => 'u_me');

/// The seeded post, as the feed would hand it to the detail screen.
Future<Post> _seed(WidgetTester tester, String id) async =>
    (await tester.runAsync(() => _repo.getPost(id)))!.toEntity();

Future<void> _pump(WidgetTester tester, Widget home,
    {Map<String, Object> session = _minhAnh,
    Size size = const Size(411, 860)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(home: home),
  ));
}

/// Frames for mock latency without waiting on endless shimmer animations.
Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Unmounts the tree and lets pending mock timers finish.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

final _scroll = find.byType(CustomScrollView);
final _composerInput = find.descendant(
    of: find.byType(CommentComposer), matching: find.byType(TextField));

/// Drags the post detail up until [finder] shows, waiting for pages.
Future<void> _scrollUntil(WidgetTester tester, Finder finder,
    {int max = 40}) async {
  for (var i = 0; i < max && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(_scroll, const Offset(0, -400));
    await _wait(tester, 750);
  }
  expect(finder.hitTestable(), findsWidgets);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

EditableText _composerField(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(
        of: find.byType(CommentComposer), matching: find.byType(EditableText)));

Finder _tileOf(Finder text) =>
    find.ancestor(of: text, matching: find.byType(CommentTile));

double _headerTop(WidgetTester tester) => tester
    .getTopLeft(find.textContaining('Bình luận (', skipOffstage: false))
    .dy;

/// "Bình luận (N)", scrolled into view or not.
Finder _header(int count) =>
    find.text('Bình luận ($count)', skipOffstage: false);

void main() {
  group('lazy thread', () {
    testWidgets(
        'p_b12: newest first, more while scrolling, a 2-reply preview '
        'with "Xem thêm 1 phản hồi"', (tester) async {
      final post = await _seed(tester, 'p_b12');
      await _pump(tester, PostDetailScreen(post: post),
          session: const {}, size: const Size(411, 700));
      await _wait(tester);
      expect(_header(31), findsOneWidget);
      // No "Xem tất cả & bình luận" button: the thread is right here.
      expect(find.textContaining('Xem tất cả'), findsNothing);
      expect(find.text('Cảm ơn chị, em sẽ đi xét nghiệm trước rồi mới uống ạ.'),
          findsNothing,
          reason: 'the oldest thread is not loaded yet');

      // Thu Hà's answer is the oldest top-level comment: last page.
      await _scrollUntil(tester, find.text('Xem thêm 1 phản hồi'));
      expect(find.text('Cảm ơn chị, em sẽ đi xét nghiệm trước rồi mới uống ạ.'),
          findsOneWidget);
      expect(find.text('@Hoàng Nam Được bạn nhé, một lần mỗi tuần là đủ.'),
          findsNothing);

      await _tapVisible(tester, find.text('Xem thêm 1 phản hồi'));
      await _wait(tester, 1000);
      expect(find.text('@Hoàng Nam Được bạn nhé, một lần mỗi tuần là đủ.'),
          findsOneWidget);
      expect(find.text('Xem thêm 1 phản hồi'), findsNothing);
      await _dispose(tester);
    });

    testWidgets(
        'an empty thread invites the first comment; an unpublished post '
        'takes none', (tester) async {
      final created = (await tester.runAsync(() => _repo.createPost(
          const CreatePostRequestDto(
              type: PostType.discussion,
              title: 'Câu hỏi chưa ai trả lời',
              body:
                  'Mọi người ăn chay buổi tối thường ăn gì cho nhẹ bụng?'))))!;
      await _pump(tester, PostDetailScreen(post: created.toEntity()));
      await _wait(tester);
      expect(_header(0), findsOneWidget);
      expect(find.text('Chưa có bình luận nào. Hãy là người đầu tiên!'),
          findsOneWidget);
      expect(find.byType(CommentComposer), findsOneWidget);
      await _dispose(tester);

      final pending = await _seed(tester, 'p_me_pending_celery');
      await _pump(tester, PostDetailScreen(post: pending));
      await _wait(tester);
      expect(
          find.text('Bài chưa hiển thị trên bảng tin nên chưa nhận bình luận.'),
          findsOneWidget);
      expect(find.byType(CommentComposer), findsNothing);
      await _dispose(tester);
    });

    testWidgets('no sponsored card in a food post', (tester) async {
      final post = await _seed(tester, 'p_bun_rieu');
      await _pump(tester, PostDetailScreen(post: post));
      await _wait(tester);
      expect(find.text('Được tài trợ'), findsNothing);
      await _scrollUntil(tester, find.byType(CommentTile));
      expect(find.text('Được tài trợ'), findsNothing);
      await _dispose(tester);
    });
  });

  group('entry points', () {
    testWidgets('"Bình luận" scrolls to the comments and focuses the composer',
        (tester) async {
      final post = await _seed(tester, 'p_bun_rieu');
      await _pump(tester,
          PostDetailScreen(post: post, entry: PostDetailEntry.writeComment),
          size: const Size(411, 700));
      await _wait(tester);
      expect(_headerTop(tester), lessThan(160));
      expect(_composerField(tester).focusNode.hasFocus, isTrue);
      await _dispose(tester);
    });

    testWidgets('"N bình luận" scrolls to the comments without focus',
        (tester) async {
      final post = await _seed(tester, 'p_bun_rieu');
      await _pump(
          tester, PostDetailScreen(post: post, entry: PostDetailEntry.comments),
          size: const Size(411, 700));
      await _wait(tester);
      expect(_headerTop(tester), lessThan(160));
      expect(_composerField(tester).focusNode.hasFocus, isFalse);
      await _dispose(tester);
    });

    testWidgets('the card body opens the top of the post', (tester) async {
      final post = await _seed(tester, 'p_bun_rieu');
      await _pump(tester, PostDetailScreen(post: post),
          size: const Size(411, 700));
      await _wait(tester);
      expect(tester.getTopLeft(find.text(post.title)).dy, lessThan(200));
      expect(_headerTop(tester), greaterThan(300));
      expect(_composerField(tester).focusNode.hasFocus, isFalse);
      await _dispose(tester);
    });

    testWidgets('"Nội dung của tôi": a reply is revealed and tinted',
        (tester) async {
      final post = await _seed(tester, 'p_b12');
      await _pump(
          tester,
          PostDetailScreen(
            post: post,
            entry: PostDetailEntry.comments,
            highlightCommentId: 'c_p_b12_3',
            highlightParentId: 'c_p_b12_0',
          ),
          session: const {},
          size: const Size(411, 700));
      // Three pages, then the rest of its replies.
      for (var i = 0; i < 24 && !_isTinted(tester, 'c_p_b12_3'); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      // The scroll to it starts on the next frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      final reply =
          find.text('@Hoàng Nam Được bạn nhé, một lần mỗi tuần là đủ.');
      expect(reply.hitTestable(), findsOneWidget);
      expect(_isTinted(tester, 'c_p_b12_3'), isTrue);
      await _wait(tester, 3000);
      expect(_isTinted(tester, 'c_p_b12_3'), isFalse);
      await _dispose(tester);
    });
  });

  group('composer', () {
    testWidgets(
        'new comment on top, reply nests under its comment, '
        'reply-to-reply gets "@Tên", edit inline, delete with replies',
        (tester) async {
      final post = await _seed(tester, 'p_sua_chua_dua');
      await _pump(tester,
          PostDetailScreen(post: post, entry: PostDetailEntry.comments));
      await _wait(tester);
      expect(_header(12), findsOneWidget);

      // A new top-level comment: first in the list.
      await tester.enterText(_composerInput, 'Men vi sinh mua ở đâu vậy bạn?');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      expect(_header(13), findsOneWidget);
      final mine = find.text('Men vi sinh mua ở đâu vậy bạn?');
      expect(mine, findsOneWidget);
      expect(tester.getTopLeft(mine).dy,
          lessThan(tester.getTopLeft(find.byType(CommentTile).at(1)).dy),
          reason: 'newest first');

      // Reply to it: banner, then nested under it.
      await _tapVisible(tester,
          find.descendant(of: _tileOf(mine), matching: find.text('Trả lời')));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsOneWidget);
      expect(find.text('Viết phản hồi…'), findsOneWidget);
      await tester.enterText(_composerInput, 'Tự trả lời: siêu thị có bán.');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      expect(find.text('Đang trả lời Minh Anh'), findsNothing);
      expect(_header(14), findsOneWidget);
      final reply = find.text('Tự trả lời: siêu thị có bán.');
      expect(reply, findsOneWidget);
      expect(tester.getTopLeft(reply).dx,
          greaterThan(tester.getTopLeft(mine).dx + 30),
          reason: 'indented one level');

      // Reply to that reply: same thread, "@Minh Anh " prefilled.
      await _tapVisible(tester,
          find.descendant(of: _tileOf(reply), matching: find.text('Trả lời')));
      await tester.pump();
      expect(_composerField(tester).controller.text, '@Minh Anh ');
      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsNothing);

      // Edit inline.
      await _tapVisible(
          tester,
          find.descendant(
              of: _tileOf(mine),
              matching: find.byTooltip('Tuỳ chọn bình luận')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      expect(find.text('Đang sửa bình luận'), findsOneWidget);
      expect(_composerField(tester).controller.text,
          'Men vi sinh mua ở đâu vậy bạn?');
      await tester.enterText(
          _composerInput, 'Men vi sinh loại nào tốt vậy bạn?');
      await tester.tap(find.byTooltip('Lưu bình luận'));
      await _wait(tester, 1500);
      final edited = find.text('Men vi sinh loại nào tốt vậy bạn?');
      expect(edited, findsOneWidget);
      expect(
          find.descendant(of: _tileOf(edited), matching: find.text('(đã sửa)')),
          findsOneWidget);

      // Delete it: its reply goes too.
      await _tapVisible(
          tester,
          find.descendant(
              of: _tileOf(edited),
              matching: find.byTooltip('Tuỳ chọn bình luận')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá'));
      await tester.pumpAndSettle();
      expect(find.text('Xoá bình luận và 1 phản hồi?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await _wait(tester, 1500);
      expect(edited, findsNothing);
      expect(reply, findsNothing);
      expect(_header(12), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('guests read; the composer and "Trả lời" ask them to sign in',
        (tester) async {
      final post = await _seed(tester, 'p_quan_chay_q9');
      await _pump(tester,
          PostDetailScreen(post: post, entry: PostDetailEntry.writeComment),
          session: const {});
      await _wait(tester);
      expect(find.byType(CommentTile), findsWidgets);
      expect(find.byTooltip('Tuỳ chọn bình luận'), findsNothing);
      expect(_composerField(tester).focusNode.hasFocus, isFalse,
          reason: 'guests are not dropped into the keyboard');

      await tester.tap(_composerInput);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
      Navigator.of(tester.element(find.text('Tham gia cộng đồng VeganLife')))
          .pop(false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsNothing);

      await _tapVisible(tester, find.text('Trả lời').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
      await _dispose(tester);
    });
  });

  group('video post & body', () {
    testWidgets(
        'inline player, AI chip, "Xem công thức" opens the recipe sheet '
        '(no "Video công thức" page)', (tester) async {
      final post = await _seed(tester, 'p_video_meal_prep');
      expect(post.hasVideo, isTrue);
      expect(post.type, PostType.recipe);
      await _pump(tester, PostDetailScreen(post: post), session: const {});
      await _wait(tester);
      expect(find.text('Video công thức'), findsNothing);
      expect(find.text('Tóm tắt AI'), findsOneWidget, reason: 'AI chip');
      expect(find.text('Xem công thức'), findsOneWidget);

      await tester.tap(find.text('Xem công thức'));
      await _wait(tester, 1500);
      for (final tab in [
        'Tóm tắt AI',
        'Nguyên liệu',
        'Các bước',
        'Lời thoại'
      ]) {
        expect(find.widgetWithText(Tab, tab), findsOneWidget, reason: tab);
      }
      expect(find.text('Sao chép danh sách đi chợ'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await _wait(tester, 800);
      expect(find.widgetWithText(Tab, 'Lời thoại'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('a Hỏi đáp post shows no recipe button; links are tappable',
        (tester) async {
      final post = await _seed(tester, 'p_dam_thuc_vat');
      await _pump(tester, PostDetailScreen(post: post), session: const {});
      await _wait(tester);
      expect(find.text('Xem công thức'), findsNothing);
      expect(find.byType(LinkifiedText), findsOneWidget);
      expect(LinkifiedText.linksIn(post.body),
          [Uri.parse('https://viendinhduong.vn')]);
      await _dispose(tester);
    });

    testWidgets('LinkifiedText opens the tapped link', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LinkifiedText(
            'Xem www.y.vn/v nhé.',
            opener: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ));
      expect(LinkifiedText.linksIn('a https://x.vn/b. c www.y.vn'),
          [Uri.parse('https://x.vn/b'), Uri.parse('https://www.y.vn')]);
      // Test font: every glyph is 14 px wide; the link starts at the 5th.
      await tester.tapAt(tester.getTopLeft(find.byType(LinkifiedText)) +
          const Offset(4 * 14 + 30, 7));
      await tester.pump();
      expect(opened, [Uri.parse('https://www.y.vn/v')]);
      // Plain text opens nothing.
      await tester.tapAt(
          tester.getTopLeft(find.byType(LinkifiedText)) + const Offset(10, 7));
      await tester.pump();
      expect(opened, hasLength(1));
    });
  });
}

bool _isTinted(WidgetTester tester, String commentId) {
  final tile = find.byWidgetPredicate(
      (w) => w is CommentTile && w.comment.id == commentId,
      skipOffstage: false);
  if (tile.evaluate().isEmpty) return false;
  return tester.widget<CommentTile>(tile).highlighted;
}
