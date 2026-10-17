// test/community/device_qa_fixes_test.dart
// Device QA regressions: B2 "Trả lời" / "Sửa" open the keyboard (post
// detail and the Bếp nhanh comments sheet), B6 the photo-only picker only
// advertises photos, B7 the post author line (name + "Chuyên gia" badge +
// "— tại {quán}") at text scale 1.0 and 1.3.
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/data/media_picker.dart';
import 'package:veganlife_mobile/features/community/data/mock_community_repository.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/community/presentation/screens/post_detail_screen.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_thread.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comment_tile.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/comments_sheet.dart';
import 'package:veganlife_mobile/features/community/presentation/widgets/post_card.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

final _repo = MockCommunityRepository(
    currentUserName: () => 'Minh Anh',
    isSignedIn: () => true,
    currentUserId: () => 'u_me');

Future<Post> _seed(WidgetTester tester, String id) async =>
    (await tester.runAsync(() => _repo.getPost(id)))!.toEntity();

Future<void> _pump(WidgetTester tester, Widget home,
    {Map<String, Object> session = _minhAnh,
    Size size = const Size(411, 860),
    double textScale = 1}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(session);
  final prefs = await SharedPreferences.getInstance();
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
}

Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

final _composerInput = find.descendant(
    of: find.byType(CommentComposer), matching: find.byType(TextField));

EditableText _composerField(WidgetTester tester) =>
    tester.widget<EditableText>(find.descendant(
        of: find.byType(CommentComposer), matching: find.byType(EditableText)));

Finder _tileOf(Finder text) =>
    find.ancestor(of: text, matching: find.byType(CommentTile));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// Focused, keyboard up, caret right after the text.
void _expectKeyboardAtEnd(WidgetTester tester, {String? reason}) {
  final field = _composerField(tester);
  expect(field.focusNode.hasFocus, isTrue, reason: reason);
  expect(tester.testTextInput.isVisible, isTrue, reason: reason);
  expect(field.controller.selection,
      TextSelection.collapsed(offset: field.controller.text.length),
      reason: reason);
}

Post _chefPost({TaggedRestaurant? restaurant, String name = 'Lê Quang Tâm'}) =>
    Post(
      id: 'p_b7',
      type: PostType.recipe,
      author: AuthorSummary(id: 'u_chef_tam', name: name, isVerifiedChef: true),
      title: 'Chả lụa chay từ đậu hũ ky — không cần máy xay',
      body: 'Công thức mình bán ở quán 6 năm nay.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      coverSeed: 'p_b7',
      likeCount: 842,
      commentCount: 63,
      status: PostStatus.published,
      restaurant: restaurant,
    );

const _anLac = TaggedRestaurant(
    id: 'rs_an_lac',
    name: 'Quán Chay An Lạc',
    district: 'Q.1',
    isCertified: true);

void main() {
  // Real Roboto metrics, so widths and wrapping match a device.
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

  group('B2: "Trả lời" / "Sửa" open the keyboard', () {
    testWidgets(
        'post detail: the keyboard comes back even when the composer kept '
        'focus after Back; caret after "@Tên " / at the end of the edit',
        (tester) async {
      final post = await _seed(tester, 'p_sua_chua_dua');
      await _pump(tester,
          PostDetailScreen(post: post, entry: PostDetailEntry.comments));
      await _wait(tester);

      // Send a comment: the composer keeps focus.
      await tester.enterText(_composerInput, 'Men vi sinh mua ở đâu vậy bạn?');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      final mine = find.text('Men vi sinh mua ở đâu vậy bạn?');
      expect(mine, findsOneWidget);
      expect(_composerField(tester).focusNode.hasFocus, isTrue);

      // Back closes the keyboard but leaves the field focused.
      tester.testTextInput.hide();
      expect(tester.testTextInput.isVisible, isFalse);

      await _tapVisible(tester,
          find.descendant(of: _tileOf(mine), matching: find.text('Trả lời')));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsOneWidget);
      _expectKeyboardAtEnd(tester, reason: '"Trả lời" on a focused composer');

      // A reply, then a reply to it: "@Minh Anh " with the caret after it.
      await tester.enterText(_composerInput, 'Tự trả lời: siêu thị có bán.');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      final reply = find.text('Tự trả lời: siêu thị có bán.');
      expect(reply, findsOneWidget);
      tester.testTextInput.hide();
      await _tapVisible(tester,
          find.descendant(of: _tileOf(reply), matching: find.text('Trả lời')));
      await tester.pump();
      expect(_composerField(tester).controller.text, '@Minh Anh ');
      _expectKeyboardAtEnd(tester, reason: 'reply to a reply');

      // "Huỷ" still drops the reply and the keyboard.
      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsNothing);
      expect(_composerField(tester).focusNode.hasFocus, isFalse);

      // "Sửa" with the composer focused and the keyboard closed.
      await tester.tap(_composerInput);
      await tester.pump();
      expect(_composerField(tester).focusNode.hasFocus, isTrue);
      tester.testTextInput.hide();
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
      _expectKeyboardAtEnd(tester, reason: '"Sửa" from the comment menu');

      // Replying from an edit doesn't carry the edited text along.
      await _tapVisible(tester,
          find.descendant(of: _tileOf(mine), matching: find.text('Trả lời')));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsOneWidget);
      expect(_composerField(tester).controller.text, isEmpty);
      _expectKeyboardAtEnd(tester, reason: 'reply after an edit');

      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pump();
      await _dispose(tester);
    });

    testWidgets('post detail: "Sửa" without prior focus opens the keyboard',
        (tester) async {
      final post = await _seed(tester, 'p_sua_chua_dua');
      await _pump(tester,
          PostDetailScreen(post: post, entry: PostDetailEntry.comments));
      await _wait(tester);
      await tester.enterText(_composerInput, 'Bình luận để sửa');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      final mine = find.text('Bình luận để sửa');
      // Drop focus as a scroll would.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(_composerField(tester).focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      await _tapVisible(
          tester,
          find.descendant(
              of: _tileOf(mine),
              matching: find.byTooltip('Tuỳ chọn bình luận')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      _expectKeyboardAtEnd(tester);
      expect(_composerField(tester).controller.text, 'Bình luận để sửa');
      await _dispose(tester);
    });

    testWidgets('Bếp nhanh comments sheet: "Trả lời" opens the keyboard',
        (tester) async {
      final post = await _seed(tester, 'p_sua_chua_dua');
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCommentsSheet(context, post),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await _wait(tester);
      expect(find.byType(CommentsSheet), findsOneWidget);

      await tester.enterText(_composerInput, 'Nấu thử rồi, ngon!');
      await tester.tap(find.byTooltip('Gửi'));
      await _wait(tester, 1500);
      final mine = find.text('Nấu thử rồi, ngon!');
      expect(mine, findsOneWidget);
      tester.testTextInput.hide();

      await _tapVisible(tester,
          find.descendant(of: _tileOf(mine), matching: find.text('Trả lời')));
      await tester.pump();
      expect(find.text('Đang trả lời Minh Anh'), findsOneWidget);
      _expectKeyboardAtEnd(tester);

      // And from an unfocused composer.
      await tester.tap(find.widgetWithText(TextButton, 'Huỷ'));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.descendant(
          of: find.byType(CommentTile).first, matching: find.text('Trả lời')));
      await tester.pump();
      _expectKeyboardAtEnd(tester);
      await _dispose(tester);
    });
  });

  group('B6: the picker copy follows the requested kinds', () {
    test('hint and title per kinds', () {
      expect(MediaUploadRules.hintFor(const {MediaKind.image}),
          'Ảnh JPG, PNG, WEBP, HEIC tối đa 10 MB');
      expect(MediaUploadRules.hintFor(const {MediaKind.video}),
          'Video MP4, MOV, WEBM tối đa 200 MB');
      expect(MediaUploadRules.hintFor(const {MediaKind.image, MediaKind.video}),
          MediaUploadRules.hint);
      expect(MediaUploadRules.titleFor(const {MediaKind.image}), 'Chọn ảnh');
      expect(MediaUploadRules.titleFor(const {MediaKind.video}), 'Chọn video');
      expect(
          MediaUploadRules.titleFor(const {MediaKind.image, MediaKind.video}),
          'Chọn ảnh hoặc video');
    });

    Future<void> openPicker(WidgetTester tester, Set<MediaKind> kinds) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    const MockMediaPickerService().pick(context, kinds: kinds),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
    }

    testWidgets('photos only (complaint evidence): no video formats or samples',
        (tester) async {
      await openPicker(tester, const {MediaKind.image});
      expect(find.text('Chọn ảnh'), findsOneWidget);
      expect(
          find.text('Ảnh JPG, PNG, WEBP, HEIC tối đa 10 MB'), findsOneWidget);
      expect(find.textContaining('Video'), findsNothing);
      expect(find.textContaining('MP4'), findsNothing);
      expect(find.textContaining('mất kết nối'), findsNothing);
      expect(find.text('Dùng để thử tải lên thành công và ảnh quá lớn.'),
          findsOneWidget);
      expect(find.text('dau_hu_sot_ca.jpg'), findsOneWidget);
      expect(find.text('anh_qua_lon.png'), findsOneWidget);
      expect(find.text('banh_xeo_chay.mp4'), findsNothing);
    });

    testWidgets('videos only: no photo formats or samples', (tester) async {
      await openPicker(tester, const {MediaKind.video});
      expect(find.text('Chọn video'), findsOneWidget);
      expect(find.text('Video MP4, MOV, WEBM tối đa 200 MB'), findsOneWidget);
      expect(find.textContaining('JPG'), findsNothing);
      expect(
          find.text(
              'Dùng để thử tải lên thành công, mất kết nối và video quá lớn.'),
          findsOneWidget);
      expect(find.text('banh_xeo_chay.mp4'), findsOneWidget);
      expect(find.text('dau_hu_sot_ca.jpg'), findsNothing);
    });

    testWidgets('photos and videos (Tạo bài viết): both', (tester) async {
      await openPicker(tester, const {MediaKind.image, MediaKind.video});
      expect(find.text('Chọn ảnh hoặc video'), findsOneWidget);
      expect(find.text(MediaUploadRules.hint), findsOneWidget);
      expect(
          find.text(
              'Dùng để thử tải lên thành công, mất kết nối và tệp quá lớn.'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('video_4k_qua_lon.mov'), 200,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('dau_hu_sot_ca.jpg'), findsOneWidget);
      expect(find.text('video_4k_qua_lon.mov'), findsOneWidget);
    });
  });

  group('B7: post author line', () {
    const width = 411.0;
    final name = find.descendant(
        of: find.byKey(const ValueKey('post-author-name')),
        matching: find.text('Lê Quang Tâm'));
    final badge = find.text('Chuyên gia');
    final at = find.byKey(const ValueKey('post-author-restaurant'));

    for (final scale in [1.0, 1.3]) {
      testWidgets(
          'detail (no menu) at text scale $scale: badge next to the name, '
          '16 dp right margin, "— tại {quán}" kept whole', (tester) async {
        await _pump(tester,
            Scaffold(body: PostAuthorRow(post: _chefPost(restaurant: _anLac))),
            textScale: scale, size: const Size(width, 800));
        expect(tester.takeException(), isNull);
        expect(
            find.textContaining('— tại Quán Chay An Lạc', findRichText: true),
            findsOneWidget);

        final n = tester.getRect(name);
        final b = tester.getRect(badge);
        final r = tester.getRect(at);
        // The badge follows the name on its line, not pushed to the edge.
        expect(b.left - n.right, lessThan(30));
        expect((b.center.dy - n.center.dy).abs(), lessThan(4));
        // Nothing runs into the screen edge.
        for (final rect in [n, b, r]) {
          expect(rect.right, lessThanOrEqualTo(width - 16 + 0.5));
        }
        // The name is one line; "— tại Quán Chay An Lạc" is never split.
        final line = tester.getSize(find.text('Chuyên gia')).height;
        expect(n.height, lessThan(line * 1.6));
        expect(r.height, lessThan(n.height * 1.6));
        expect(r.top, greaterThanOrEqualTo(n.top - 1));
        // Time and category below.
        expect(tester.getRect(find.textContaining('· Công thức')).top,
            greaterThanOrEqualTo(r.bottom - 1));
      });

      testWidgets('feed card header (with "⋯") at text scale $scale',
          (tester) async {
        await _pump(
            tester,
            Scaffold(
                body: PostAuthorRow(
                    post: _chefPost(restaurant: _anLac), onReport: () {})),
            textScale: scale,
            size: const Size(width, 800));
        expect(tester.takeException(), isNull);
        final menu = tester.getRect(find.byTooltip('Tuỳ chọn'));
        for (final f in [name, badge, at]) {
          expect(tester.getRect(f).right, lessThanOrEqualTo(menu.left + 0.5));
        }
        expect(
            (tester.getRect(badge).center.dy - tester.getRect(name).center.dy)
                .abs(),
            lessThan(4));
      });
    }

    testWidgets('a long name ellipsizes and keeps the badge on screen',
        (tester) async {
      await _pump(
          tester,
          Scaffold(
              body: PostAuthorRow(
                  post: _chefPost(
                      restaurant: _anLac,
                      name: 'Nguyễn Thị Thanh Hương Lê Quang Tâm Phạm Văn'))),
          textScale: 1.3,
          size: const Size(360, 800));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(badge).right, lessThanOrEqualTo(360 - 16 + 0.5));
    });

    testWidgets('a short line stays on one row', (tester) async {
      await _pump(
          tester,
          Scaffold(
              body: PostAuthorRow(
                  post: _chefPost(
                      name: 'Tâm',
                      restaurant: const TaggedRestaurant(
                          id: 'rs_x', name: 'An Lạc', district: 'Q.1')))));
      expect(
          (tester.getRect(at).center.dy - tester.getRect(badge).center.dy)
              .abs(),
          lessThan(4));
    });
  });
}
