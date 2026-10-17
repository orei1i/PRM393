// lib/features/commerce/data/mock_commerce_repository.dart
import '../../../core/utils/mock_delay.dart';
import '../../booking/data/mock/mock_booking_db.dart';
import '../domain/commerce_status.dart';
import 'commerce_api_service.dart';
import 'mock/mock_commerce_db.dart';
import 'models/order_model.dart';
import 'models/payment_model.dart';

/// Booking payments on [MockCommerceDb]. A paid order funds its booking's
/// escrow ([MockBookingDb.onOrderPaid]); a new QR never outlives the
/// booking's 48-hour payment window (30 s with `#expire` in the needs).
class MockCommerceRepository implements CommerceApiService {
  MockCommerceRepository({required this.currentUserId});

  final String? Function() currentUserId;

  MockCommerceDb get _db => MockCommerceDb.instance;

  String _me() =>
      currentUserId() ??
      (throw mockError(401, 'Vui lòng đăng nhập để tiếp tục.'));

  MockOrderRow _myOrder(String id) {
    final me = _me();
    _db.bookingDb.settle();
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
  Future<OrderDto> getOrder(String id) async {
    await mockDelay(400);
    return _order(_myOrder(id));
  }

  @override
  Future<PaymentDto> renewPayment(String orderId) async {
    await mockDelay(600);
    final o = _myOrder(orderId);
    if (o.status != OrderStatus.pending) {
      throw mockError(409, 'Đơn này không còn chờ thanh toán.');
    }
    final booking = _db.bookingDb.booking(o.bookingId);
    _db.bookingDb.startPayment(booking);
    return PaymentDto.fromJson(_db.paymentJson(_db.latestPayment(o.id)!));
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
}
