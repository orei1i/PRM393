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
import '../../../chef_studio/data/models/wallet_models.dart';
import '../../data/commerce_api_service.dart';
import '../../data/models/order_model.dart';
import '../../data/models/payment_model.dart';
import '../../domain/commerce_status.dart';
import '../controllers/commerce_controllers.dart';
import '../widgets/commerce_ui.dart';
import '../widgets/mock_qr_view.dart';

/// The QR of the gateway for one booking order (the agreed contract price), or
/// the member's wallet when its balance covers the price. Polls the payment
/// every 3 s while it is pending (the real confirmation comes from the gateway,
/// on the BE) and counts down to its expiry. Once paid, the money is held in
/// escrow until [BookingRules.holdDays] days after the contract is completed.
///
/// A gateway that is missing or down (503) is said here, with the wallet still
/// on offer. Only the server's answer ever shows a payment as done.
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

  /// Opened to pay: a QR is asked for right away unless one is open.
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

  /// Why the last request for a QR failed. The order is fine, so the screen
  /// stays, with what can still be done.
  ApiException? _qrError;
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
        await _askForQr();
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

  /// A failure is kept in [_qrError], not thrown: the order itself is fine.
  Future<void> _askForQr() async {
    try {
      await _api.renewPayment(widget.orderId);
      _qrError = null;
    } on ApiException catch (e) {
      _qrError = e;
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
        await _askForQr();
        await _reloadOrder();
      });

  Future<void> _payWithWallet(OrderDto order, int balance) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Thanh toán ${formatVnd(order.amount)} bằng ví?'),
        content: Text(
            'Số dư ví còn ${formatVnd(balance - order.amount)} sau khi thanh toán. '
            'VeganLife giữ tiền đến ${BookingRules.holdDays} ngày sau khi hợp đồng hoàn thành.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Xem lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Thanh toán')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await _api.payWithWallet(order.id);
      await _reloadOrder();
    });
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rời màn thanh toán?'),
        content: const Text(
            'Bạn có thể thanh toán tiếp ngay trong yêu cầu này, trước hạn thanh toán.'),
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
          message: '${formatVnd(refunded)} đã được hoàn vào Ví của tôi.',
          actions: [
            OutlinedButton(
                onPressed: _openHistory, child: const Text('Lịch sử tư vấn')),
          ],
        );
      case OrderStatus.pending:
        final wallet = BackendModules.payFromWallet
            ? _WalletOption(
                amount: order.amount,
                busy: _busy,
                onPay: (balance) => _payWithWallet(order, balance),
              )
            : null;
        if (payment != null && payment.status == PaymentStatus.pending) {
          return _PendingView(
            order: order,
            payment: payment,
            busy: _busy,
            showMockControls: widget.showMockControls,
            wallet: wallet,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: payment.transactionRef));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã sao chép mã giao dịch')));
            },
            onMockPaid: () => _mockPay(success: true),
            onMockFailed: () => _mockPay(success: false),
          );
        }
        return _NoQrView(
          order: order,
          payment: payment,
          error: _qrError,
          busy: _busy,
          wallet: wallet,
          onRetry: _renew,
          onLater: _back,
        );
    }
  }
}

/// A pending order with no open QR: never made, expired, failed, or the gateway
/// can't make one. Nothing is charged, and the wallet still works.
class _NoQrView extends StatelessWidget {
  const _NoQrView({
    required this.order,
    required this.payment,
    required this.error,
    required this.busy,
    required this.wallet,
    required this.onRetry,
    required this.onLater,
  });

  final OrderDto order;
  final PaymentDto? payment;
  final ApiException? error;
  final bool busy;
  final Widget? wallet;
  final VoidCallback onRetry;
  final VoidCallback onLater;

  bool get _noGateway => error?.statusCode == 503;

  ({IconData icon, String title, String message, String action}) get _state {
    final failure = error;
    if (_noGateway) {
      return (
        icon: Icons.cloud_off_rounded,
        title: 'Chưa thanh toán qua cổng được',
        message: 'Cổng thanh toán đang chưa sẵn sàng nên chưa tạo được mã QR. '
            'Bạn chưa bị trừ tiền.',
        action: 'Thử lại',
      );
    }
    if (failure != null) {
      return (
        icon: Icons.error_outline_rounded,
        title: 'Chưa tạo được mã QR',
        message: '${describeError(failure)} Bạn chưa bị trừ tiền.',
        action: 'Thử lại',
      );
    }
    return switch (payment?.status) {
      PaymentStatus.failed => (
          icon: Icons.error_outline_rounded,
          title: 'Thanh toán không thành công',
          message:
              'Giao dịch chưa được xác nhận nên bạn chưa bị trừ tiền. Thử lại với mã mới nhé.',
          action: 'Thử lại',
        ),
      null => (
          icon: Icons.qr_code_2_rounded,
          title: 'Chưa có mã QR',
          message: 'Tạo mã để thanh toán đơn này.',
          action: 'Tạo mã QR',
        ),
      _ => (
          icon: Icons.timer_off_outlined,
          title: 'Mã QR đã hết hạn',
          message:
              'Mỗi mã chỉ dùng được 15 phút. Tạo mã mới để tiếp tục thanh toán.',
          action: 'Tạo mã mới',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return _Outcome(
      icon: state.icon,
      title: state.title,
      message: state.message,
      header: _OrderHeader(order: order),
      details: [if (wallet != null) wallet!],
      actions: [
        FilledButton(
          onPressed: busy ? null : onRetry,
          child: Text(busy ? 'Đang tạo mã…' : state.action),
        ),
        OutlinedButton(
            onPressed: busy ? null : onLater, child: const Text('Để sau')),
      ],
    );
  }
}

/// "Thanh toán bằng ví" when the balance covers the price (no partial
/// balance); otherwise a line saying why not. A wallet that can't be read
/// never blocks the QR.
class _WalletOption extends ConsumerWidget {
  const _WalletOption({
    required this.amount,
    required this.busy,
    required this.onPay,
  });

  final int amount;
  final bool busy;
  final ValueChanged<int> onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memberWalletProvider);
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final WalletDto? wallet = async.valueOrNull;
    if (wallet == null) {
      return async.hasError
          ? Row(
              children: [
                Expanded(child: Text('Chưa đọc được số dư ví.', style: muted)),
                TextButton(
                    onPressed: () => ref.invalidate(memberWalletProvider),
                    child: const Text('Thử lại')),
              ],
            )
          : Text('Đang kiểm tra số dư ví…', style: muted);
    }
    final balance = wallet.available;
    if (balance < amount) {
      return Text(
          'Số dư ví ${formatVnd(balance)} chưa đủ để thanh toán bằng ví.',
          style: muted);
    }
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Số dư ví ${formatVnd(balance)}',
              style: context.textStyles.titleSmall),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => onPay(balance),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Thanh toán bằng ví'),
          ),
        ],
      ),
    );
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
    this.wallet,
  });

  final OrderDto order;
  final PaymentDto payment;
  final bool busy;
  final bool showMockControls;

  /// The wallet option, above the QR so a small screen shows it first.
  final Widget? wallet;
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
    final sandbox = payment.provider == 'Sandbox';
    final booking = order.booking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wallet != null) ...[
          wallet!,
          const SizedBox(height: 12),
        ],
        VLCard(
          child: Column(
            children: [
              _OrderHeader(order: order),
              const SizedBox(height: 4),
              Text(
                  'Kế hoạch ${formatDayMonth(booking.startDate)} – ${formatDayMonth(booking.endDate)} · '
                  'VeganLife giữ tiền đến ${BookingRules.holdDays} ngày sau khi hợp đồng hoàn thành',
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodyMedium),
              const SizedBox(height: 16),
              if (showMockControls || sandbox)
                MockQrView(data: payment.transactionRef)
              else if (qrUrl == null)
                SizedBox.square(
                  dimension: 200,
                  child: Center(
                    child: Text('Máy chủ chưa gửi mã QR.',
                        textAlign: TextAlign.center,
                        style: context.textStyles.bodySmall),
                  ),
                )
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
                    : sandbox
                        ? 'Cổng thử nghiệm, không có tiền thật: mã này không '
                            'quét được, dùng nút bên dưới để thử.'
                        : 'Quét bằng ứng dụng ngân hàng để thanh toán qua ${payment.provider}',
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
        if (showMockControls || sandbox) ...[
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
                  sandbox
                      ? 'Bản demo không có tiền thật. Khi có cổng thanh toán, giao dịch sẽ được xác nhận tự động.'
                      : 'Bản thật được PaymentOS xác nhận tự động sau khi bạn chuyển khoản.',
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
            'VeganLife đang giữ tiền đến ${BookingRules.holdDays} ngày sau khi hợp đồng hoàn thành. '
            '${order.booking.chefName} bắt đầu soạn kế hoạch; nếu kế hoạch có vấn đề, '
            'bạn khiếu nại trong thời gian này để VeganLife giữ tiền lại.',
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
    this.header,
    this.details = const [],
  });

  final IconData icon;
  final Color? iconColor;

  /// What the screen is about, above the [icon].
  final Widget? header;
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
          if (header != null) ...[
            header!,
            const SizedBox(height: 20),
          ],
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
