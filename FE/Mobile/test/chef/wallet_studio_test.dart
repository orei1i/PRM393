// test/chef/wallet_studio_test.dart
// Chef wallet on escrow holds, "Hồ sơ & bảng giá", knowledge docs and the
// public chef DTO. The mock repositories wait like a network.
@Timeout(Duration(seconds: 120))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/user_role.dart';
import 'package:veganlife_mobile/features/chef/data/mock_chef_repository.dart';
import 'package:veganlife_mobile/features/chef/data/models/chef_model.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_studio_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/mock_chef_wallet_repository.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/chef_studio_models.dart';
import 'package:veganlife_mobile/features/chef_studio/data/models/wallet_models.dart';
import 'package:veganlife_mobile/features/chef_studio/domain/wallet_rules.dart';
import 'package:veganlife_mobile/features/commerce/data/mock/mock_commerce_db.dart';

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
  final wallet = MockChefWalletRepository(
      currentUserId: () => userId, currentRole: () => role);
  final chefs = MockChefRepository();

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 3);
    MockCommerceDb.reset(clock: () => now);
    userId = 'u_chef_tam';
    role = UserRole.chef;
  });

  group('wallet (escrow)', () {
    test('Tâm: 110.000đ available, 1.134.000đ held, 945.000đ frozen', () async {
      expect(kPlatformFeeRate, 0.10);
      expect(kEscrowHoldDays, 3);
      final w = await wallet.getWallet();
      // Released: b_ma_tam_done 900.000 + b_han_tam_done 6.000.000 → net
      // 6.210.000, minus 1.000.000 withdrawn and 5.100.000 processing.
      expect(w.available, 110000);
      expect(w.pending, 1134000, reason: 'Thảo Vy, until plan end + 3 days');
      expect(w.frozen, 945000, reason: 'Ngọc Trâm, cp_tram_tam');
      expect(w.withdrawn, 1000000);
      expect(w.processing, 5100000);
      expect(w.holdDays, 3);
      expect(w.bankAccount!.masked, '•••• 6789');
    });

    test('ledger: one row per booking following its hold, withdrawals',
        () async {
      final all = await wallet.transactions();
      final vy = all.singleWhere((t) => t.id == 'tx_in_b_vy_tam_active');
      expect(vy.status, LedgerStatus.held);
      expect((vy.gross, vy.fee, vy.net), (1260000, 126000, 1134000));
      expect(vy.planTitle, 'Thực đơn 7 ngày · Có phản hồi mỗi ngày');
      expect(vy.memberName, 'Thảo Vy');
      expect(vy.bookingId, 'b_vy_tam_active');
      expect(vy.orderId, 'ord_603');
      expect(vy.transactionRef, startsWith('VL'));
      // 21/10 23:59 VN + 3 days.
      expect(vy.releaseAt!.toUtc(), DateTime.utc(2026, 10, 24, 16, 59));
      final tram = all.singleWhere((t) => t.id == 'tx_in_b_tram_tam');
      expect(tram.status, LedgerStatus.frozen);
      expect(tram.complaintId, 'cp_tram_tam');
      expect(tram.releaseAt, isNull);
      final han = all.singleWhere((t) => t.id == 'tx_in_b_han_tam_done');
      expect(han.status, LedgerStatus.available);
      expect(han.net, 5400000);
      final rejected = all.singleWhere((t) => t.id == 'tx_wd_wd_tam_1');
      expect(rejected.status, LedgerStatus.rejected);
      expect(rejected.net, -2000000);
      expect(all.singleWhere((t) => t.id == 'tx_wd_wd_tam_3').status,
          LedgerStatus.processing,
          reason: 'above 5.000.000đ: waits for an admin');

      final october = await wallet.transactions(month: '2026-10');
      expect(october.every((t) => t.createdAt.month == 10), isTrue);
      expect(october.map((t) => t.id), isNot(contains('tx_in_b_han_tam_done')),
          reason: 'released in September');
    });

    test('withdrawals: minimum, balance, auto payout, no bank account',
        () async {
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 50000)),
          throwsA(apiError(400)));
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 200000)),
          throwsA(apiError(409, 'insufficient_balance')));
      await expectLater(
          wallet.saveBankAccount(const BankAccountDto(
              bankName: 'ACB',
              accountNumber: '123456789',
              accountHolder: 'LE QUANG TAM #fail')),
          throwsA(apiError(503)));
      final small = await wallet
          .requestWithdrawal(const WithdrawalRequestDto(amount: 100000));
      expect(small.status, LedgerStatus.processing);
      expect(small.accountNumber, '•••• 6789');
      now = now.add(const Duration(seconds: 11));
      final list = await wallet.withdrawals();
      expect(list.singleWhere((x) => x.id == small.id).status,
          LedgerStatus.completed);
      final w = await wallet.getWallet();
      expect(w.available, 10000);
      expect(w.withdrawn, 1100000);

      MockCommerceDb.instance.bankAccounts.remove('u_chef_tam');
      await expectLater(
          wallet.requestWithdrawal(const WithdrawalRequestDto(amount: 100000)),
          throwsA(apiError(409, 'no_bank_account')));
    });

    test('members cannot open a wallet', () async {
      userId = 'u_me';
      role = UserRole.user;
      await expectLater(wallet.getWallet(), throwsA(apiError(403)));
    });

    test('legacy wire values still read (Pending, serviceTitle, buyerName)',
        () {
      final t = WalletTransactionDto.fromJson({
        'id': 'tx_1',
        'type': 'Income',
        'status': 'Pending',
        'serviceTitle': 'Thực đơn 5 ngày',
        'buyerName': 'Minh Anh',
        'net': 315000,
        'createdAt': '2026-10-10T03:00:00Z',
      });
      expect(t.status, LedgerStatus.held);
      expect(t.planTitle, 'Thực đơn 5 ngày');
      expect(t.memberName, 'Minh Anh');
      expect(LedgerStatus.fromApi('Frozen').label, 'Tạm giữ do khiếu nại');
    });
  });

  group('Hồ sơ & bảng giá', () {
    const bio =
        'Bếp trưởng chay 15 năm, chuyên meal prep cho gia đình bận rộn: nấu một lần, ăn cả tuần.';

    test('a non-chef gets 403', () async {
      userId = 'u_me';
      role = UserRole.user;
      await expectLater(
          studio.getMyProfile(), throwsA(apiError(403, 'not_chef')));
      await expectLater(studio.myKnowledgeDocs(), throwsA(apiError(403)));
    });

    test('prices and the "Đang nhận yêu cầu" switch reach the public profile',
        () async {
      final before = await studio.getMyProfile();
      expect(before.specialty, 'Ẩm thực chay Việt');
      expect(before.pricePerDay, 150000);
      expect(before.feedbackPricePerDay, 180000);
      await expectLater(
          studio.updateMyProfile(const ChefProfileRequestDto(
              specialty: 'Meal prep', bio: bio, pricePerDay: 10000)),
          throwsA(apiError(400)));
      await expectLater(
          studio.updateMyProfile(const ChefProfileRequestDto(
              specialty: 'Meal prep',
              bio: bio,
              minPlanDays: 10,
              maxPlanDays: 5)),
          throwsA(apiError(400)));
      final after = await studio.updateMyProfile(const ChefProfileRequestDto(
        specialty: 'Meal prep',
        bio: bio,
        pricePerDay: 130000,
        feedbackPricePerDay: 200000,
        minPlanDays: 5,
        maxPlanDays: 14,
        acceptingBookings: false,
      ));
      expect(after.acceptingBookings, isFalse);
      final public = (await chefs.getChef('u_chef_tam')).toEntity();
      expect(public.specialties, ['Meal prep']);
      expect(public.bio, bio);
      expect(public.pricePerDay, 130000);
      expect(public.feedbackPricePerDay, 200000);
      expect((public.minPlanDays, public.maxPlanDays), (5, 14));
      expect(public.acceptingBookings, isFalse);
      expect(public.startingPriceVnd, 130000);
    });

    test('a chef without a profile gets 404, and saving creates one', () async {
      userId = 'u_new_chef';
      await expectLater(studio.getMyProfile(),
          throwsA(apiError(404, 'chef_profile_missing')));
      final created = await studio.updateMyProfile(
          const ChefProfileRequestDto(specialty: 'Bếp chay cho bé', bio: bio));
      expect(created.userId, 'u_new_chef');
      expect(created.pricePerDay, 120000);
      expect((await chefs.listChefs()).map((c) => c.userId),
          contains('u_new_chef'));
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
      expect((await studio.myKnowledgeDocs()).first.id, doc.id);
    });
  });

  test('ChefDto: single SQL specialty, booking prices, legacy fields ignored',
      () {
    final chef = ChefDto.fromJson({
      'id': 3,
      'userId': 12,
      'name': 'Phạm Thu Hà',
      'specialty': 'Dinh dưỡng lâm sàng',
      'rating': 4.8,
      'pricePerDay': 120000,
      'feedbackPricePerDay': 180000,
      'minPlanDays': 3,
      'maxPlanDays': 30,
      // Legacy, ignored now.
      'services': [
        {'id': 12, 'title': 'Tư vấn nhanh', 'type': 'Consult', 'price': 1},
      ],
      'availableSlots': ['2026-10-20T12:30:00Z'],
      'startingPriceVnd': 1,
    }).toEntity();
    expect(chef.id, '3');
    expect(chef.userId, '12');
    expect(chef.name, 'Phạm Thu Hà');
    expect(chef.specialties, ['Dinh dưỡng lâm sàng']);
    expect(chef.startingPriceVnd, 120000);
    expect(chef.priceFor(dailyFeedback: true), 180000);
    expect(chef.acceptingBookings, isTrue, reason: 'default when missing');

    final bare = ChefDto.fromJson({'id': 'x', 'pricePerDay': 150000});
    expect(bare.feedbackPricePerDay, 150000);
    expect((bare.minPlanDays, bare.maxPlanDays), (3, 30));
  });
}
