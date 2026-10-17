// test/auth_shell/chef_application_test.dart
// The chef application form, also step 2 of a "Chuyên gia" sign-up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/chef/domain/chef_specialties.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/chef_application_screen.dart';

void main() {
  testWidgets('chef application: submit scrolls to and focuses the bad field',
      (tester) async {
    tester.view
      ..physicalSize = const Size(400, 560)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ChefApplicationScreen())));

    await tester.tap(find.text(chefSpecialties.first));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Số năm kinh nghiệm'), '5');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Thành phố'), 'Huế');
    final bio = find.widgetWithText(TextFormField, 'Giới thiệu');
    await tester.enterText(bio, 'Quá ngắn');
    await tester.enterText(
        find.widgetWithText(TextField,
            'VD: Chứng chỉ Đầu bếp chuyên nghiệp — CĐ Du lịch Sài Gòn'),
        'Chứng chỉ Bếp chay');
    await tester.ensureVisible(find.byTooltip('Thêm chứng chỉ'));
    await tester.tap(find.byTooltip('Thêm chứng chỉ'));
    await tester.pump();

    final submit = find.widgetWithText(FilledButton, 'Gửi hồ sơ');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    final bioEditable = tester.widget<EditableText>(
        find.descendant(of: bio, matching: find.byType(EditableText)));
    expect(bioEditable.focusNode.hasFocus, isTrue);
    final rect = tester.getRect(bio);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.top, lessThan(560));
    expect(find.text('Viết ít nhất 50 ký tự để học viên hiểu về bạn.'),
        findsOneWidget);
    expect(find.text('Hồ sơ chưa hợp lệ: giới thiệu.'), findsOneWidget);
  });

  testWidgets('from sign-up: "Bước 2/2" banner and "Để sau"', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(ChefApplicationScreen.route(fromRegistration: true)),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(find.text('Hồ sơ chuyên gia'), findsOneWidget);
    expect(find.text('Bước 2/2: Hồ sơ chuyên gia'), findsOneWidget);
    expect(find.textContaining('khoá học'), findsNothing);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.byType(ChefApplicationScreen), findsNothing);
  });

  testWidgets('from Tôi: no step banner, no "Để sau"', (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ChefApplicationScreen())));
    expect(find.text('Đăng ký chuyên gia'), findsOneWidget);
    expect(find.textContaining('Bước 2/2'), findsNothing);
    expect(find.text('Để sau'), findsNothing);
  });
}
