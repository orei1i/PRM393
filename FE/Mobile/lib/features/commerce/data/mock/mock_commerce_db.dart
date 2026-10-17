// lib/features/commerce/data/mock/mock_commerce_db.dart
import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../booking/data/mock/mock_booking_db.dart';
import '../../../chef/data/mock/chef_mock_data.dart';
import '../../domain/commerce_status.dart';

/// Mock-only switch for the booking, wallet and chef-studio lists, so their
/// empty and error states can be seen on a device:
/// `flutter run --dart-define=MOCK_COMMERCE_SCENARIO=empty` (or `error`).
const _scenarioFromEnv =
    String.fromEnvironment('MOCK_COMMERCE_SCENARIO', defaultValue: 'normal');

ApiException mockError(int status, String message, [String? code]) =>
    ApiException(message: message, statusCode: status, code: code);

/// The `#fail` convention: any free-text field containing it gives a 503.
bool hasFailTrigger(String? text) =>
    text?.toLowerCase().contains('#fail') ?? false;

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

/// `chef_profiles` + the proposed booking prices
/// (`price_per_day`, `feedback_price_per_day`, `min_plan_days`,
/// `max_plan_days`, `accepting_bookings`).
class MockChefRow {
  MockChefRow.fromSeed(Map<String, dynamic> json)
      : id = json['id'] as String,
        userId = json['userId'] as String,
        fullName = json['fullName'] as String,
        email = json['email'] as String? ?? '',
        headline = json['headline'] as String,
        specialties = readStringList(json['specialties']),
        bio = json['bio'] as String,
        rating = readDouble(json['rating']),
        reviewCount = readInt(json['reviewCount']),
        yearsExperience = readInt(json['yearsExperience']),
        city = json['city'] as String,
        consultCount = readInt(json['consultCount']),
        certificates = readStringList(json['certificates']),
        pricePerDay = readInt(json['pricePerDay']),
        feedbackPricePerDay = readInt(json['feedbackPricePerDay']),
        minPlanDays = readInt(json['minPlanDays']),
        maxPlanDays = readInt(json['maxPlanDays']),
        acceptingBookings = json['acceptingBookings'] as bool? ?? true;

  MockChefRow.created(
      {required this.id,
      required this.userId,
      required this.fullName,
      required String specialty,
      required this.bio})
      : email = '',
        headline = 'Chuyên gia VeganLife',
        specialties = [specialty],
        rating = 0,
        reviewCount = 0,
        yearsExperience = 0,
        city = '',
        consultCount = 0,
        certificates = const [],
        pricePerDay = 120000,
        feedbackPricePerDay = 180000,
        minPlanDays = 3,
        maxPlanDays = 30,
        acceptingBookings = true;

  final String id;
  final String userId;
  String fullName;
  final String email;
  String headline;
  List<String> specialties;
  String bio;
  final double rating;
  final int reviewCount;
  final int yearsExperience;
  final String city;

  /// Finished bookings ("kế hoạch đã thiết kế").
  final int consultCount;
  final List<String> certificates;
  int pricePerDay;
  int feedbackPricePerDay;
  int minPlanDays;
  int maxPlanDays;
  bool acceptingBookings;

  /// The listed price per day for [dailyFeedback] or one-shot plans.
  int priceFor({required bool dailyFeedback}) =>
      dailyFeedback ? feedbackPricePerDay : pricePerDay;
}

/// `orders` with `booking_id` (the only order type left).
class MockOrderRow {
  MockOrderRow({
    required this.id,
    required this.userId,
    required this.buyerName,
    required this.bookingId,
    required this.chefId,
    required this.chefName,
    required this.amount,
    required this.createdAt,
    this.status = OrderStatus.pending,
  });

  final String id;
  final String userId;
  final String buyerName;
  final String bookingId;
  final String chefId;
  final String chefName;

  /// = contract price, a snapshot.
  final int amount;
  final DateTime createdAt;
  OrderStatus status;

  /// When the refund (full or partial) was sent back.
  DateTime? refundedAt;
}

class MockPaymentRow {
  MockPaymentRow({
    required this.id,
    required this.orderId,
    required this.transactionRef,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String orderId;
  final String transactionRef;
  final int amount;
  final DateTime createdAt;
  final DateTime expiresAt;
  PaymentStatus status = PaymentStatus.pending;
  DateTime? paidAt;
}

class MockDocRow {
  MockDocRow({
    required this.id,
    required this.chefId,
    required this.title,
    required this.fileUrl,
    required this.createdAt,
    this.status = 'Pending',
    this.reviewNote,
    this.chunkCount = 0,
  });

  final String id;
  final String chefId;
  final String title;
  final String fileUrl;
  final DateTime createdAt;

  /// `knowledge_docs.status` wire value.
  final String status;
  final String? reviewNote;
  final int chunkCount;
}

/// `bank_accounts` (proposed table): where a chef's withdrawals go.
class MockBankAccountRow {
  MockBankAccountRow({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.updatedAt,
  });

  String bankName;
  String accountNumber;
  String accountHolder;
  DateTime updatedAt;
}

/// `withdrawal_requests` (proposed table).
class MockWithdrawalRow {
  MockWithdrawalRow({
    required this.id,
    required this.chefId,
    required this.amount,
    required this.bankName,
    required this.accountNumber,
    required this.createdAt,
    this.status = 'Processing',
    this.autoApproveAt,
    this.processedAt,
    this.reason,
  });

  final String id;
  final String chefId;
  final int amount;
  final String bankName;
  final String accountNumber;
  final DateTime createdAt;

  /// `Processing` | `Completed` | `Rejected`.
  String status;

  /// Small withdrawals are paid out automatically at this time; null when
  /// an admin has to approve it.
  final DateTime? autoApproveAt;
  DateTime? processedAt;
  String? reason;
}

/// One static in-memory DB for chef profiles, booking orders and PaymentOS
/// payments, knowledge docs and wallets, plus the chef bookings themselves
/// ([bookingDb]). Shared by the chef directory, the booking flows (member
/// and chef), the payment screen and the chef wallet, so a booking Minh Anh
/// pays shows up for Tâm after switching accounts.
class MockCommerceDb {
  MockCommerceDb._();

  static MockCommerceDb? _instance;
  static MockCommerceDb get instance =>
      _instance ??= MockCommerceDb._().._seed();

  /// Mock clock (also `MockBookingDb.clock`). Tests move it forward instead
  /// of waiting (`#expire`, releaseAt).
  static DateTime Function() clock = DateTime.now;

  /// `normal` | `empty` | `error`, see [_scenarioFromEnv].
  static String scenario = _scenarioFromEnv;

  /// Fresh seeds — profiles, orders, bookings, wallets — seeded against
  /// [clock] on next use.
  @visibleForTesting
  static void reset({DateTime Function()? clock}) {
    MockCommerceDb.clock = clock ?? DateTime.now;
    scenario = _scenarioFromEnv;
    _instance = null;
  }

  /// For list endpoints: throws in the `error` scenario, true for `empty`.
  static bool emptyScenario() {
    if (scenario == 'error') {
      throw mockError(503, 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.');
    }
    return scenario == 'empty';
  }

  static const paymentTtl = Duration(minutes: 15);

  /// `#expire` in the booking needs.
  static const fastExpiryTtl = Duration(seconds: 30);

  final chefs = <MockChefRow>[];
  final orders = <MockOrderRow>[];
  final payments = <MockPaymentRow>[];
  final docs = <MockDocRow>[];

  /// Chef wallet: keyed by chef profile id.
  final bankAccounts = <String, MockBankAccountRow>{};
  final withdrawals = <MockWithdrawalRow>[];

  /// Chef meal-plan bookings, seeded with this DB.
  late final MockBookingDb bookingDb;

  int _ids = 1000;
  int _refSeq = 0;

  DateTime get now => clock();

  String newId(String prefix) => '${prefix}_${++_ids}';

  /// `VL` + yyMMdd + 4-digit sequence.
  String nextRef(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    final seq = (++_refSeq).toString().padLeft(4, '0');
    return 'VL${two(at.year % 100)}${two(at.month)}${two(at.day)}$seq';
  }

  // ---- lookups ------------------------------------------------------------

  MockChefRow chef(String id) => chefs.firstWhere((c) => c.id == id,
      orElse: () => throw mockError(404, 'Chuyên gia không còn hoạt động.'));

  MockChefRow? chefOfUser(String userId) =>
      chefs.where((c) => c.userId == userId).firstOrNull;

  MockOrderRow order(String id) => orders.firstWhere((o) => o.id == id,
      orElse: () => throw mockError(404, 'Không tìm thấy đơn hàng.'));

  MockPaymentRow payment(String id) => payments.firstWhere((p) => p.id == id,
      orElse: () => throw mockError(404, 'Không tìm thấy giao dịch.'));

  /// Latest payment attempt, expired lazily (the real BE does it on read or
  /// in a job).
  MockPaymentRow? latestPayment(String orderId) {
    final p = payments.where((p) => p.orderId == orderId).lastOrNull;
    if (p != null) expireIfDue(p);
    return p;
  }

  /// The attempt that was paid, if any.
  MockPaymentRow? paidPayment(String orderId) => payments
      .where((p) => p.orderId == orderId && p.paidAt != null)
      .firstOrNull;

  void expireIfDue(MockPaymentRow p) {
    if (p.status == PaymentStatus.pending && !now.isBefore(p.expiresAt)) {
      p.status = PaymentStatus.expired;
    }
  }

  // ---- state changes ------------------------------------------------------

  MockPaymentRow openPayment(MockOrderRow order, {Duration ttl = paymentTtl}) {
    final created = now;
    final p = MockPaymentRow(
      id: newId('pay'),
      orderId: order.id,
      transactionRef: nextRef(created),
      amount: order.amount,
      createdAt: created,
      expiresAt: created.add(ttl),
    );
    payments.add(p);
    return p;
  }

  /// PaymentOS confirmed (the webhook, on the real BE): the order is Paid
  /// and its booking's money goes into escrow in the same step.
  void markPaid(MockPaymentRow p) {
    final o = order(p.orderId);
    p
      ..status = PaymentStatus.paid
      ..paidAt = now;
    o.status = OrderStatus.paid;
    bookingDb.onOrderPaid(o, p);
  }

  /// Refund through PaymentOS to the original payment method: the whole
  /// amount, or [amount] of it (a Split decision).
  void refund(MockOrderRow o, {int? amount}) {
    final partial = amount != null && amount < o.amount;
    o
      ..status = partial ? OrderStatus.partiallyRefunded : OrderStatus.refunded
      ..refundedAt = now;
    if (!partial) {
      for (final p in payments.where((p) => p.orderId == o.id)) {
        if (p.status == PaymentStatus.paid) p.status = PaymentStatus.refunded;
      }
    }
  }

  /// An unpaid order: the QR stops working.
  void cancelUnpaid(MockOrderRow o) {
    if (o.status != OrderStatus.pending) return;
    o.status = OrderStatus.cancelled;
    for (final p in payments.where((p) => p.orderId == o.id)) {
      if (p.status == PaymentStatus.pending) p.status = PaymentStatus.expired;
    }
  }

  /// The auto payout of a small withdrawal happens lazily on read.
  void settleWithdrawal(MockWithdrawalRow w) {
    final at = w.autoApproveAt;
    if (w.status == 'Processing' && at != null && !now.isBefore(at)) {
      w
        ..status = 'Completed'
        ..processedAt = at;
    }
  }

  // ---- wire JSON ----------------------------------------------------------

  Map<String, dynamic> chefJson(MockChefRow c, {required bool detail}) => {
        'id': c.id,
        'userId': c.userId,
        'fullName': c.fullName,
        'headline': c.headline,
        'specialties': c.specialties,
        'rating': c.rating,
        'reviewCount': c.reviewCount,
        'yearsExperience': c.yearsExperience,
        'city': c.city,
        'consultCount': c.consultCount,
        'pricePerDay': c.pricePerDay,
        'feedbackPricePerDay': c.feedbackPricePerDay,
        'minPlanDays': c.minPlanDays,
        'maxPlanDays': c.maxPlanDays,
        'acceptingBookings': c.acceptingBookings,
        if (detail) ...{
          'bio': c.bio,
          'certificates': c.certificates,
        },
      };

  Map<String, dynamic> paymentJson(MockPaymentRow p) {
    expireIfDue(p);
    return {
      'id': p.id,
      'orderId': p.orderId,
      'provider': 'PaymentOS',
      'transactionRef': p.transactionRef,
      'qrCodeUrl': 'https://pay.veganlife.vn/mock/qr/${p.transactionRef}.png',
      'status': p.status.apiValue,
      'paidAt': _iso(p.paidAt),
      'amount': p.amount,
      'expiresAt': _iso(p.expiresAt),
      'createdAt': _iso(p.createdAt),
    };
  }

  Map<String, dynamic> orderJson(MockOrderRow o) {
    bookingDb.settle();
    final payment = latestPayment(o.id);
    final booking = bookingDb.find(o.bookingId);
    return {
      'id': o.id,
      'userId': o.userId,
      'bookingId': o.bookingId,
      'amount': o.amount,
      'status': o.status.apiValue,
      'createdAt': _iso(o.createdAt),
      'booking': booking == null
          ? {'id': o.bookingId, 'chefId': o.chefId, 'chefName': o.chefName}
          : bookingDb.orderBookingJson(booking),
      'payment': payment == null ? null : paymentJson(payment),
      'escrow': booking?.escrow?.toJson(),
    };
  }

  // ---- seeds --------------------------------------------------------------

  void _seed() {
    for (final json in seedChefs) {
      chefs.add(MockChefRow.fromSeed(json));
    }
    final now = this.now;

    // Tâm's wallet: bank account and withdrawals (same ids and amounts as
    // the web console, FE/Web src/lib/mock_payouts.ts). wd_tam_3 is above
    // the 5.000.000đ auto-approve limit, so it waits for an admin and keeps
    // "Có thể rút" at 110.000đ.
    bankAccounts['u_chef_tam'] = MockBankAccountRow(
      bankName: 'Vietcombank',
      accountNumber: '0071000456789',
      accountHolder: 'LE QUANG TAM',
      updatedAt: now.subtract(const Duration(days: 45)),
    );
    withdrawals.addAll([
      MockWithdrawalRow(
        id: 'wd_tam_1',
        chefId: 'u_chef_tam',
        amount: 2000000,
        bankName: 'Vietcombank',
        accountNumber: '0071000456789',
        createdAt: now.subtract(const Duration(days: 30)),
        status: 'Rejected',
        processedAt: now.subtract(const Duration(days: 29)),
        reason: 'Số dư có thể rút lúc gửi yêu cầu chưa đủ 2.000.000đ.',
      ),
      MockWithdrawalRow(
        id: 'wd_tam_2',
        chefId: 'u_chef_tam',
        amount: 1000000,
        bankName: 'Vietcombank',
        accountNumber: '0071000456789',
        createdAt: now.subtract(const Duration(days: 17)),
        status: 'Completed',
        processedAt: now.subtract(const Duration(days: 16, hours: 22)),
      ),
      MockWithdrawalRow(
        id: 'wd_tam_3',
        chefId: 'u_chef_tam',
        amount: 5100000,
        bankName: 'Vietcombank',
        accountNumber: '0071000456789',
        createdAt: now.subtract(const Duration(hours: 3, minutes: 12)),
        reason: 'Trên 5.000.000đ: chờ Ban quản trị duyệt (1–2 ngày làm việc).',
      ),
    ]);

    // Tâm's knowledge docs.
    docs.addAll([
      MockDocRow(
        id: 'kd_tam_protein',
        chefId: 'u_chef_tam',
        title: 'Bữa sáng chay đủ đạm cho người tập',
        fileUrl: 'https://files.veganlife.vn/mock/bua-sang-chay-du-dam.pdf',
        createdAt: now.subtract(const Duration(days: 21)),
        status: 'Approved',
        chunkCount: 18,
      ),
      MockDocRow(
        id: 'kd_tam_mealprep',
        chefId: 'u_chef_tam',
        title: 'Bảo quản đồ ăn meal prep chay trong 5 ngày',
        fileUrl: 'https://files.veganlife.vn/mock/bao-quan-meal-prep.pdf',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      MockDocRow(
        id: 'kd_tam_detox',
        chefId: 'u_chef_tam',
        title: 'Nước ép rau củ thay bữa tối để thải độc',
        fileUrl: 'https://files.veganlife.vn/mock/nuoc-ep-thai-doc.pdf',
        createdAt: now.subtract(const Duration(days: 9)),
        status: 'Rejected',
        reviewNote:
            'Tài liệu khẳng định "thải độc" nhưng chưa có nguồn y khoa. Vui lòng bổ sung nguồn hoặc bỏ phần này.',
      ),
    ]);

    // Bookings last: their seed orders and payments land in [orders] and
    // [payments].
    bookingDb = MockBookingDb.attach(this)..seed();
  }
}
