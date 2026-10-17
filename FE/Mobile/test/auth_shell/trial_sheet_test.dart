// test/auth_shell/trial_sheet_test.dart
// The "Hỏi AI" sign-in sheet (TrialExhaustedSheet): copy, the two ways in,
// and closing itself once the guest is signed in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:veganlife_mobile/features/chatbot/presentation/widgets/trial_exhausted_sheet.dart';

void main() {
  group('TrialExhaustedSheet', () {
    Future<void> pumpSheet(WidgetTester tester,
        {required int remaining, required int limit}) {
      return tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrialExhaustedSheet(remaining: remaining, limit: limit),
          ),
        ),
      ));
    }

    testWidgets('invites, without "đã dùng hết", while questions remain',
        (tester) async {
      await pumpSheet(tester, remaining: 2, limit: 3);
      expect(find.textContaining('Bạn vẫn còn 2/3 lượt hỏi miễn phí'),
          findsOneWidget);
      expect(find.textContaining('đã dùng hết'), findsNothing);
    });

    testWidgets('says the trial is over with the configured limit',
        (tester) async {
      await pumpSheet(tester, remaining: 0, limit: 5);
      expect(find.textContaining('Bạn đã dùng hết 5 lượt hỏi miễn phí'),
          findsOneWidget);
      expect(find.textContaining('vẫn còn'), findsNothing);
    });

    testWidgets('offers "Đăng nhập" and "Tạo tài khoản", no Google',
        (tester) async {
      await pumpSheet(tester, remaining: 0, limit: 3);
      expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
      expect(
          find.widgetWithText(OutlinedButton, 'Tạo tài khoản'), findsOneWidget);
      expect(find.text('Để sau'), findsOneWidget);
      expect(find.textContaining('Google'), findsNothing);
    });

    testWidgets(
        'signing in from the sheet closes it; "Tạo tài khoản" opens the '
        'sign-up form', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => TrialExhaustedSheet.show(context,
                      pendingPrompt: 'Đậu hũ thay thịt được không?'),
                  child: const Text('Hỏi tiếp'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Hỏi tiếp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sẽ được gửi ngay sau khi bạn đăng nhập'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(TrialExhaustedSheet), findsOneWidget,
          reason: 'backing out keeps the sheet');

      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.text('Thành viên')); // test-account chip
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
      await tester.pump(const Duration(seconds: 2)); // mock latency
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(TrialExhaustedSheet), findsNothing);
      expect(prefs.getString('vl.user_id'), minhAnhAccount.userId);
    });
  });
}
