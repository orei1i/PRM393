// test/hybrid/profile_labels_test.dart
// §9 of the plan, word for word: "Nội dung của tôi", "Thông tin cá nhân" and
// "Hồ sơ chuyên gia" on the real BE, and that a mock build keeps its own text.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/models/author_summary.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/community/domain/entities/post.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/profile/data/models/user_profile_model.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/chef_application_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/my_posts_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/profile_screen.dart';

const _me = '6ae5962396695f5c139fa9b0';
const _realModules = {BackendModule.community, BackendModule.profile};
const _savedNote = 'Bài đã lưu chỉ nằm trên máy này.';
const _truncatedNote = 'Đang hiện bài của bạn trong 250 bài mới nhất.';
const _localNote =
    'Hồ sơ đã lưu trên máy này. Máy chủ chưa nhận hồ sơ chuyên gia nên chưa có người duyệt.';

final _post = Post(
  id: 'p1',
  type: PostType.recipe,
  author: const AuthorSummary(id: _me, name: 'FE Test'),
  title: 'Bài của tôi',
  body: 'Nội dung',
  createdAt: DateTime(2026, 10, 31, 9),
  coverSeed: 'p1',
);

class _Profile implements ProfileApiService {
  _Profile({this.chefStatus = 'none', this.updateError});

  final String chefStatus;
  final ApiException? updateError;

  @override
  Future<UserProfileDto> getMe() async => UserProfileDto.fromJson({
        'id': _me,
        'email': 'member@example.com',
        'fullName': 'FE Test',
        'role': 'User',
        'chefApplication': {'status': chefStatus},
      });

  @override
  Future<UserProfileDto> updateMe(
      String userId, UpdateUserRequestDto request) async {
    final error = updateError;
    if (error != null) throw error;
    return getMe();
  }

  @override
  Future<void> submitChefApplication(ChefApplicationRequest request) async {}
}

Future<void> _pump(WidgetTester tester, Widget home,
    {List<Override> overrides = const []}) async {
  tester.view
    ..physicalSize = const Size(411, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SessionController.accessTokenKey: 'test-token',
    'vl.user_id': _me,
    'vl.display_name': 'FE Test',
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
  await tester.pump();
  await tester.pump();
}

List<Override> _lists({
  List<Post> mine = const [],
  List<Post> saved = const [],
  bool truncated = false,
}) =>
    [
      myPostsProvider.overrideWith((ref) async => mine),
      savedPostsProvider.overrideWith((ref) async => saved),
      myPostsTruncatedProvider.overrideWithValue(truncated),
    ];

void main() {
  tearDown(() => BackendModules.debugOverride(null));

  group('Nội dung của tôi', () {
    Future<void> tab(WidgetTester t, String label) async {
      await t.tap(find.widgetWithText(Tab, label));
      await t.pumpAndSettle();
    }

    testWidgets('real: saved posts say where they live', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const MyPostsScreen(), overrides: _lists(saved: [_post]));
      await tab(t, 'Đã lưu');
      expect(find.text(_savedNote), findsOneWidget);
      expect(find.text('Bài của tôi'), findsWidgets);
    });

    testWidgets('real: also with nothing saved', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const MyPostsScreen(), overrides: _lists());
      await tab(t, 'Đã lưu');
      expect(find.text(_savedNote), findsOneWidget);
      expect(find.text('Chưa lưu bài nào'), findsOneWidget);
    });

    testWidgets('real: my posts past the scan say so; the chips stay',
        (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const MyPostsScreen(),
          overrides: _lists(mine: [_post], truncated: true));
      expect(find.text(_truncatedNote), findsOneWidget);
      expect(find.text('Đã đăng (1)'), findsOneWidget);
      expect(find.text('Chờ duyệt (0)'), findsOneWidget);
    });

    testWidgets('real: no note when everything was scanned', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const MyPostsScreen(), overrides: _lists(mine: [_post]));
      expect(find.text(_truncatedNote), findsNothing);
    });

    testWidgets('real: the comments tab explains itself', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const MyPostsScreen(), overrides: _lists());
      await tab(t, 'Bình luận');
      expect(find.text('Chưa xem được bình luận của bạn'), findsOneWidget);
      expect(
          find.text(
              'Máy chủ chưa hỗ trợ danh sách này. Bình luận của bạn vẫn hiện trong từng bài viết.'),
          findsOneWidget);
    });

    testWidgets('mock: none of the notes', (t) async {
      BackendModules.debugOverride(const {});
      await _pump(t, const MyPostsScreen(),
          overrides: _lists(mine: [_post], saved: [_post]));
      expect(find.text(_truncatedNote), findsNothing);
      await tab(t, 'Đã lưu');
      expect(find.text(_savedNote), findsNothing);
    });
  });

  group('Thông tin cá nhân', () {
    testWidgets('real: a refused save keeps the form open and says why',
        (t) async {
      BackendModules.debugOverride(_realModules);
      const message =
          'Máy chủ chưa cho phép đổi thông tin cá nhân. Thử lại sau nhé.';
      final profile = (await _Profile().getMe()).toEntity();
      await _pump(
        t,
        Consumer(builder: (context, ref, _) {
          ref.watch(profileControllerProvider);
          return EditProfileScreen(profile: profile);
        }),
        overrides: [
          profileApiProvider.overrideWithValue(_Profile(
              updateError:
                  const ApiException(message: message, statusCode: 403))),
        ],
      );
      await t.enterText(
          find.widgetWithText(TextFormField, 'Họ tên'), 'Tên Mới');
      await t.tap(find.text('Lưu thay đổi'));
      await t.pump();
      await t.pump();
      expect(find.text(message), findsOneWidget);
      expect(find.text('Thông tin cá nhân'), findsOneWidget);
      expect(find.text('Tên Mới'), findsOneWidget);
    });
  });

  group('Hồ sơ chuyên gia', () {
    Future<void> openProfile(WidgetTester t, String status) => _pump(
          t,
          const ProfileScreen(),
          overrides: [
            profileApiProvider.overrideWithValue(_Profile(chefStatus: status)),
            profileHealthProvider
                .overrideWith((ref) async => null as HealthProfile?),
            ..._lists(),
          ],
        );

    testWidgets('real: pending says it is only on this device', (t) async {
      BackendModules.debugOverride(_realModules);
      await openProfile(t, 'pending');
      expect(find.text('Hồ sơ chuyên gia đang chờ duyệt'), findsOneWidget);
      expect(find.text(_localNote), findsOneWidget);
      expect(find.textContaining('Ban quản trị sẽ phản hồi'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('mock: the admins answer', (t) async {
      BackendModules.debugOverride(const {});
      await openProfile(t, 'pending');
      expect(find.text('Ban quản trị sẽ phản hồi trong 1–3 ngày làm việc.'),
          findsOneWidget);
      expect(find.text(_localNote), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('real: the form promises no email', (t) async {
      BackendModules.debugOverride(_realModules);
      await _pump(t, const ChefApplicationScreen());
      expect(find.textContaining('qua email'), findsNothing);
    });

    testWidgets('mock: the form keeps it', (t) async {
      BackendModules.debugOverride(const {});
      await _pump(t, const ChefApplicationScreen());
      expect(find.textContaining('qua email'), findsOneWidget);
    });
  });
}
