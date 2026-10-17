// test/auth_shell/guest_gate_test.dart
// Sign-in prompts for guests: `ensureSignedIn` (the sheet) continues the
// action once signed in; `GuestGate` turns into its content in place.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/widgets/guest_gate.dart';
import 'package:veganlife_mobile/core/widgets/sign_in_sheet.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/chef_application_screen.dart';

/// "Thích" asks for sign-in, then counts the like (the post action).
class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.likes, required this.answers});

  final ValueNotifier<int> likes;
  final List<bool> answers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      onPressed: () async {
        final ok = await ensureSignedIn(context, ref,
            reason: 'Đăng nhập để thích bài viết và theo dõi tác giả.');
        answers.add(ok);
        if (ok) likes.value++;
      },
      child: const Text('Thích'),
    );
  }
}

Future<(SharedPreferences, ValueNotifier<int>, List<bool>)> _pump(
    WidgetTester tester,
    {Map<String, Object> prefs = const {}}) async {
  tester.view
    ..physicalSize = const Size(411, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final likes = ValueNotifier(0);
  final answers = <bool>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    child: MaterialApp(
      home: Scaffold(
        body: Center(child: _LikeButton(likes: likes, answers: answers)),
      ),
    ),
  ));
  return (sp, likes, answers);
}

void main() {
  setUp(MockAuthDb.reset);

  testWidgets(
      'the sheet: reason, "Đăng nhập", "Tạo tài khoản"; "Để sau" '
      'answers false', (tester) async {
    final (_, likes, answers) = await _pump(tester);
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    expect(find.text('Tham gia cộng đồng VeganLife'), findsOneWidget);
    expect(find.text('Đăng nhập để thích bài viết và theo dõi tác giả.'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    expect(
        find.widgetWithText(OutlinedButton, 'Tạo tài khoản'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);

    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInSheet), findsNothing);
    expect(answers, [false]);
    expect(likes.value, 0);
  });

  testWidgets('backing out of Đăng nhập returns to the sheet', (tester) async {
    final (_, _, answers) = await _pump(tester);
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SignInSheet), findsOneWidget);
    expect(answers, isEmpty);
  });

  testWidgets('signing in from the sheet carries on with the like',
      (tester) async {
    final (prefs, likes, answers) = await _pump(tester);
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), minhAnhAccount.email);
    await tester.enterText(find.widgetWithText(TextFormField, 'Mật khẩu'),
        minhAnhAccount.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 2)); // mock latency
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(SignInSheet), findsNothing);
    expect(answers, [true]);
    expect(likes.value, 1);
    expect(prefs.getString('vl.user_id'), 'u_me');

    // Signed in now: no sheet the second time.
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInSheet), findsNothing);
    expect(likes.value, 2);
  });

  testWidgets(
      'a "Chuyên gia" sign-up from the sheet carries on too, with the '
      'chef application on top', (tester) async {
    final (_, likes, answers) = await _pump(tester);
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Tạo tài khoản'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await tester.tap(find.text('Chuyên gia'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'), 'Lý Bếp Chay');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'bepchay.ly@gmail.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'), 'bepchay2026');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'), 'bepchay2026');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo tài khoản'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(ChefApplicationScreen), findsOneWidget);
    expect(find.text('Bước 2/2: Hồ sơ chuyên gia'), findsOneWidget);
    expect(answers, [true]);
    expect(likes.value, 1);

    // The sheet is gone underneath: "Để sau" lands on the host screen.
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.byType(ChefApplicationScreen), findsNothing);
    expect(find.byType(SignInSheet), findsNothing);
    expect(find.text('Thích'), findsOneWidget);
  });

  testWidgets('members never see the sheet', (tester) async {
    final (_, likes, answers) = await _pump(tester, prefs: {
      'vl.access_token': 'mock.jwt',
      'vl.display_name': 'Minh Anh',
      'vl.user_id': 'u_me',
      'vl.role': 'User',
    });
    await tester.tap(find.text('Thích'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInSheet), findsNothing);
    expect(answers, [true]);
    expect(likes.value, 1);
  });

  testWidgets('GuestGate: both buttons; signing in shows the content in place',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    tester.view
      ..physicalSize = const Size(411, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      child: const MaterialApp(
        home: Scaffold(
          body: GuestGate(
            icon: Icons.calendar_month_rounded,
            title: 'Thực đơn 7 ngày của riêng bạn',
            message: 'Đăng nhập để AI lên thực đơn.',
            benefits: ['Thực đơn thuần chay 7 ngày'],
            child: Text('Thực đơn của Tâm'),
          ),
        ),
      ),
    ));
    expect(find.text('Thực đơn 7 ngày của riêng bạn'), findsOneWidget);
    expect(find.text('Thực đơn của Tâm'), findsNothing);
    expect(
        find.widgetWithText(OutlinedButton, 'Tạo tài khoản'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chuyên gia')); // test-account chip
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Thực đơn của Tâm'), findsOneWidget);
    expect(find.text('Thực đơn 7 ngày của riêng bạn'), findsNothing);
  });
}
