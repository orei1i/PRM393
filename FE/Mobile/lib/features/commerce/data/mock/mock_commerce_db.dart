// lib/features/commerce/data/mock/mock_commerce_db.dart
import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../chef/data/mock/chef_mock_data.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../domain/commerce_status.dart';

/// Mock-only switch for the commerce and chef-studio lists, so their empty
/// and error states can be seen on a device:
/// `flutter run --dart-define=MOCK_COMMERCE_SCENARIO=empty` (or `error`).
const _scenarioFromEnv =
    String.fromEnvironment('MOCK_COMMERCE_SCENARIO', defaultValue: 'normal');

ApiException mockError(int status, String message, [String? code]) =>
    ApiException(message: message, statusCode: status, code: code);

/// The `#fail` convention: any free-text field containing it gives a 503.
bool hasFailTrigger(String? text) =>
    text?.toLowerCase().contains('#fail') ?? false;

String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

class MockChefRow {
  MockChefRow.fromSeed(Map<String, dynamic> json)
      : id = json['id'] as String,
        userId = json['userId'] as String,
        fullName = json['fullName'] as String,
        headline = json['headline'] as String,
        specialties = readStringList(json['specialties']),
        bio = json['bio'] as String,
        rating = readDouble(json['rating']),
        reviewCount = readInt(json['reviewCount']),
        yearsExperience = readInt(json['yearsExperience']),
        city = json['city'] as String,
        consultCount = readInt(json['consultCount']),
        certificates = readStringList(json['certificates']);

  MockChefRow.created(
      {required this.id,
      required this.userId,
      required this.fullName,
      required String specialty,
      required this.bio})
      : headline = 'Chuyên gia VeganLife',
        specialties = [specialty],
        rating = 0,
        reviewCount = 0,
        yearsExperience = 0,
        city = '',
        consultCount = 0,
        certificates = const [];

  final String id;
  final String userId;
  String fullName;
  String headline;
  List<String> specialties;
  String bio;
  final double rating;
  final int reviewCount;
  final int yearsExperience;
  final String city;
  final int consultCount;
  final List<String> certificates;
}

class MockServiceRow {
  MockServiceRow({
    required this.id,
    required this.chefId,
    required this.title,
    required this.type,
    required this.price,
    this.description = '',
    this.durationMinutes,
    this.contentUrl,
  });

  final String id;
  final String chefId;
  String title;
  ServiceType type;
  int price;
  String description;
  int? durationMinutes;
  String? contentUrl;

  /// [contentUrl] only goes to the owner (buyers get it from /content).
  Map<String, dynamic> toJson({bool withContentUrl = false}) => {
        'id': id,
        'chefId': chefId,
        'title': title,
        'type': type.apiValue,
        'price': price,
        'description': description,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (withContentUrl && contentUrl != null) 'contentUrl': contentUrl,
      };
}

class MockOrderRow {
  MockOrderRow({
    required this.id,
    required this.userId,
    required this.buyerName,
    required this.service,
    required this.chefName,
    required this.createdAt,
    this.status = OrderStatus.pending,
  })  : serviceId = service.id,
        serviceTitle = service.title,
        type = service.type,
        chefId = service.chefId,
        amount = service.price;

  final String id;
  final String userId;
  final String buyerName;
  final MockServiceRow service;

  // Snapshot at purchase time: later edits to the service don't change it.
  final String serviceId;
  final String serviceTitle;
  final ServiceType type;
  final String chefId;
  final String chefName;
  final int amount;
  final DateTime createdAt;
  OrderStatus status;

  /// When the refund stub ran (chef wallet: the reversal's date).
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

class MockGrantRow {
  MockGrantRow({
    required this.id,
    required this.paymentId,
    required this.orderId,
    required this.grantedAt,
    required this.expiresAt,
  });

  final String id;
  final String paymentId;
  final String orderId;
  final DateTime grantedAt;
  final DateTime? expiresAt;
  GrantStatus status = GrantStatus.active;
}

class MockConsultationRow {
  MockConsultationRow({
    required this.id,
    required this.order,
    required this.durationMinutes,
    required this.startAt,
    required this.createdAt,
    this.status = ConsultationStatus.awaitingPayment,
    this.buyerNote,
  });

  final String id;
  final MockOrderRow order;
  final int durationMinutes;
  final DateTime startAt;
  final DateTime createdAt;
  ConsultationStatus status;
  final String? buyerNote;
  String? chefNotes;
  String? declineReason;
  DateTime? startedAt;
  DateTime? completedAt;
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

/// One static in-memory DB for chef profiles, services, orders, payments,
/// access grants, consultations and knowledge docs. Shared by
/// `MockChefRepository` (directory, slots), `MockCommerceRepository` (buyer)
/// and `MockChefStudioRepository` (chef), so a consult Minh Anh pays for shows
/// up for Tâm after switching accounts.
class MockCommerceDb {
  MockCommerceDb._();

  static MockCommerceDb? _instance;
  static MockCommerceDb get instance =>
      _instance ??= MockCommerceDb._().._seed();

  /// Mock clock. Tests move it forward instead of waiting (`#expire`).
  static DateTime Function() clock = DateTime.now;

  /// `normal` | `empty` | `error`, see [_scenarioFromEnv].
  static String scenario = _scenarioFromEnv;

  /// Fresh seeds (seeded against [clock] on next use).
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

  /// `#expire` in the booking note.
  static const fastExpiryTtl = Duration(seconds: 30);

  final chefs = <MockChefRow>[];
  final services = <MockServiceRow>[];
  final orders = <MockOrderRow>[];
  final payments = <MockPaymentRow>[];
  final grants = <MockGrantRow>[];
  final consultations = <MockConsultationRow>[];
  final docs = <MockDocRow>[];

  /// Chef wallet: keyed by chef profile id.
  final bankAccounts = <String, MockBankAccountRow>{};
  final withdrawals = <MockWithdrawalRow>[];

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

  MockServiceRow service(String id) => services.firstWhere((s) => s.id == id,
      orElse: () => throw mockError(404, 'Dịch vụ không còn được bán.'));

  List<MockServiceRow> servicesOf(String chefId) =>
      services.where((s) => s.chefId == chefId).toList();

  MockOrderRow order(String id) => orders.firstWhere((o) => o.id == id,
      orElse: () => throw mockError(404, 'Không tìm thấy đơn hàng.'));

  MockPaymentRow payment(String id) => payments.firstWhere((p) => p.id == id,
      orElse: () => throw mockError(404, 'Không tìm thấy giao dịch.'));

  MockConsultationRow consultation(String id) =>
      consultations.firstWhere((c) => c.id == id,
          orElse: () => throw mockError(404, 'Không tìm thấy lịch hẹn.'));

  MockConsultationRow? consultationOf(String orderId) =>
      consultations.where((c) => c.order.id == orderId).firstOrNull;

  MockGrantRow? grantOf(String orderId) =>
      grants.where((g) => g.orderId == orderId).lastOrNull;

  /// Latest payment attempt, expired lazily (the real BE does it on read or
  /// in a job).
  MockPaymentRow? latestPayment(String orderId) {
    final p = payments.where((p) => p.orderId == orderId).lastOrNull;
    if (p != null) expireIfDue(p);
    return p;
  }

  void expireIfDue(MockPaymentRow p) {
    if (p.status == PaymentStatus.pending && !now.isBefore(p.expiresAt)) {
      p.status = PaymentStatus.expired;
    }
  }

  GrantStatus grantStatus(MockGrantRow g) => g.status == GrantStatus.active &&
          g.expiresAt != null &&
          g.expiresAt!.isBefore(now)
      ? GrantStatus.expired
      : g.status;

  // ---- slots --------------------------------------------------------------

  /// Paid consultations keep their slot; an unpaid one only while its QR is
  /// still payable (it's released on expiry, failure or cancel).
  bool holdsSlot(MockConsultationRow c) => switch (c.status) {
        ConsultationStatus.pending ||
        ConsultationStatus.confirmed ||
        ConsultationStatus.inProgress =>
          true,
        ConsultationStatus.awaitingPayment =>
          c.order.status == OrderStatus.pending &&
              latestPayment(c.order.id)?.status == PaymentStatus.pending,
        _ => false,
      };

  bool isSlotFree(String chefId, DateTime startAt,
          {String? exceptConsultationId}) =>
      !consultations.any((c) =>
          c.order.chefId == chefId &&
          c.id != exceptConsultationId &&
          c.startAt.isAtSameMomentAs(startAt) &&
          holdsSlot(c));

  List<DateTime> freeSlots(String chefId) => buildSlots(chefId, now: now)
      .where((s) => s.isAfter(now) && isSlotFree(chefId, s))
      .toList();

  /// Upcoming slots of the chef's calendar someone already holds (paid, or
  /// an unpaid order whose QR is still payable). Sent as `bookedSlots` so
  /// the booking sheet can grey them out.
  List<DateTime> bookedSlots(String chefId) => buildSlots(chefId, now: now)
      .where((s) => s.isAfter(now) && !isSlotFree(chefId, s))
      .toList();

  /// The member's own consultation (any chef) that overlaps
  /// [startAt] … +[durationMinutes] and still holds its time, including an
  /// AwaitingPayment hold. A member can't be in two consultations at once.
  MockConsultationRow? memberClash(
          String userId, DateTime startAt, int durationMinutes,
          {String? exceptConsultationId}) =>
      consultations
          .where((c) =>
              c.order.userId == userId &&
              c.id != exceptConsultationId &&
              holdsSlot(c) &&
              c.startAt
                  .isBefore(startAt.add(Duration(minutes: durationMinutes))) &&
              startAt.isBefore(c.endAt))
          .firstOrNull;

  /// 409 `schedule_conflict` for [memberClash].
  ApiException clashError(MockConsultationRow c) {
    String two(int n) => n.toString().padLeft(2, '0');
    final at = c.startAt;
    return mockError(
        409,
        'Bạn đã có lịch lúc ${two(at.hour)}:${two(at.minute)} · '
            '${formatLongDate(at)} với ${c.order.chefName} — chọn giờ khác nhé.',
        'schedule_conflict');
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

  /// PaymentOS confirmed (the webhook, on the real BE): order Paid, access
  /// granted in the same step, a consult goes to the chef for confirmation.
  void markPaid(MockPaymentRow p) {
    final o = order(p.orderId);
    final c = consultationOf(o.id);
    p
      ..status = PaymentStatus.paid
      ..paidAt = now;
    o.status = OrderStatus.paid;
    final days = o.type.accessDays;
    grants.add(MockGrantRow(
      id: newId('gr'),
      paymentId: p.id,
      orderId: o.id,
      grantedAt: now,
      expiresAt: days != null
          ? now.add(Duration(days: days))
          : c?.startAt.add(const Duration(hours: 24)),
    ));
    if (c != null && c.status == ConsultationStatus.awaitingPayment) {
      c.status = ConsultationStatus.pending;
    }
  }

  /// Refund stub: statuses move, no money does.
  void refund(MockOrderRow o) {
    o
      ..status = OrderStatus.refunded
      ..refundedAt = now;
    for (final p in payments.where((p) => p.orderId == o.id)) {
      if (p.status == PaymentStatus.paid) p.status = PaymentStatus.refunded;
    }
    grantOf(o.id)?.status = GrantStatus.revoked;
  }

  /// An unpaid order: the QR stops working and the slot is released.
  void cancelUnpaid(MockOrderRow o) {
    o.status = OrderStatus.cancelled;
    for (final p in payments.where((p) => p.orderId == o.id)) {
      if (p.status == PaymentStatus.pending) p.status = PaymentStatus.expired;
    }
    consultationOf(o.id)?.status = ConsultationStatus.cancelled;
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

  Map<String, dynamic> chefJson(MockChefRow c, {required bool detail}) {
    final own = servicesOf(c.id);
    return {
      'id': c.id,
      'userId': c.userId,
      'fullName': c.fullName,
      'headline': c.headline,
      'specialties': c.specialties,
      'rating': c.rating,
      'reviewCount': c.reviewCount,
      'yearsExperience': c.yearsExperience,
      'city': c.city,
      'startingPriceVnd': own.isEmpty
          ? 0
          : own.map((s) => s.price).reduce((a, b) => a < b ? a : b),
      'consultCount': c.consultCount,
      if (detail) ...{
        'bio': c.bio,
        'certificates': c.certificates,
        'services': own.map((s) => s.toJson()).toList(),
        'availableSlots': freeSlots(c.id).map(_iso).toList(),
        'bookedSlots': bookedSlots(c.id).map(_iso).toList(),
      },
    };
  }

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

  Map<String, dynamic> grantJson(MockGrantRow g) => {
        'id': g.id,
        'paymentId': g.paymentId,
        'grantedAt': _iso(g.grantedAt),
        'expiresAt': _iso(g.expiresAt),
        'status': grantStatus(g).apiValue,
      };

  Map<String, dynamic> consultationJson(MockConsultationRow c) => {
        'id': c.id,
        'orderId': c.order.id,
        'chefId': c.order.chefId,
        'chefName': c.order.chefName,
        'buyer': {'id': c.order.userId, 'fullName': c.order.buyerName},
        'serviceId': c.order.serviceId,
        'serviceTitle': c.order.serviceTitle,
        'durationMinutes': c.durationMinutes,
        'amount': c.order.amount,
        'startAt': _iso(c.startAt),
        'status': c.status.apiValue,
        'buyerNote': c.buyerNote,
        'chefNotes': c.chefNotes,
        'declineReason': c.declineReason,
        'startedAt': _iso(c.startedAt),
        'completedAt': _iso(c.completedAt),
        'createdAt': _iso(c.createdAt),
      };

  Map<String, dynamic> orderJson(MockOrderRow o, {bool withBuyer = false}) {
    final payment = latestPayment(o.id);
    final grant = grantOf(o.id);
    final consultation = consultationOf(o.id);
    return {
      'id': o.id,
      'userId': o.userId,
      'serviceId': o.serviceId,
      'amount': o.amount,
      'status': o.status.apiValue,
      'createdAt': _iso(o.createdAt),
      'service': {
        'id': o.serviceId,
        'title': o.serviceTitle,
        'type': o.type.apiValue,
        'chefId': o.chefId,
        'chefName': o.chefName,
      },
      if (withBuyer) 'buyer': {'id': o.userId, 'fullName': o.buyerName},
      'payment': payment == null ? null : paymentJson(payment),
      'accessGrant': grant == null ? null : grantJson(grant),
      'consultation':
          consultation == null ? null : consultationJson(consultation),
    };
  }

  // ---- seeds --------------------------------------------------------------

  void _seed() {
    for (final json in seedChefs) {
      final chef = MockChefRow.fromSeed(json);
      chefs.add(chef);
      for (final s in (json['services'] as List<Object?>)
          .whereType<Map<String, dynamic>>()) {
        final minutes = readInt(s['durationMinutes']);
        services.add(MockServiceRow(
          id: s['id'] as String,
          chefId: chef.id,
          title: s['title'] as String,
          type: ServiceType.fromApi(s['type']),
          price: readInt(s['price']),
          description: s['description'] as String? ?? '',
          durationMinutes: minutes > 0 ? minutes : null,
          contentUrl: s['contentUrl'] as String?,
        ));
      }
    }

    final now = this.now;
    DateTime day(int offset, int hour, [int minute = 0]) =>
        DateTime(now.year, now.month, now.day + offset, hour, minute);
    final inTenMinutes =
        DateTime(now.year, now.month, now.day, now.hour, now.minute + 10);
    const me = ('u_me', 'Minh Anh');

    // Tâm's calendar (Lê Quang Tâm, u_chef_tam).
    _seedConsult('cs_tam_nam', ('u_hoang_nam', 'Hoàng Nam'), 'svc_tam_consult',
        startAt: day(2, 14),
        status: ConsultationStatus.pending,
        paidAt: now.subtract(const Duration(hours: 5)),
        note:
            'Nhà mình 4 người, bé 6 tuổi kén rau. Muốn thực đơn tối dễ nấu trong 30 phút.');
    _seedConsult('cs_tam_vy', ('u_thao_vy', 'Thảo Vy'), 'svc_tam_consult',
        startAt: inTenMinutes,
        status: ConsultationStatus.confirmed,
        paidAt: now.subtract(const Duration(days: 3)),
        note: 'Mình mới ăn chay 2 tháng, hay bị đói giữa buổi chiều.');
    _seedConsult('cs_tam_tram', ('u_ngoc_tram', 'Ngọc Trâm'), 'svc_tam_consult',
        startAt: day(-10, 14),
        status: ConsultationStatus.completed,
        paidAt: day(-13, 20),
        note: 'Cần thực đơn chay cho mẹ bị tiểu đường type 2.',
        chefNotes:
            'Ưu tiên gạo lứt, yến mạch và đậu; chia 5 bữa nhỏ. Hạn chế nước ép trái cây. '
            'Đã gửi file thực đơn 7 ngày và danh sách đi chợ qua email.');
    _seedPackage('od_tam_huy', ('u_duc_huy', 'Đức Huy'), 'svc_tam_course',
        paidAt: now.subtract(const Duration(days: 5)));
    // Earlier package sales: already past the hold period in Tâm's wallet.
    _seedPackage(
        'od_tam_vip_phuong', ('u_lan_phuong', 'Lan Phương'), 'svc_tam_vip',
        paidAt: now.subtract(const Duration(days: 12)));
    _seedPackage('od_tam_vip_tram', ('u_bao_tram', 'Bảo Trâm'), 'svc_tam_vip',
        paidAt: now.subtract(const Duration(days: 15)));
    _seedPackage('od_tam_vip_han', ('u_gia_han', 'Gia Hân'), 'svc_tam_vip',
        paidAt: now.subtract(const Duration(days: 25)));
    _seedPackage(
        'od_tam_course_viet', ('u_quoc_viet', 'Quốc Việt'), 'svc_tam_course',
        paidAt: now.subtract(const Duration(days: 40)));

    // Minh Anh (u_me).
    _seedConsult('cs_seed_1', me, 'svc_ha_plan',
        startAt: day(2, 19, 30),
        status: ConsultationStatus.confirmed,
        paidAt: now.subtract(const Duration(days: 1)),
        note: 'Mình hay mệt buổi chiều, muốn kiểm tra B12 và sắt.');
    _seedConsult('cs_seed_2', me, 'svc_tam_consult',
        startAt: day(-10, 9),
        status: ConsultationStatus.completed,
        paidAt: day(-13, 8),
        chefNotes:
            'Thực đơn 7 ngày đã gửi kèm. Nấu sẵn đậu gà và gạo lứt vào Chủ Nhật, '
            'mỗi tối chỉ cần 20 phút xào rau và làm nước sốt.');
    _seedPackage('od_me_course', me, 'svc_tam_course',
        paidAt: now.subtract(const Duration(days: 20)));
    // Still waiting for payment: "Thanh toán tiếp" resumes it.
    final vip = _newOrder('od_me_vip_ha', me, 'svc_ha_vip',
        createdAt: now.subtract(const Duration(minutes: 3)));
    payments.add(MockPaymentRow(
      id: 'pay_me_vip_ha',
      orderId: vip.id,
      transactionRef: nextRef(vip.createdAt),
      amount: vip.amount,
      createdAt: vip.createdAt,
      expiresAt: vip.createdAt.add(paymentTtl),
    ));

    // Tâm's wallet: bank account and past withdrawals.
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
  }

  MockOrderRow _newOrder(String id, (String, String) buyer, String serviceId,
      {required DateTime createdAt}) {
    final s = service(serviceId);
    final o = MockOrderRow(
      id: id,
      userId: buyer.$1,
      buyerName: buyer.$2,
      service: s,
      chefName: chef(s.chefId).fullName,
      createdAt: createdAt,
    );
    orders.add(o);
    return o;
  }

  void _pay(MockOrderRow o, DateTime paidAt) {
    final p = MockPaymentRow(
      id: 'pay_${o.id}',
      orderId: o.id,
      transactionRef: nextRef(o.createdAt),
      amount: o.amount,
      createdAt: o.createdAt,
      expiresAt: o.createdAt.add(paymentTtl),
    )
      ..status = PaymentStatus.paid
      ..paidAt = paidAt;
    payments.add(p);
    o.status = OrderStatus.paid;
    final days = o.type.accessDays;
    final c = consultationOf(o.id);
    grants.add(MockGrantRow(
      id: 'gr_${o.id}',
      paymentId: p.id,
      orderId: o.id,
      grantedAt: paidAt,
      expiresAt: days != null
          ? paidAt.add(Duration(days: days))
          : c?.startAt.add(const Duration(hours: 24)),
    ));
  }

  void _seedConsult(
    String id,
    (String, String) buyer,
    String serviceId, {
    required DateTime startAt,
    required ConsultationStatus status,
    required DateTime paidAt,
    String? note,
    String? chefNotes,
  }) {
    final createdAt = paidAt.subtract(const Duration(minutes: 4));
    final o = _newOrder('od_${id.substring(3)}', buyer, serviceId,
        createdAt: createdAt);
    final c = MockConsultationRow(
      id: id,
      order: o,
      durationMinutes: o.service.durationMinutes ?? 60,
      startAt: startAt,
      createdAt: createdAt,
      status: status,
      buyerNote: note,
    );
    consultations.add(c);
    _pay(o, paidAt);
    if (status == ConsultationStatus.completed) {
      c
        ..startedAt = startAt
        ..completedAt = c.endAt
        ..chefNotes = chefNotes;
    }
  }

  void _seedPackage(String id, (String, String) buyer, String serviceId,
      {required DateTime paidAt}) {
    final o = _newOrder(id, buyer, serviceId,
        createdAt: paidAt.subtract(const Duration(minutes: 3)));
    _pay(o, paidAt);
  }
}

extension on MockConsultationRow {
  DateTime get endAt => startAt.add(Duration(minutes: durationMinutes));
}
