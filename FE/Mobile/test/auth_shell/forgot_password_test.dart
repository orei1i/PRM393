// test/auth_shell/forgot_password_test.dart
// "Quên mật khẩu": email → code (mock banner, resend countdown, 3 wrong
// codes) → new password → back on Đăng nhập with the email prefilled.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);
Finder _button(String label) => find.widgetWithText(FilledButton, label);

Future<SharedPreferences> _pumpLogin(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(411, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MaterialApp(home: LoginScreen()),
  ));
  return prefs;
}

/// Waits out the mock latency (under a second); a countdown started by the
/// answer has then ticked exactly once.
Future<void> _wait(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _toCodeStep(WidgetTester tester, String email) async {
  await tester.tap(find.text('Quên mật khẩu?'));
  await tester.pumpAndSettle();
  expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  await tester.enterText(_field('Email'), email);
  await tester.tap(_button('Gửi mã'));
  await _wait(tester);
}

void main() {
  setUp(MockAuthDb.reset);

  testWidgets('three steps end on Đăng nhập; the new password works',
      (tester) async {
    final prefs = await _pumpLogin(tester);
    await tester.enterText(_field('Email'), minhAnhAccount.email);
    await _toCodeStep(tester, minhAnhAccount.email);

    expect(
        find.text(
            'Nếu email đã đăng ký, mã 6 chữ số đã được gửi tới m•••@gmail.com'),
        findsOneWidget);
    expect(find.text('(Bản thử nghiệm) Mã xác minh: $mockResetCode'),
        findsOneWidget);
    expect(find.text('Gửi lại mã (0:59)'), findsOneWidget);

    await tester.enterText(_field('Nhập mã'), '12');
    await tester.tap(_button('Xác nhận'));
    await tester.pump();
    expect(find.text('Mã gồm 6 chữ số'), findsOneWidget);

    await tester.enterText(_field('Nhập mã'), mockResetCode);
    await tester.tap(_button('Xác nhận'));
    await _wait(tester);
    expect(_field('Mật khẩu mới'), findsOneWidget);

    await tester.enterText(_field('Mật khẩu mới'), 'ngan');
    await tester.enterText(_field('Nhập lại mật khẩu mới'), 'khac');
    await tester.tap(_button('Đổi mật khẩu'));
    await tester.pump();
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự, gồm chữ và số'),
        findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);

    await tester.enterText(_field('Mật khẩu mới'), 'minhanhMoi2026');
    await tester.enterText(_field('Nhập lại mật khẩu mới'), 'minhanhMoi2026');
    await tester.tap(_button('Đổi mật khẩu'));
    await _wait(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text('Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới.'),
        findsOneWidget);
    final email = tester.widget<EditableText>(find.descendant(
        of: _field('Email'), matching: find.byType(EditableText)));
    expect(email.controller.text, minhAnhAccount.email);

    // The old password fails, the new one signs in.
    await tester.enterText(_field('Mật khẩu'), minhAnhAccount.password);
    await tester.tap(_button('Đăng nhập'));
    await _wait(tester);
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
    await tester.enterText(_field('Mật khẩu'), 'minhanhMoi2026');
    await tester.tap(_button('Đăng nhập'));
    await _wait(tester);
    await tester.pumpAndSettle();
    expect(prefs.getString('vl.user_id'), 'u_me');
    // Let the snackbar finish.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('three wrong codes kill it; "Gửi lại mã" is open right away',
      (tester) async {
    await _pumpLogin(tester);
    await _toCodeStep(tester, tamChefAccount.email);
    final resend = find.widgetWithText(TextButton, 'Gửi lại mã (0:59)');
    expect(tester.widget<TextButton>(resend).onPressed, isNull);

    for (final (code, message) in [
      ('111111', 'Mã xác minh không đúng. Bạn còn 2 lần thử.'),
      ('222222', 'Mã xác minh không đúng. Bạn còn 1 lần thử.'),
      ('333333', 'Mã đã hết hiệu lực, hãy gửi lại mã'),
    ]) {
      await tester.enterText(_field('Nhập mã'), code);
      await tester.tap(_button('Xác nhận'));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(message), findsOneWidget, reason: code);
    }
    final again = find.widgetWithText(TextButton, 'Gửi lại mã');
    expect(tester.widget<TextButton>(again).onPressed, isNotNull);

    await tester.tap(again);
    await _wait(tester);
    expect(find.textContaining('Gửi lại mã (0:5'), findsOneWidget);
    await tester.enterText(_field('Nhập mã'), mockResetCode);
    await tester.tap(_button('Xác nhận'));
    await _wait(tester);
    expect(_field('Mật khẩu mới'), findsOneWidget);
  });

  testWidgets('the resend countdown runs for a minute', (tester) async {
    await _pumpLogin(tester);
    await _toCodeStep(tester, tamChefAccount.email);
    expect(find.text('Gửi lại mã (0:59)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Gửi lại mã (0:29)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 29));
    final resend = find.widgetWithText(TextButton, 'Gửi lại mã');
    expect(resend, findsOneWidget);
    expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
  });

  testWidgets('an unknown email reads the same, without a code',
      (tester) async {
    await _pumpLogin(tester);
    await _toCodeStep(tester, 'chua.dang.ky@gmail.com');
    expect(
        find.text(
            'Nếu email đã đăng ký, mã 6 chữ số đã được gửi tới c•••@gmail.com'),
        findsOneWidget);
    expect(find.textContaining('(Bản thử nghiệm)'), findsNothing);

    // "Đổi email" goes back to step 1.
    await tester.tap(find.text('Đổi email'));
    await tester.pump();
    expect(_button('Gửi mã'), findsOneWidget);
  });
}
