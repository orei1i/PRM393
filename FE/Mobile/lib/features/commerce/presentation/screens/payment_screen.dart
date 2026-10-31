// lib/features/commerce/presentation/screens/payment_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/navigation/app_nav.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../booking/domain/booking_rules.dart';
import '../../../booking/presentation/screens/booking_history_screen.dart';
import '../../data/commerce_api_service.dart';
import '../../data/models/order_model.dart';
import '../../data/models/payment_model.dart';
import '../../domain/commerce_status.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';
import '../widgets/mock_qr_view.dart';

/// PaymentOS QR for one booking order (the agreed contract price). Polls
/// the payment every 3 s while it is pending (the real confirmation is the
/// PaymentOS webhook on the BE) and counts down to its expiry. Once paid,
/// the money is held in escrow until the plan's end date + 3 days.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.orderId,
    bool? showMockControls,
    this.autoRenew = false,
  }) : _showMockControls = showMockControls;

  final String orderId;

  final bool? _showMockControls;

  /// "Mô phỏng đã thanh toán" / "Mô phỏng thất bại": only while the commerce
  /// module is mock, hybrid builds included (a booking could not be paid
  /// otherwise).
  bool get showMockControls =>
      _showMockControls ?? BackendModules.isMock(BackendModule.commerce);

  /// "Thanh toán tiếp": an expired or failed QR is replaced right away.
  final bool autoRenew;

  static Route<void> route(String orderId, {bool autoRenew = false}) =>
      MaterialPageRoute<void>(
        builder: (_) => PaymentScreen(orderId: orderId, autoRenew: autoRenew),
      );

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  static const _pollEvery = Duration(seconds: 3);

  OrderDto? _order;
  Object? _error;
  bool _busy = false;
  bool _polling = false;
  Timer? _poll;
  Timer? _tick;
  late bool _autoRenew = widget.autoRenew;

  CommerceApiService get _api => ref.read(commerceApiProvider);

  PaymentDto? get _payment => _order?.payment;

  bool get _awaiting =>
      _order?.status == OrderStatus.pending &&
      _payment?.status == PaymentStatus.pending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var order = await _api.getOrder(widget.orderId);
      final status = order.payment?.status;
      if (_autoRenew &&
          order.status == OrderStatus.pending &&
          status != PaymentStatus.pending) {
        await _api.renewPayment(order.id);
        order = await _api.getOrder(order.id);
        _changed();
      }
      _autoRenew = false;
      if (mounted) _apply(order);
    } catch (e) {
      _autoRenew = false;
      if (mounted) setState(() => _error = e);
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _order = null;
    });
    _load();
  }

  void _apply(OrderDto order) {
    setState(() {
      _order = order;
      _error = null;
    });
    if (_awaiting) {
      _poll ??= Timer.periodic(_pollEvery, (_) => _pollOnce());
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    } else {
      _poll?.cancel();
      _tick?.cancel();
      _poll = _tick = null;
    }
  }

  /// Lists elsewhere (bookings, the chef's inbox and wallet) refetch.
  void _changed() => ref.read(commerceRevisionProvider.notifier).bump();

  void _onTick() {
    if (!mounted) return;
    final expiresAt = _payment?.expiresAt;
    if (expiresAt != null && !DateTime.now().isBefore(expiresAt)) _pollOnce();
    setState(() {}); // countdown
  }

  Future<void> _pollOnce() async {
    final payment = _payment;
    if (_polling || _busy || payment == null) return;
    _polling = true;
    try {
      final fresh = await _api.getPayment(payment.id);
      if (mounted && fresh.status != payment.status) await _reloadOrder();
    } catch (_) {
      // Best effort: the next tick tries again.
    } finally {
      _polling = false;
    }
  }

  Future<void> _reloadOrder() async {
    final order = await _api.getOrder(widget.orderId);
    if (!mounted) return;
    _apply(order);
    _changed();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _mockPay({required bool success}) => _run(() async {
        await _api.mockConfirmPayment(_payment!.id, success: success);
        await _reloadOrder();
      });

  void _renew() => _run(() async {
        await _api.renewPayment(widget.orderId);
        await _reloadOrder();
      });

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rời màn thanh toán?'),
        content: const Text(
            'Bạn có thể thanh toán tiếp trong Lịch sử tư vấn trước hạn thanh toán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ở lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Rời đi')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  /// "Lịch sử tư vấn": the booking pages under this one are done with
  /// (paid, cancelled or refunded), so back to the history already open,
  /// else a single one right above the shell.
  void _openHistory() =>
      AppNav.popToOrReset(Navigator.of(context), BookingHistoryScreen.route());

  /// Back to the booking that opened this screen.
  void _back() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return PopScope(
      canPop: !_awaiting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Thanh toán')),
        body: DemoDataBanner.wrap(BackendModule.commerce,
            child: order == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : ErrorStateView(error: _error!, onRetry: _retry),
                  )
                : SafeArea(
                    top: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _content(order),
                        ),
                      ),
                    ),
                  )),
      ),
    );
  }

  Widget _content(OrderDto order) {
    final payment = order.payment;
    switch (order.status) {
      case OrderStatus.paid:
        return _PaidView(
            order: order, onBack: _back, onOpenHistory: _openHistory);
      case OrderStatus.cancelled:
        return _Outcome(
          icon: Icons.cancel_outlined,
          title: 'Đơn đã huỷ',
          message: 'Không có khoản tiền nào bị trừ.',
          actions: [
            OutlinedButton(
                onPressed: _openHistory, child: const Text('Lịch sử tư vấn')),
          ],
        );
      case OrderStatus.refunded:
      case OrderStatus.partiallyRefunded:
        final refunded = order.escrow?.refundedAmount ?? order.amount;
        return _Outcome(
          icon: Icons.currency_exchange_rounded,
          title: order.status == OrderStatus.refunded
              ? 'Đã hoàn tiền'
              : 'Đã hoàn một phần',
          message:
              '${formatVnd(refunded)} đã được hoàn về phương thức thanh toán ban đầu.',
          actions: [
            OutlinedButton(
                onPressed: _openHistory, child: const Text('Lịch sử tư vấn')),
          ],
        );
      case OrderStatus.pending:
        if (payment != null && payment.status == PaymentStatus.pending) {
          return _PendingView(
            order: order,
            payment: payment,
            busy: _busy,
            showMockControls: widget.showMockControls,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: payment.transactionRef));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã giao dịch')));
            },
            onMockPaid: () => _mockPay(success: true),
            onMockFailed: () => _mockPay(success: false),
          );
        }
        final failed = payment?.status == PaymentStatus.failed;
        return _Outcome(
          icon: failed ? Icons.error_outline_rounded : Icons.timer_off_outlined,
          title: failed ? 'Thanh toán không thành công' : 'Mã QR đã hết hạn',
          message: failed
              ? 'Giao dịch chưa được xác nhận nên bạn chưa bị trừ tiền. Thử lại với mã mới nhé.'
              : 'Mỗi mã chỉ dùng được 15 phút. Tạo mã mới để tiếp tục thanh toán.',
          actions: [
            FilledButton(
              onPressed: _busy ? null : _renew,
              child: Text(_busy
                  ? 'Đang tạo mã…'
                  : failed
                      ? 'Thử lại'
                      : 'Tạo mã mới'),
            ),
            OutlinedButton(
                onPressed: _busy ? null : _back, child: const Text('Để sau')),
          ],
        );
    }
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final OrderDto order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(order.booking.title,
            textAlign: TextAlign.center,
            style: context.textStyles.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${order.booking.chefName} · ${order.booking.bookingType.label}',
            textAlign: TextAlign.center,
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.muted)),
        const SizedBox(height: 12),
        Text(
          formatVnd(order.amount),
          textAlign: TextAlign.center,
          style: context.textStyles.headlineMedium?.copyWith(
              color: context.colors.primary, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({
    required this.order,
    required this.payment,
    required this.busy,
    required this.showMockControls,
    required this.onCopy,
    required this.onMockPaid,
    required this.onMockFailed,
  });

  final OrderDto order;
  final PaymentDto payment;
  final bool busy;
  final bool showMockControls;
  final VoidCallback onCopy;
  final VoidCallback onMockPaid;
  final VoidCallback onMockFailed;

  String _countdown() {
    final expiresAt = payment.expiresAt;
    if (expiresAt == null) return '';
    final left = expiresAt.difference(DateTime.now());
    final s = left.isNegative ? 0 : left.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final qrUrl = payment.qrCodeUrl;
    final booking = order.booking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VLCard(
          child: Column(
            children: [
              _OrderHeader(order: order),
              const SizedBox(height: 4),
              Text(
                  'Kế hoạch ${formatDayMonth(booking.startDate)} – ${formatDayMonth(booking.endDate)} · '
                  'tiền được giữ đến ${formatVnStamp(escrowReleaseAt(booking.endDate))}',
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodyMedium),
              const SizedBox(height: 16),
              if (showMockControls || qrUrl == null)
                MockQrView(data: payment.transactionRef)
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    qrUrl,
                    width: 200,
                    height: 200,
                    errorBuilder: (_, __, ___) => SizedBox.square(
                      dimension: 200,
                      child: Center(
                        child: Text('Không tải được mã QR.',
                            textAlign: TextAlign.center,
                            style: context.textStyles.bodySmall),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                showMockControls
                    ? 'Mã QR mô phỏng'
                    : 'Quét bằng ứng dụng ngân hàng để thanh toán qua PaymentOS',
                textAlign: TextAlign.center,
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Mã giao dịch: ',
                        children: [
                          TextSpan(
                            text: payment.transactionRef,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodyMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sao chép mã giao dịch',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 20),
                  ),
                ],
              ),
              Text('Mã hết hạn sau ${_countdown()}',
                  textAlign: TextAlign.center,
                  style: context.textStyles.labelLarge
                      ?.copyWith(color: vl.onCautionContainer)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Đang chờ thanh toán…',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: vl.muted)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (showMockControls) ...[
          const SizedBox(height: 12),
          VLCard(
            color: vl.aiContainer,
            borderColor: vl.aiBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Chế độ mô phỏng',
                    style: context.textStyles.titleSmall
                        ?.copyWith(color: vl.onAiContainer)),
                const SizedBox(height: 2),
                Text(
                  'Bản thật được PaymentOS xác nhận tự động sau khi bạn chuyển khoản.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: vl.onAiContainer),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: busy ? null : onMockPaid,
                  child: const Text('Mô phỏng đã thanh toán'),
                ),
                TextButton(
                  onPressed: busy ? null : onMockFailed,
                  child: const Text('Mô phỏng thất bại'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PaidView extends StatelessWidget {
  const _PaidView({
    required this.order,
    required this.onBack,
    required this.onOpenHistory,
  });

  final OrderDto order;
  final VoidCallback onBack;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final paidAt = order.payment?.paidAt;
    final releaseAt =
        order.escrow?.releaseAt ?? escrowReleaseAt(order.booking.endDate);
    return _Outcome(
      icon: Icons.check_circle_rounded,
      iconColor: context.vl.success,
      title: 'Thanh toán thành công',
      message: [
        formatVnd(order.amount),
        if (paidAt != null) 'lúc ${formatStamp(paidAt)}',
      ].join(' '),
      details: [
        VLCard(
          color: context.vl.successContainer,
          borderColor: Colors.transparent,
          child: Text(
            'Đang giữ đến ${formatVnStamp(releaseAt)} '
            '(${BookingRules.holdDays} ngày sau khi kế hoạch kết thúc). '
            '${order.booking.chefName} bắt đầu soạn kế hoạch; nếu kế hoạch có vấn đề, '
            'bạn khiếu nại trước thời điểm này để VeganLife giữ tiền lại.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.onSuccessContainer),
          ),
        ),
      ],
      actions: [
        FilledButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.restaurant_menu_rounded),
          label: const Text('Về kế hoạch'),
        ),
        OutlinedButton(
            onPressed: onOpenHistory, child: const Text('Lịch sử tư vấn')),
      ],
    );
  }
}

/// Icon + title + message + stacked full-width actions.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.iconColor,
    this.details = const [],
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String message;
  final List<Widget> details;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 64, color: iconColor ?? context.colors.primary),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: context.textStyles.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: context.textStyles.bodyLarge
                  ?.copyWith(color: context.vl.muted)),
          const SizedBox(height: 12),
          ...details,
          const SizedBox(height: 20),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52), child: a),
            ),
        ],
      ),
    );
  }
}
