// test/m4_chef_clients_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_clients_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/domain/chef_client_rules.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_client_detail_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_clients_screen.dart';
import 'package:veganlife_mobile/features/chef_studio/presentation/screens/chef_suggestions_screen.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/data/models/order_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/chef_suggestion_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/mock_recipe_book.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

const _tam = {
  'vl.access_token': 'mock.jwt.tam',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
};

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// A paid package order (wire shape) with its access grant.
OrderDto _order({
  String type = 'VIP Menu',
  String status = 'Paid',
  required DateTime grantedAt,
  DateTime? expiresAt,
  String grant = 'Active',
  Map<String, dynamic>? consultation,
}) =>
    OrderDto.fromJson({
      'id': 'o_${grantedAt.microsecondsSinceEpoch}_$type',
      'userId': 'u_x',
      'serviceId': 's',
      'amount': 1500000,
      'status': status,
      'createdAt': _iso(grantedAt),
      'service': {
        'id': 's',
        'title': 'Gói',
        'type': type,
        'chefId': 'c',
        'chefName': 'Tâm'
      },
      'accessGrant': {
        'id': 'g',
        'paymentId': 'p',
        'grantedAt': _iso(grantedAt),
        'expiresAt': expiresAt == null ? null : _iso(expiresAt),
        'status': grant,
      },
      'consultation': consultation,
    });

void main() {
  final now = DateTime(2026, 10, 15, 10);

  group('client buckets', () {
    test('packages: live, ending within 7 days, finished', () {
      final vip18 = _order(
          grantedAt: now.subtract(const Duration(days: 12)),
          expiresAt: now.add(const Duration(days: 18)));
      final vip5 = _order(
          grantedAt: now.subtract(const Duration(days: 25)),
          expiresAt: now.add(const Duration(days: 5)));
      final expired = _order(
          grantedAt: now.subtract(const Duration(days: 40)),
          expiresAt: now.subtract(const Duration(days: 10)));
      final refunded = _order(
          status: 'Refunded',
          grant: 'Revoked',
          grantedAt: now.subtract(const Duration(days: 2)),
          expiresAt: now.add(const Duration(days: 28)));
      Map<String, dynamic> consult(String status, DateTime start) => {
            'id': 'cs',
            'chefId': 'c',
            'chefName': 'Tâm',
            'serviceTitle': 'Tư vấn',
            'durationMinutes': 60,
            'amount': 350000,
            'startAt': _iso(start),
            'status': status,
          };
      final upcoming = _order(
          type: 'Consult',
          grantedAt: now.subtract(const Duration(days: 1)),
          expiresAt: now.add(const Duration(days: 3)),
          consultation: consult('Confirmed', now.add(const Duration(days: 2))));
      final done = _order(
          type: 'Consult',
          grantedAt: now.subtract(const Duration(hours: 30)),
          expiresAt: now.add(const Duration(hours: 2)),
          consultation:
              consult('Completed', now.subtract(const Duration(hours: 22))));

      expect(packageBucket(vip18, now), ClientBucket.active);
      expect(packageBucket(vip5, now), ClientBucket.expiringSoon);
      expect(packageBucket(expired, now), ClientBucket.ended);
      expect(packageBucket(refunded, now), ClientBucket.ended);
      expect(packageBucket(upcoming, now), ClientBucket.active);
      expect(packageBucket(done, now), ClientBucket.ended);
      expect(daysLeft(vip18, now), 18);
      expect(daysLeft(expired, now), 0);

      // Anything about to run out puts the client under "Sắp hết hạn".
      expect(clientBucketOf([vip18, vip5], now), ClientBucket.expiringSoon);
      expect(clientBucketOf([expired, upcoming], now), ClientBucket.active);
      expect(clientBucketOf([expired, done], now), ClientBucket.ended);
      expect(
          primaryPackage([vip18, vip5], ClientBucket.expiringSoon, now), vip5);
      expect(nextConsultation([vip18, upcoming, done], now), upcoming);
      expect(canSuggestTo([expired, done], now), isFalse);
      expect(hasMenuPackage([upcoming], now), isTrue);
      expect(ClientBucket.fromApi('expiring_soon'), ClientBucket.expiringSoon);
    });
  });

  group('mock clients & suggestions (Tâm)', () {
    setUp(() {
      MockCommerceDb.reset();
      MockMealPlannerRepository.reset();
    });

    MockChefClientsRepository repo({UserRole role = UserRole.chef}) =>
        MockChefClientsRepository(
            currentUserId: () => 'u_chef_tam', currentRole: () => role);

    MockChefSuggestionRepository suggestions({bool chef = true}) =>
        MockChefSuggestionRepository(
            chefUserId: () => 'u_chef_tam',
            chefName: () => 'Lê Quang Tâm',
            isChef: () => chef);

    test('clients come from orders, grants and consultations', () async {
      final clients = await repo().myClients();
      final byName = {for (final c in clients) c.fullName: c};
      expect(
          byName.keys,
          containsAll([
            'Lan Phương',
            'Bảo Trâm',
            'Gia Hân',
            'Đức Huy',
            'Quốc Việt',
            'Hoàng Nam',
            'Thảo Vy',
            'Ngọc Trâm',
            'Minh Anh',
          ]));
      expect(byName['Gia Hân']!.status, ClientBucket.expiringSoon);
      expect(byName['Ngọc Trâm']!.status, ClientBucket.ended);
      expect(byName['Lan Phương']!.status, ClientBucket.active);
      expect(byName['Minh Anh']!.status, ClientBucket.active);
      expect(byName['Lan Phương']!.health!.allergies, ['peanut']);
      expect(byName['Minh Anh']!.lastSuggestion!.dishName,
          'Cháo yến mạch hạt sen táo đỏ');
      expect(
          (await repo().myClients(status: ClientBucket.ended)).single.fullName,
          'Ngọc Trâm');
      await expectLater(
          repo().client('u_nobody'),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 404)));
      await expectLater(
          repo(role: UserRole.user).myClients(),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
    });

    test(
        'a suggestion lands in the member\'s "Từ chuyên gia" and on the '
        'client card', () async {
      final sent = await suggestions().send(
        'u_me',
        SendChefSuggestionDto(
          name: 'Đậu hũ sốt nấm đông cô',
          calories: 480,
          ingredients: const ['Đậu hũ non', 'Nấm đông cô'],
          note: 'Bữa tối nhẹ.',
          slot: MealSlot.dinner,
          targetDate: DateTime(2026, 10, 17),
        ),
      );
      expect(sent.dishName, 'Đậu hũ sốt nấm đông cô');
      expect(sent.targetDate, DateTime(2026, 10, 17));

      // What Minh Anh's planner reads.
      final forMinhAnh =
          await MockMealPlannerRepository(userId: 'u_me').getChefSuggestions();
      final dto = forMinhAnh.first;
      expect(dto.chefName, 'Lê Quang Tâm');
      expect(dto.slot, 'dinner');
      final entity = dto.toEntity();
      expect(entity.recipe.name, 'Đậu hũ sốt nấm đông cô');
      expect(entity.recipe.allergens, contains('soy'));
      expect(entity.recipe.nutrition.calories, 480);
      expect(MockRecipeBook.findDetail(entity.recipe.id), isNotNull);

      final sentList = await suggestions().sentTo('u_me');
      expect(sentList.first.dishName, 'Đậu hũ sốt nấm đông cô');
      expect(sentList, hasLength(3)); // + the 2 seeds
      final me = await repo().client('u_me');
      expect(me.lastSuggestion!.dishName, 'Đậu hũ sốt nấm đông cô');
    });

    test('validation, #fail and the chef-only rule', () async {
      await expectLater(
          suggestions().send('u_me', const SendChefSuggestionDto(name: 'ab')),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 400)));
      await expectLater(
          suggestions().send('u_me',
              const SendChefSuggestionDto(name: 'Bún xào', calories: 10)),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 400)));
      await expectLater(
          suggestions()
              .send('u_me', const SendChefSuggestionDto(name: 'Bún #fail')),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
      await expectLater(
          suggestions(chef: false)
              .send('u_me', const SendChefSuggestionDto(name: 'Bún xào')),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
      expect(MockRecipeBook.chefSuggestions('u_me'), hasLength(2));
    });
  });

  group('screens', () {
    setUp(() {
      MockCommerceDb.reset();
      MockMealPlannerRepository.reset();
    });

    Future<void> pump(WidgetTester tester, Widget home,
        {Map<String, Object> session = _tam, double textScale = 1}) async {
      tester.view
        ..physicalSize = const Size(411, 913)
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
      await tester.pump(const Duration(seconds: 2)); // mock latency
    }

    Future<void> frames(WidgetTester tester, [int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('tabs with counts, search, type filter, empty states',
        (tester) async {
      await pump(tester, const ChefClientsScreen());
      expect(find.text('Đang dùng gói (7)'), findsOneWidget);
      expect(find.text('Sắp hết hạn (1)'), findsOneWidget);
      expect(find.text('Đã kết thúc (1)'), findsOneWidget);
      expect(find.text('Lan Phương'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'lan');
      await tester.pump();
      expect(find.text('Lan Phương'), findsOneWidget);
      expect(find.text('Đức Huy'), findsNothing);
      expect(find.text('Đang dùng gói (1)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      final vip = find.widgetWithText(ChoiceChip, 'Thực đơn VIP');
      await tester.ensureVisible(vip); // the chip row scrolls sideways
      await frames(tester, 2);
      await tester.tap(vip);
      await tester.pump();
      expect(find.text('Đang dùng gói (2)'),
          findsOneWidget); // Lan Phương, Bảo Trâm
      expect(find.text('Đức Huy'), findsNothing);

      await tester.tap(find.text('Sắp hết hạn (1)'));
      await frames(tester, 3);
      expect(find.text('Gia Hân'), findsOneWidget);
      expect(find.textContaining('còn 5 ngày'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(find.text('Không tìm thấy khách phù hợp'), findsOneWidget);
      await tester.tap(find.text('Xoá bộ lọc'));
      await tester.pump();
      expect(find.text('Gia Hân'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('large text: cards wrap instead of overflowing',
        (tester) async {
      await pump(tester, const ChefClientsScreen(), textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text('Đang dùng gói (7)'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a member sees "Chỉ dành cho chuyên gia"', (tester) async {
      await pump(tester, const ChefClientsScreen(), session: _minhAnh);
      expect(find.text('Chỉ dành cho chuyên gia'), findsOneWidget);
      expect(find.text('Lan Phương'), findsNothing);
    });

    testWidgets(
        'client detail: shared health summary, history, "Đề xuất món" → '
        'sent list', (tester) async {
      await pump(
          tester,
          const ChefClientDetailScreen(
              userId: 'u_lan_phuong', name: 'Lan Phương'));
      expect(find.text('Giảm cân'), findsOneWidget);
      expect(find.text('Đậu phộng'), findsOneWidget);
      expect(find.text('Thực đơn VIP 30 ngày cho gia đình'), findsOneWidget);
      expect(find.text('Gọi video'), findsOneWidget);
      expect(find.text('Xem lịch hẹn'), findsOneWidget);
      await tester.scrollUntilVisible(
          find.textContaining('Chưa đề xuất món nào'), 300,
          scrollable: find.byType(Scrollable).first);

      await tester.scrollUntilVisible(find.text('Đề xuất món'), -300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Đề xuất món'));
      await frames(tester);
      expect(find.text('Gửi cho Lan Phương'), findsOneWidget);
      expect(find.textContaining('Khách dị ứng: Đậu phộng'), findsOneWidget);

      // Validation first.
      await tester.ensureVisible(find.text('Gửi đề xuất'));
      await tester.tap(find.text('Gửi đề xuất'));
      await frames(tester, 3);
      expect(find.textContaining('Nhập tên món'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Tên món'),
          'Bún gạo lứt xào rau củ');
      await tester.enterText(
          find.widgetWithText(
              TextFormField, 'Năng lượng (kcal, không bắt buộc)'),
          '450');
      await tester.tap(find.text('Bữa tối'));
      await tester.pump();
      await tester.ensureVisible(find.text('Gửi đề xuất'));
      await tester.tap(find.text('Gửi đề xuất'));
      await tester.pump(const Duration(seconds: 2));
      await frames(tester);
      expect(find.textContaining('Đã gửi "Bún gạo lứt xào rau củ"'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('Bún gạo lứt xào rau củ'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Bún gạo lứt xào rau củ'), findsOneWidget);
      expect(MockRecipeBook.chefSuggestions('u_lan_phuong').first['slot'],
          'dinner');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('"Đề xuất món cho khách": VIP & consult first, then others',
        (tester) async {
      await pump(tester, const ChefSuggestionsScreen());
      expect(find.text('Thực đơn VIP & tư vấn'), findsOneWidget);
      expect(find.text('Lan Phương'), findsOneWidget);
      expect(find.text('Ngọc Trâm'), findsNothing, reason: 'package ended');
      await tester.scrollUntilVisible(
          find.text('Khách khác đang dùng gói'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Khách khác đang dùng gói'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
