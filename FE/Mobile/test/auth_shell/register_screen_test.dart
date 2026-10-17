// test/auth_shell/register_screen_test.dart
// "Tạo tài khoản": role card, field rules, 409, member vs chef outcome.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/session/mock_accounts.dart';
import 'package:veganlife_mobile/core/session/mock_auth_db.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:veganlife_mobile/features/chef/domain/chef_specialties.dart';
import 'package:veganlife_mobile/features/profile/data/profile_api_service.dart';
import 'package:veganlife_mobile/features/profile/domain/entities/user_profile.dart';
import 'package:veganlife_mobile/features/profile/presentation/controllers/profile_controller.dart';
import 'package:veganlife_mobile/features/profile/presentation/screens/chef_application_screen.dart';

Finder _field(String label) => find.widgetWithText(TextFormField, label);
final _create = find.widgetWithText(FilledButton, 'Tạo tài khoản');

Future<(ProviderContainer, List<bool?>)> _pumpHost(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(411, 1400)
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
                  .push<bool>(RegisterScreen.route())),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Mở'));
  await tester.pumpAndSettle();
  final container =
      ProviderScope.containerOf(tester.element(find.byType(RegisterScreen)));
  return (container, results);
}

Future<void> _fill(
  WidgetTester tester, {
  String name = 'Ngô Bảo Châu',
  String email = 'baochau.ngo@gmail.com',
  String phone = '',
  String password = 'baochau2026',
  String? confirm,
  bool agree = true,
}) async {
  await tester.enterText(_field('Họ và tên'), name);
  await tester.enterText(_field('Email'), email);
  await tester.enterText(_field('Số điện thoại (không bắt buộc)'), phone);
  await tester.enterText(_field('Mật khẩu'), password);
  await tester.enterText(_field('Nhập lại mật khẩu'), confirm ?? password);
  if (agree) await tester.tap(find.byType(Checkbox));
}

void main() {
  setUp(() {
    MockAuthDb.reset();
    MockProfileRepository.reset();
  });

  testWidgets('"Chuyên gia" explains the admin review', (tester) async {
    await _pumpHost(tester);
    expect(find.text('Bạn là'), findsOneWidget);
    const note =
        'Tài khoản chuyên gia cần Ban quản trị duyệt hồ sơ. Sau khi đăng ký, bạn sẽ điền hồ sơ chuyên gia.';
    expect(find.text(note), findsNothing);
    await tester.tap(find.text('Chuyên gia'));
    await tester.pump();
    expect(find.text(note), findsOneWidget);
    await tester.tap(find.text('Thành viên'));
    await tester.pump();
    expect(find.text(note), findsNothing);
  });

  testWidgets('field rules and the required terms', (tester) async {
    final (container, results) = await _pumpHost(tester);
    await tester.tap(_create);
    await tester.pump();
    expect(find.text('Họ và tên cần từ 2 đến 100 ký tự'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự, gồm chữ và số'),
        findsOneWidget);
    expect(find.text('Bạn cần đồng ý để tạo tài khoản'), findsOneWidget);

    await _fill(tester,
        name: 'A',
        phone: '12345',
        password: 'chiconchu',
        confirm: 'khac',
        agree: false);
    await tester.tap(_create);
    await tester.pump();
    expect(find.text('Họ và tên cần từ 2 đến 100 ký tự'), findsOneWidget);
    expect(find.text('Số điện thoại không hợp lệ'), findsOneWidget);
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự, gồm chữ và số'),
        findsOneWidget);
    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);

    // Digits only is not enough either; +84 phones are fine.
    await _fill(tester,
        phone: '+84912345678',
        password: '12345678',
        confirm: '12345678',
        agree: false);
    await tester.tap(_create);
    await tester.pump();
    expect(find.text('Số điện thoại không hợp lệ'), findsNothing);
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự, gồm chữ và số'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(results, isEmpty);
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
  });

  testWidgets('a seeded email gets the 409 message', (tester) async {
    final (container, results) = await _pumpHost(tester);
    await _fill(tester, email: minhAnhAccount.email);
    await tester.tap(_create);
    await tester.pump();
    expect(find.text('Đang tạo tài khoản…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(
        find.text('Email này đã có tài khoản. Đăng nhập hoặc dùng email khác.'),
        findsOneWidget);
    expect(results, isEmpty);
    expect(container.read(sessionControllerProvider).isGuest, isTrue);
  });

  testWidgets('a member sign-up signs in and pops true', (tester) async {
    final (container, results) = await _pumpHost(tester);
    await _fill(tester, phone: '0987 654 321');
    await tester.tap(_create);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
    expect(results, [true]);
    final session = container.read(sessionControllerProvider);
    expect(session.isGuest, isFalse);
    expect(session.role, UserRole.user);
    expect(session.displayName, 'Ngô Bảo Châu');
    final loading = container.read(profileControllerProvider.future);
    await tester.pump(const Duration(seconds: 2)); // mock latency
    final me = await loading;
    expect(me.email, 'baochau.ngo@gmail.com');
    expect(me.phone, '0987654321');
  });

  testWidgets(
      'a chef sign-up stays a member and continues to "Bước 2/2"; after '
      'submitting, the application is pending', (tester) async {
    final (container, results) = await _pumpHost(tester);
    await tester.tap(find.text('Chuyên gia'));
    await tester.pump();
    await _fill(tester, name: 'Võ Đầu Bếp', email: 'daubep.vo@gmail.com');
    await tester.tap(_create);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(ChefApplicationScreen), findsOneWidget);
    expect(find.text('Bước 2/2: Hồ sơ chuyên gia'), findsOneWidget);
    expect(results, [true], reason: 'the opener continues signed in');
    expect(container.read(sessionControllerProvider).role, UserRole.user);
    expect(container.read(sessionControllerProvider).isChef, isFalse);

    await tester.tap(find.text(chefSpecialties.first));
    await tester.enterText(_field('Số năm kinh nghiệm'), '6');
    await tester.enterText(_field('Thành phố'), 'Đà Nẵng');
    await tester.enterText(_field('Giới thiệu'),
        'Đầu bếp chay 6 năm tại các nhà hàng chay ở Đà Nẵng, chuyên món Huế.');
    await tester.enterText(
        find.widgetWithText(TextField,
            'VD: Chứng chỉ Đầu bếp chuyên nghiệp — CĐ Du lịch Sài Gòn'),
        'Chứng chỉ Bếp chay');
    await tester.tap(find.byTooltip('Thêm chứng chỉ'));
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, 'Gửi hồ sơ');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byType(ChefApplicationScreen), findsNothing);
    final loading = container.read(profileControllerProvider.future);
    await tester.pump(const Duration(seconds: 2)); // mock latency
    final me = await loading;
    expect(me.chefApplication, ChefApplicationStatus.pending);
    expect(me.role, UserRole.user);
  });
}
