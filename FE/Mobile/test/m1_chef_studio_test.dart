// test/m1_chef_studio_test.dart
// The mock repository waits like a network (0.5–1 s per call).
@Timeout(Duration(seconds: 90))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/chef/data/mock_chef_repository.dart';
import 'package:veganlife_mobile/features/chef/data/models/service_model.dart';
import 'package:veganlife_mobile/features/chef/domain/entities/chef.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_studio_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_wallet_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/chef_studio_models.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/chef_studio/domain/wallet_rules.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';
import 'package:veganlife_mobile/features/commerce/domain/commerce_status.dart';

Matcher apiError(int status, [String? code]) => isA<ApiException>()
    .having((e) => e.statusCode, 'statusCode', status)
    .having((e) => e.code, 'code', code ?? anything);

void main() {
  late DateTime now;
  var userId = 'u_chef_tam';
  var role = UserRole.chef;
  final studio = MockChefStudioRepository(
    currentUserId: () => userId,
    currentUserName: () => 'Lê Quang Tâm',
    currentRole: () => role,
  );
  final chefs = MockChefRepository();

  setUp(() {
    now = DateTime(2026, 10, 15, 9);
    MockCommerceDb.reset(clock: () => now);
    userId = 'u_chef_tam';
    role = UserRole.chef;
  });

  const consult = ServiceRequestDto(
    title: 'Tư vấn ăn chay cho người tập gym',
    type: ServiceType.consult,
    price: 400000,
    durationMinutes: 45,
    description: 'Gọi video 45 phút.',
  );

  test('a non-chef gets 403 everywhere', () async {
    userId = 'u_me';
    role = UserRole.user;
    await expectLater(studio.myServices(), throwsA(apiError(403, 'not_chef')));
    await expectLater(studio.getMyProfile(), throwsA(apiError(403)));
    await expectLater(studio.createService(consult), throwsA(apiError(403)));
  });

  test('service CRUD: validation, public profile, delete rules', () async {
    await expectLater(
        studio.createService(const ServiceRequestDto(
            title: 'Ngắn',
            type: ServiceType.consult,
            price: 400000,
            durationMinutes: 45)),
        throwsA(apiError(400, 'validation')));
    await expectLater(
        studio.createService(const ServiceRequestDto(
            title: 'Khoá học không có link',
            type: ServiceType.course,
            price: 500000)),
        throwsA(apiError(400)));
    await expectLater(
        studio.createService(const ServiceRequestDto(
            title: 'Giá quá thấp cho buổi tư vấn',
            type: ServiceType.consult,
            price: 1000,
            durationMinutes: 45)),
        throwsA(apiError(400)));
    await expectLater(
        studio.createService(const ServiceRequestDto(
            title: 'Dịch vụ #fail',
            type: ServiceType.consult,
            price: 400000,
            durationMinutes: 45)),
        throwsA(apiError(503)));

    final created = await studio.createService(consult);
    expect(created.type, ServiceType.consult);
    expect((await studio.myServices()).map((s) => s.id), contains(created.id));
    final public = await chefs.getChef('u_chef_tam');
    expect(public.services.map((s) => s.title), contains(consult.title));

    final updated = await studio.updateService(
        created.id,
        const ServiceRequestDto(
            title: 'Tư vấn ăn chay cho người tập gym (mới)',
            type: ServiceType.consult,
            price: 450000,
            durationMinutes: 60));
    expect(updated.price, 450000);

    await expectLater(studio.deleteService('svc_tam_course'),
        throwsA(apiError(409, 'service_has_orders')));
    await studio.deleteService(created.id);
    expect((await studio.myServices()).map((s) => s.id),
        isNot(contains(created.id)));
  });

  test('confirm / decline / start / complete transitions and errors', () async {
    final list = await studio.myConsultations();
    expect(list.map((c) => c.status),
        isNot(contains(ConsultationStatus.awaitingPayment)),
        reason: 'unpaid holds stay with the buyer');
    final nam = list.singleWhere((c) => c.id == 'cs_tam_nam');
    final vy = list.singleWhere((c) => c.id == 'cs_tam_vy');
    expect(nam.status, ConsultationStatus.pending);
    expect(vy.status, ConsultationStatus.confirmed);
    expect(vy.startAt.difference(now).inMinutes, 10);

    expect((await studio.confirmConsultation(nam.id)).status,
        ConsultationStatus.confirmed);
    await expectLater(studio.confirmConsultation(nam.id),
        throwsA(apiError(409, 'invalid_status')));
    await expectLater(
        studio.startConsultation(nam.id), throwsA(apiError(409, 'too_early')));
    await expectLater(
        studio.declineConsultation(nam.id, 'Không còn rảnh hôm đó'),
        throwsA(apiError(409, 'invalid_status')),
        reason: 'only pending requests are declined');

    final started = await studio.startConsultation(vy.id);
    expect(started.status, ConsultationStatus.inProgress);
    expect(started.startedAt, isNotNull);
    await expectLater(
        studio.completeConsultation(vy.id, 'Quá ngắn'), throwsA(apiError(400)));
    await expectLater(
        studio.completeConsultation(
            vy.id, 'Ghi chú đủ dài nhưng có #fail ở đây'),
        throwsA(apiError(503)));
    const notes = 'Ăn thêm đậu gà buổi chiều, uống đủ 2 lít nước mỗi ngày.';
    final done = await studio.completeConsultation(vy.id, notes);
    expect(done.status, ConsultationStatus.completed);
    expect(done.chefNotes, notes);
    expect(done.completedAt, now);
  });

  test('orders for my services include buyers; seeds for the dashboard',
      () async {
    final orders = await studio.myOrders();
    expect(orders.every((o) => o.service.chefId == 'u_chef_tam'), isTrue);
    final sold = orders.where(
        (o) => o.type == ServiceType.course && o.status == OrderStatus.paid);
    expect(sold.map((o) => o.buyer!.fullName),
        containsAll(['Đức Huy', 'Minh Anh']));
    expect(
        sold.every((o) => o.accessGrant!.status == GrantStatus.active), isTrue);
    final docs = await studio.myKnowledgeDocs();
    expect(
        docs.map((d) => d.status).toSet(), KnowledgeDocStatus.values.toSet());
    expect(
        docs
            .singleWhere((d) => d.status == KnowledgeDocStatus.approved)
            .chunkCount,
        18);
  });

  test('knowledge doc submission defaults and errors', () async {
    await expectLater(
        studio.submitKnowledgeDoc(const KnowledgeDocRequestDto(
            title: 'Tài liệu #fail kiểm thử',
            fileUrl: 'https://files.veganlife.vn/mock/a.pdf')),
        throwsA(apiError(503)));
    await expectLater(
        studio.submitKnowledgeDoc(const KnowledgeDocRequestDto(
            title: 'Đậu và hạt cho bữa sáng', fileUrl: 'http://x.vn/a.pdf')),
        throwsA(apiError(400)));
    final doc = await studio.submitKnowledgeDoc(const KnowledgeDocRequestDto(
        title: 'Đậu và hạt cho bữa sáng',
        fileUrl: 'https://files.veganlife.vn/mock/dau-hat.pdf'));
    expect(doc.status, KnowledgeDocStatus.pending);
    expect(doc.source, 'Chef');
    expect(doc.chunkCount, 0);
    expect((await studio.myKnowledgeDocs()).first.id, doc.id);
  });

  test('profile edit updates the public chef profile', () async {
    final before = await studio.getMyProfile();
    expect(before.specialty, 'Ẩm thực chay Việt');
    await expectLater(
        studio.updateMyProfile(const ChefProfileRequestDto(
            specialty: 'Meal prep', bio: 'Quá ngắn')),
        throwsA(apiError(400)));
    const bio =
        'Bếp trưởng chay 15 năm, chuyên meal prep cho gia đình bận rộn: nấu một lần, ăn cả tuần.';
    final after = await studio.updateMyProfile(
        const ChefProfileRequestDto(specialty: 'Meal prep', bio: bio));
    expect(after.specialty, 'Meal prep');
    final public = await chefs.getChef('u_chef_tam');
    expect(public.specialties, ['Meal prep']);
    expect(public.bio, bio);
  });

  test('a chef without a profile gets 404, and saving creates one', () async {
    userId = 'u_new_chef';
    await expectLater(
        studio.getMyProfile(), throwsA(apiError(404, 'chef_profile_missing')));
    await expectLater(studio.myServices(), throwsA(apiError(404)));
    const bio =
        'Đầu bếp chay tại gia, chia sẻ món ăn dặm và bữa trưa văn phòng đủ chất.';
    final created = await studio.updateMyProfile(
        const ChefProfileRequestDto(specialty: 'Bếp chay cho bé', bio: bio));
    expect(created.userId, 'u_new_chef');
    expect(await studio.myServices(), isEmpty);
  });

  group('wallet', () {
    final wallet = MockChefWalletRepository(
        currentUserId: () => userId, currentRole: () => role);

    test('balance matches the seeded orders minus the 10% fee', () async {
      expect(kPlatformFeeRate, 0.10);
      expect(platformFee(350000), 35000);
      final w = await wallet.getWallet();
      // Released: 2 completed consults, 2 courses and 3 VIP menus past the
      // 7-day hold; pending: 2 paid consults and a 5-day-old course.
      expect(w.available, 6462000 - 1000000);
      expect(w.pending, 315000 + 315000 + 891000);
      expect(w.withdrawn, 1000000);
      expect(w.processing, 0);
      expect(w.bankAccount!.masked, '•••• 6789');
    });

    test('ledger: income with gross / fee / net, withdrawals, month filter',
        () async {
      final all = await wallet.transactions();
      final tram = all.singleWhere((t) => t.id == 'tx_in_od_tam_tram');
      expect(tram.type, WalletEntryType.income);
      expect((tram.gross, tram.fee, tram.net), (350000, 35000, 315000));
      expect(tram.status, LedgerStatus.available);
      expect(tram.transactionRef, startsWith('VL'));
      expect(all.singleWhere((t) => t.id == 'tx_in_od_tam_huy').status,
          LedgerStatus.pending,
          reason: 'course still in its hold period');
      expect(
          all.map((t) => t.serviceTitle).toSet(),
          containsAll([
            'Tư vấn thực đơn gia đình 7 ngày',
            'Khoá meal prep chay 4 tuần',
            'Thực đơn VIP 30 ngày cho gia đình',
          ]));
      final rejected = all.singleWhere((t) => t.id == 'tx_wd_wd_tam_1');
      expect(rejected.status, LedgerStatus.rejected);
      expect(rejected.note, isNotNull);
      expect(rejected.net, -2000000);

      final october = await wallet.transactions(month: '2026-10');
      expect(october, isNotEmpty);
      expect(october.every((t) => t.createdAt.month == 10), isTrue);
      expect(
          october.map((t) => t.id), isNot(contains('tx_in_od_tam_course_viet')),
          reason: 'paid in September');
    });

    test('a decline reverses pending income; completing releases it', () async {
      final before = await wallet.getWallet();
      await studio.declineConsultation('cs_tam_nam', 'Hôm đó tôi đi công tác.');
      final ledger = await wallet.transactions();
      expect(ledger.singleWhere((t) => t.id == 'tx_in_od_tam_nam').status,
          LedgerStatus.reversed);
      final reversal = ledger.singleWhere((t) => t.id == 'tx_rf_od_tam_nam');
      expect(reversal.type, WalletEntryType.refund);
      expect(reversal.net, -315000);

      await studio.startConsultation('cs_tam_vy');
      await studio.completeConsultation(
          'cs_tam_vy', 'Ăn thêm đậu gà buổi chiều, uống đủ nước mỗi ngày.');
      final after = await wallet.getWallet();
      expect(after.pending, before.pending - 315000 - 315000);
      expect(after.available, before.available + 315000);
    });

    test('withdrawals: limits, admin hold above 5M, auto payout, #fail',
        () async {
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 50000)),
          throwsA(apiError(400)));
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 9000000)),
          throwsA(apiError(409, 'insufficient_balance')));
      await expectLater(
          wallet.saveBankAccount(const BankAccountDto(
              bankName: 'ACB',
              accountNumber: '123456789',
              accountHolder: 'LE QUANG TAM #fail')),
          throwsA(apiError(503)));

      final held = await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 5100000));
      expect(held.status, LedgerStatus.processing);
      expect(held.reason, contains('Ban quản trị'));
      expect(held.accountNumber, '•••• 6789');
      var w = await wallet.getWallet();
      expect(w.available, 5462000 - 5100000);
      expect(w.processing, 5100000);

      final small = await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 300000));
      expect(small.status, LedgerStatus.processing);
      now = now.add(const Duration(seconds: 11));
      final list = await wallet.withdrawals();
      expect(list.singleWhere((x) => x.id == small.id).status,
          LedgerStatus.completed);
      expect(list.singleWhere((x) => x.id == held.id).status,
          LedgerStatus.processing,
          reason: 'waits for an admin');
      w = await wallet.getWallet();
      expect(w.withdrawn, 1000000 + 300000);
      expect(w.available, 62000);

      MockCommerceDb.instance.bankAccounts.remove('u_chef_tam');
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 50000)),
          throwsA(apiError(409, 'no_bank_account')));
    });

    test('members cannot open a wallet', () async {
      userId = 'u_me';
      role = UserRole.user;
      await expectLater(wallet.getWallet(), throwsA(apiError(403)));
    });
  });
}
