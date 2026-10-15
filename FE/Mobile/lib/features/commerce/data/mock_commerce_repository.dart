// lib/features/commerce/data/mock_commerce_repository.dart
import '../../../core/utils/mock_delay.dart';
import '../../chef/domain/entities/chef.dart';
import '../domain/commerce_status.dart';
import 'commerce_api_service.dart';
import 'mock/mock_commerce_db.dart';
import 'models/consultation_model.dart';
import 'models/order_model.dart';
import 'models/payment_model.dart';

/// Buyer flows on [MockCommerceDb]. Triggers in the booking note: `#fail` →
/// 503 on create; `#expire` → the first QR expires 30 s after creation.
/// A consult that overlaps one of the member's own (any chef, including an
/// unpaid hold) → 409 `schedule_conflict`; a slot someone else holds → 409
/// `slot_taken`.
class MockCommerceRepository implements CommerceApiService {
  MockCommerceRepository(
      {required this.currentUserId, required this.currentUserName});

  final String? Function() currentUserId;
  final String Function() currentUserName;

  MockCommerceDb get _db => MockCommerceDb.instance;

  String _me() =>
      currentUserId() ??
      (throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.'));

  MockOrderRow _myOrder(String id) {
    final me = _me();
    final o = _db.order(id);
    if (o.userId != me) throw mockError(404, 'Không tìm thấy đơn hàng.');
    return o;
  }

  MockPaymentRow _myPayment(String id) {
    final p = _db.payment(id);
    _myOrder(p.orderId);
    return p;
  }

  OrderDto _order(MockOrderRow o) => OrderDto.fromJson(_db.orderJson(o));

  @override
  Future<OrderDto> createOrder(CreateOrderRequestDto request) async {
    await mockDelay(700);
    final me = _me();
    if (hasFailTrigger(request.note)) {
      throw mockError(503, 'Hệ thống đặt lịch đang bận. Vui lòng thử lại.');
    }
    final service = _db.service(request.serviceId);
    final chef = _db.chef(service.chefId);
    if (chef.userId == me) {
      throw mockError(
          409, 'Bạn không thể mua dịch vụ của chính mình.', 'own_service');
    }
    final startAt = request.startAt;
    if (service.type == ServiceType.consult) {
      if (startAt == null || !startAt.isAfter(_db.now)) {
        throw mockError(400, 'Chọn một khung giờ còn trống.');
      }
      // One member, one consultation at a time (any chef, held or paid).
      final clash = _db.memberClash(me, startAt, service.durationMinutes ?? 60);
      if (clash != null) throw _db.clashError(clash);
      if (!_db.isSlotFree(chef.id, startAt)) {
        throw mockError(409,
            'Khung giờ này vừa có người đặt. Chọn giờ khác nhé.', 'slot_taken');
      }
    }
    final order = MockOrderRow(
      id: _db.newId('od'),
      userId: me,
      buyerName: currentUserName(),
      service: service,
      chefName: chef.fullName,
      createdAt: _db.now,
    );
    _db.orders.add(order);
    final fast = request.note?.toLowerCase().contains('#expire') ?? false;
    _db.openPayment(order,
        ttl: fast ? MockCommerceDb.fastExpiryTtl : MockCommerceDb.paymentTtl);
    if (service.type == ServiceType.consult) {
      _db.consultations.add(MockConsultationRow(
        id: _db.newId('cs'),
        order: order,
        durationMinutes: service.durationMinutes ?? 60,
        startAt: startAt!,
        createdAt: _db.now,
        buyerNote: request.note?.trim(),
      ));
    }
    return _order(order);
  }

  @override
  Future<List<OrderDto>> myOrders({OrderStatus? status}) async {
    await mockDelay(500);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) return const [];
    final list = _db.orders
        .where((o) => o.userId == me && (status == null || o.status == status))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.map(_order).toList();
  }

  @override
  Future<OrderDto> getOrder(String id) async {
    await mockDelay(400);
    return _order(_myOrder(id));
  }

  @override
  Future<OrderDto> cancelOrder(String id) async {
    await mockDelay(500);
    final o = _myOrder(id);
    if (o.status != OrderStatus.pending) {
      throw mockError(409, 'Chỉ huỷ được đơn đang chờ thanh toán.');
    }
    _db.cancelUnpaid(o);
    return _order(o);
  }

  @override
  Future<PaymentDto> renewPayment(String orderId) async {
    await mockDelay(600);
    final o = _myOrder(orderId);
    if (o.status != OrderStatus.pending) {
      throw mockError(409, 'Đơn này không còn chờ thanh toán.');
    }
    final current = _db.latestPayment(o.id);
    if (current != null && current.status == PaymentStatus.pending) {
      return PaymentDto.fromJson(_db.paymentJson(current));
    }
    final c = _db.consultationOf(o.id);
    if (c != null) {
      if (!c.startAt.isAfter(_db.now)) {
        throw mockError(
            409, 'Đã qua giờ hẹn. Huỷ đơn này và đặt giờ khác nhé.');
      }
      final clash = _db.memberClash(o.userId, c.startAt, c.durationMinutes,
          exceptConsultationId: c.id);
      if (clash != null) throw _db.clashError(clash);
      if (!_db.isSlotFree(o.chefId, c.startAt, exceptConsultationId: c.id)) {
        throw mockError(
            409,
            'Khung giờ đã có người khác đặt. Huỷ đơn này và chọn giờ khác nhé.',
            'slot_taken');
      }
    }
    return PaymentDto.fromJson(_db.paymentJson(_db.openPayment(o)));
  }

  @override
  Future<PaymentDto> getPayment(String id) async {
    await mockDelay(150);
    return PaymentDto.fromJson(_db.paymentJson(_myPayment(id)));
  }

  @override
  Future<PaymentDto> mockConfirmPayment(String paymentId,
      {required bool success}) async {
    await mockDelay(400);
    final p = _myPayment(paymentId);
    _db.expireIfDue(p);
    if (p.status == PaymentStatus.expired) {
      throw mockError(409, 'Mã QR đã hết hạn.', 'payment_expired');
    }
    if (p.status == PaymentStatus.pending) {
      if (success) {
        _db.markPaid(p);
      } else {
        p.status = PaymentStatus.failed;
      }
    }
    return PaymentDto.fromJson(_db.paymentJson(p));
  }

  @override
  Future<List<ConsultationDto>> myConsultations() async {
    await mockDelay(500);
    final me = _me();
    if (MockCommerceDb.emptyScenario()) return const [];
    final list = _db.consultations.where((c) => c.order.userId == me).toList()
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    return list
        .map((c) => ConsultationDto.fromJson(_db.consultationJson(c)))
        .toList();
  }

  @override
  Future<ConsultationDto> cancelConsultation(String id) async {
    await mockDelay(500);
    final me = _me();
    final c = _db.consultation(id);
    if (c.order.userId != me) throw mockError(404, 'Không tìm thấy lịch hẹn.');
    final dto = ConsultationDto.fromJson(_db.consultationJson(c));
    if (c.status == ConsultationStatus.awaitingPayment) {
      _db.cancelUnpaid(c.order);
    } else if (dto.canBuyerCancel(_db.now)) {
      c.status = ConsultationStatus.cancelled;
      _db.refund(c.order);
    } else {
      throw mockError(
          409,
          'Chỉ huỷ được khi chuyên gia chưa xác nhận, hoặc trước giờ hẹn 24 tiếng.',
          'too_late');
    }
    return ConsultationDto.fromJson(_db.consultationJson(c));
  }

  @override
  Future<ServiceContentDto> getServiceContent(String serviceId) async {
    await mockDelay(500);
    final me = _me();
    final service = _db.service(serviceId);
    final paid = _db.orders.where((o) =>
        o.userId == me &&
        o.serviceId == serviceId &&
        o.status == OrderStatus.paid);
    final grant = paid
        .map((o) => _db.grantOf(o.id))
        .where((g) => g != null && _db.grantStatus(g) == GrantStatus.active)
        .firstOrNull;
    if (grant == null) {
      throw mockError(403, 'Bạn chưa mua gói này.', 'no_access');
    }
    final chef = _db.chef(service.chefId);
    return ServiceContentDto.fromJson({
      'serviceId': service.id,
      'title': service.title,
      'type': service.type.apiValue,
      'chefName': chef.fullName,
      'summary': _summary(service, chef.fullName),
      'contentUrl': service.contentUrl,
      'accessExpiresAt': grant.expiresAt?.toUtc().toIso8601String(),
    });
  }

  static String _summary(MockServiceRow s, String chefName) {
    final included = switch (s.type) {
      ServiceType.course => [
          'Video bài học theo tuần, xem lại không giới hạn trong thời gian truy cập',
          'File thực đơn và danh sách đi chợ cho từng tuần',
          'Bài tập nhỏ cuối mỗi tuần để tự kiểm tra',
        ],
      ServiceType.vipMenu => [
          'Thực đơn 3 bữa mỗi ngày, đủ đạm, sắt, B12',
          'Danh sách đi chợ gom theo tuần',
          'Gợi ý thay món khi thiếu nguyên liệu',
        ],
      ServiceType.consult => ['Ghi chú và khuyến nghị sau buổi tư vấn'],
    };
    return [
      '## ${s.title}',
      s.description,
      '### Bạn nhận được',
      for (final line in included) '- $line',
      '### Cách dùng',
      '1. Bấm **Mở nội dung** để xem trên trình duyệt.',
      '2. Lưu lại đường dẫn; nó hết hiệu lực khi quyền truy cập hết hạn.',
      '_Nội dung mô phỏng — bản thật do $chefName cung cấp._',
    ].join('\n\n');
  }
}
