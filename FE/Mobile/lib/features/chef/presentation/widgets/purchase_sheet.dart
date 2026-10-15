// lib/features/chef/presentation/widgets/purchase_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../commerce/data/commerce_api_service.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../domain/entities/chef.dart';
import 'service_tile.dart';

/// "Mua gói" for a course / VIP menu: summary, access length and
/// "Thanh toán · 990.000đ". Pops the created [OrderDto]; the caller opens
/// the payment screen.
class PurchaseSheet extends ConsumerStatefulWidget {
  const PurchaseSheet({super.key, required this.chef, required this.service});

  final Chef chef;
  final ChefService service;

  @override
  ConsumerState<PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends ConsumerState<PurchaseSheet> {
  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(commerceApiProvider)
          .createOrder(CreateOrderRequestDto(serviceId: widget.service.id));
      if (mounted) Navigator.of(context).pop(order);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final days = service.type.accessDays ?? 30;
    final until = DateTime.now().add(Duration(days: days));
    final muted =
        context.textStyles.bodyMedium?.copyWith(color: context.vl.muted);

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: context.textStyles.bodyMedium)),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The type's display label as is: "Mua Thực đơn VIP".
                Text('Mua ${service.type.label}',
                    style: context.textStyles.titleLarge),
                const SizedBox(height: 4),
                Text('của ${widget.chef.name}', style: muted),
                const SizedBox(height: 16),
                ServiceTile(service: service),
                const SizedBox(height: 16),
                line(Icons.schedule_rounded,
                    'Truy cập $days ngày · đến khoảng ${formatFullDate(until)}'),
                line(Icons.lock_open_rounded,
                    'Nội dung mở ngay sau khi thanh toán, trong "Đơn hàng của tôi".'),
                line(Icons.qr_code_2_rounded,
                    'Thanh toán bằng mã QR PaymentOS, mã có hiệu lực 15 phút.'),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            border: Border(top: BorderSide(color: context.vl.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(_error!,
                          style: context.textStyles.bodyMedium
                              ?.copyWith(color: context.colors.error)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: Text(_sending
                        ? 'Đang tạo đơn…'
                        : 'Thanh toán · ${formatVnd(service.price)}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
