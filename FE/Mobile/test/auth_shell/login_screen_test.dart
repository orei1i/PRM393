// test/auth_shell/login_screen_test.dart
// "Đăng nhập": validation, test-account chips (mock only), server error
// messages, and popping `true` once signed in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/register_screen.dart';

final _email = find.widgetWithText(TextFormField, 'Email');
final _password = find.widgetWithText(TextFormField, 'Mật khẩu');
final _submit = find.widgetWithText(FilledButton, 'Đăng nhập');

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)))
    .controller
    .text;

/// A host screen with "Mở" pushing [LoginScreen.route]; [results] collects
/// what the route resolves to.
Future<(SharedPreferences, List<bool?>)> _pumpHost(WidgetTester tester,
    {Widget Function()? login}) async {
  tester.view
    ..physicalSize = const Size(411, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final results = <bool?>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => results.add(await Navigator.of(context)
                  .push<bool>(login == null
                      ? LoginScreen.route()
                      : MaterialPageRoute<bool>(builder: (_) => login()))),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Mở'));
  await tester.pumpAndSettle();
  return (prefs, results);
}

Future<void> _signIn(WidgetTester tester, String email, String password) async {
  await tester.enterText(_email, email);
  await tester.enterText(_password, password);
  await tester.tap(_submit);
  await tester.pump();
}

void main() {
  setUp(MockAuthDb.reset);

  testWidgets('checks the email and the password before asking the server',
      (tester) async {
    final (prefs, _) = await _pumpHost(tester);
    expect(find.text('Đăng nhập'), findsWidgets);
    await tester.tap(_submit);
    await tester.pump();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Nhập mật khẩu'), findsOneWidget);

    await tester.enterText(_email, 'minhanh@');
    await tester.tap(_submit);
    await tester.pump();
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Đang đăng nhập…'), findsNothing);
    expect(prefs.containsKey('vl.access_token'), isFalse);
  });

  testWidgets('wrong password: the 401 message, still on Đăng nhập',
      (tester) async {
    final (prefs, results) = await _pumpHost(tester);
    await _signIn(tester, minhAnhAccount.email, 'sai2026abc');
    expect(find.text('Đang đăng nhập…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // mock latency
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(results, isEmpty);
    expect(prefs.containsKey('vl.access_token'), isFalse);
  });

  testWidgets('locked, admin and server-error seeds show their messages',
      (tester) async {
    await _pumpHost(tester);
    for (final (email, password, message) in [
      (
        lockedAccount.email,
        lockedAccount.password,
        'Tài khoản đang bị khoá. Liên hệ hỗ trợ.'
      ),
      (
        adminAccount.email,
        adminAccount.password,
        'Tài khoản quản trị chỉ dùng trên web quản trị.'
      ),
      (
        serverErrorEmail,
        'abc12345',
        'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.'
      ),
    ]) {
      await _signIn(tester, email, password);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: email);
    }
  });

  testWidgets('five wrong passwords: "thử lại sau 5 phút"', (tester) async {
    await _pumpHost(tester);
    for (var i = 0; i < 5; i++) {
      await _signIn(tester, tamChefAccount.email, 'sai${i}matkhau');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
    expect(find.text('Bạn thử sai quá nhiều lần. Thử lại sau 5 phút.'),
        findsOneWidget);
  });

  testWidgets('the chips fill the seeded member or chef; success pops true',
      (tester) async {
    final (prefs, results) = await _pumpHost(tester);
    expect(find.text('Điền tài khoản thử nghiệm:'), findsOneWidget);
    await tester.tap(find.text('Thành viên'));
    await tester.pump();
    expect(_text(tester, _email), minhAnhAccount.email);
    expect(_text(tester, _password), minhAnhAccount.password);
    await tester.tap(find.text('Chuyên gia'));
    await tester.pump();
    expect(_text(tester, _email), tamChefAccount.email);

    await tester.tap(_submit);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(results, [true]);
    expect(prefs.getString('vl.user_id'), 'u_chef_tam');
    expect(prefs.getString('vl.role'), 'Chef');
  });

  testWidgets('no test-account chips outside mock builds', (tester) async {
    await _pumpHost(tester,
        login: () => const LoginScreen(showTestAccounts: false));
    expect(find.text('Điền tài khoản thử nghiệm:'), findsNothing);
    expect(find.text('Thành viên'), findsNothing);
  });

  testWidgets('the password can be shown', (tester) async {
    await _pumpHost(tester);
    EditableText field() => tester.widget<EditableText>(
        find.descendant(of: _password, matching: find.byType(EditableText)));
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Hiện mật khẩu'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    expect(find.byTooltip('Ẩn mật khẩu'), findsOneWidget);
  });

  testWidgets(
      '"Chưa có tài khoản? Đăng ký": a sign-up there also resolves '
      'Đăng nhập with true', (tester) async {
    final (prefs, results) = await _pumpHost(tester);
    expect(find.text('Chưa có tài khoản?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Đăng ký'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    // "Đăng nhập" at the bottom of the sign-up goes back to this login.
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Đăng nhập'));
    await tester.tap(find.widgetWithText(TextButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(results, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Đăng ký'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'), 'Phan Mai');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'phanmai@gmail.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Mật khẩu'), 'phanmai2026');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nhập lại mật khẩu'), 'phanmai2026');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    final create = find.widgetWithText(FilledButton, 'Tạo tài khoản');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(results, [true]);
    expect(prefs.getString('vl.display_name'), 'Phan Mai');
  });
}
