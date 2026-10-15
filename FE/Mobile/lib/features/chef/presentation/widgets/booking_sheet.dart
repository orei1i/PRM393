// lib/features/chef/presentation/widgets/booking_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../commerce/data/commerce_api_service.dart';
import '../../../commerce/data/models/consultation_model.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../domain/entities/chef.dart';
import 'service_tile.dart';

/// Consult service → day → time → note → create the order. Pops the created
/// [OrderDto] (payment Pending); the caller opens the payment screen. The
/// price summary and submit button are pinned below the scrolling form.
///
/// No double booking: a time someone already holds with this chef is greyed
/// out as "Đã kín", and a time that overlaps one of the member's own
/// consultations (any chef, unpaid holds included) as "Bạn có lịch". The
/// server has the last word (409 `slot_taken` / `schedule_conflict`).
class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({super.key, required this.chef, this.initialService});

  final Chef chef;
  final ChefService? initialService;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  late final List<ChefService> _services = widget.chef.consultServices;
  late ChefService? _service =
      widget.initialService?.type == ServiceType.consult
          ? widget.initialService
          : (_services.isEmpty ? null : _services.first);

  /// The chef's calendar: free times and times someone already holds.
  late final List<DateTime> _slots = {
    for (final s in [...widget.chef.availableSlots, ...widget.chef.bookedSlots])
      s.millisecondsSinceEpoch: s,
  }.values.toList()
    ..sort();

  /// Held by someone else (`bookedSlots`, or a 409 `slot_taken`).
  late final Set<int> _taken = {
    for (final s in widget.chef.bookedSlots) s.millisecondsSinceEpoch,
  };

  /// The server said these overlap one of the member's consultations (409
  /// `schedule_conflict`), on top of what [myConsultationsProvider] shows.
  final Set<int> _clashing = {};

  late DateTime? _day = _firstDay();
  DateTime? _slot;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  List<DateTime> get _days => _slots.map(dateOnly).toSet().toList()..sort();

  bool get _fullyBooked => widget.chef.availableSlots.isEmpty;

  DateTime? _firstDay() {
    final open =
        _slots.where((s) => !_taken.contains(s.millisecondsSinceEpoch));
    final first = open.firstOrNull ?? _slots.firstOrNull;
    return first == null ? null : dateOnly(first);
  }

  /// Why [slot] can't be picked, or `null` when it can.
  String? _blockedReason(DateTime slot, List<ConsultationDto> mine) {
    final minutes = _service?.durationMinutes ?? 60;
    final end = slot.add(Duration(minutes: minutes));
    final clash = _clashing.contains(slot.millisecondsSinceEpoch) ||
        mine.any((c) =>
            c.status.isOpen &&
            c.startAt.isBefore(end) &&
            slot.isBefore(c.endAt));
    if (clash) return 'Bạn có lịch';
    if (_taken.contains(slot.millisecondsSinceEpoch)) return 'Đã kín';
    return null;
  }

  List<DateTime> get _slotsOfDay => _day == null
      ? const []
      : _slots.where((s) => isSameDay(s, _day!)).toList();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final service = _service;
    final slot = _slot;
    if (service == null || slot == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final order = await ref.read(commerceApiProvider).createOrder(
            CreateOrderRequestDto(
              serviceId: service.id,
              startAt: slot,
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop(order);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        if (e.code == 'slot_taken') {
          _taken.add(slot.millisecondsSinceEpoch);
          _slot = null;
        } else if (e.code == 'schedule_conflict') {
          _clashing.add(slot.millisecondsSinceEpoch);
          _slot = null;
        }
      });
      if (e.code == 'schedule_conflict') {
        ref.invalidate(myConsultationsProvider);
      }
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
    final service = _service;
    final mine = ref.watch(myConsultationsProvider).valueOrNull ??
        const <ConsultationDto>[];
    // A pick that became unavailable (bookings loaded, service changed) is
    // dropped rather than sent.
    final slot =
        _slot != null && _blockedReason(_slot!, mine) == null ? _slot : null;
    final blockedToday =
        _slotsOfDay.any((s) => _blockedReason(s, mine) != null);
    // Form scrolls; the summary + submit bar stays pinned at the bottom, above
    // the keyboard (viewInsets) and the gesture bar (SafeArea).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Đặt lịch với ${widget.chef.name}',
                      style: context.textStyles.titleLarge),
                  const SizedBox(height: 16),
                  Text('1. Chọn dịch vụ', style: context.textStyles.titleSmall),
                  const SizedBox(height: 8),
                  for (final s in _services)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ServiceTile(
                          service: s,
                          selected: s.id == service?.id,
                          onTap: () => setState(() => _service = s)),
                    ),
                  const SizedBox(height: 8),
                  Text('2. Chọn ngày & giờ',
                      style: context.textStyles.titleSmall),
                  const SizedBox(height: 8),
                  if (_slots.isEmpty || _fullyBooked)
                    Text(
                      'Chuyên gia đã kín lịch 7 ngày tới. Quay lại sau nhé.',
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.vl.muted),
                    )
                  else ...[
                    _DayChips(
                      days: _days,
                      selected: _day,
                      onSelected: (d) => setState(() {
                        _day = d;
                        _slot = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _slotsOfDay)
                          _SlotChip(
                            time: _time(s),
                            blockedReason: _blockedReason(s, mine),
                            selected: slot == s,
                            onSelected: () => setState(() => _slot = s),
                          ),
                      ],
                    ),
                    if (blockedToday) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Giờ bị mờ: bạn đã có lịch tư vấn trùng giờ, hoặc chuyên gia đã kín lịch.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Text('3. Bạn muốn tư vấn điều gì?',
                      style: context.textStyles.titleSmall),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _note,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      hintText:
                          'VD: Mình muốn tăng cơ, dị ứng đậu phộng, ngân sách 100k/ngày',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Text(
                    'Bước sau là thanh toán qua PaymentOS; khung giờ được giữ cho bạn 15 phút trong lúc thanh toán. '
                    'Nếu chuyên gia từ chối, bạn được hoàn tiền. Huỷ miễn phí trước giờ hẹn 24 tiếng. '
                    'Chuyên gia sẽ thấy hồ sơ sức khoẻ bạn đồng ý chia sẻ.',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.muted),
                  ),
                ],
              ),
            ),
          ),
          _ActionBar(
            service: service,
            slotLabel: slot == null
                ? null
                : '${_time(slot)} · ${formatLongDate(slot)}',
            error: _error,
            sending: _sending,
            onSubmit:
                service == null || slot == null || _sending ? null : _submit,
          ),
        ],
      ),
    );
  }
}

/// One time of the chosen day. Taken times stay visible but greyed out, with
/// why ("Đã kín", "Bạn có lịch") under the time, not just a colour.
class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.time,
    required this.blockedReason,
    required this.selected,
    required this.onSelected,
  });

  final String time;
  final String? blockedReason;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final reason = blockedReason;
    return ChoiceChip(
      label: reason == null
          ? Text(time)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time,
                    style: const TextStyle(
                        decoration: TextDecoration.lineThrough)),
                Text(reason, style: context.textStyles.labelSmall),
              ],
            ),
      tooltip: reason == null ? null : '$time · $reason',
      selected: reason == null && selected,
      onSelected: reason == null ? (_) => onSelected() : null,
    );
  }
}

/// Day picker. Scrolls sideways; each chip gets a finite max width so its
/// label is laid out again once the Google font arrives (no clipped "T5").
class _DayChips extends StatelessWidget {
  const _DayChips(
      {required this.days, required this.selected, required this.onSelected});

  final List<DateTime> days;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxChipWidth = math.max(0.0, constraints.maxWidth);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, d) in days.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxChipWidth),
                child: ChoiceChip(
                  showCheckmark: false,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(weekdayShort(d),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(formatDayMonth(d)),
                    ],
                  ),
                  selected: selected != null && isSameDay(d, selected!),
                  onSelected: (_) => onSelected(d),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Pinned footer: chosen service, time and price + "Tiếp tục thanh toán".
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.service,
    required this.slotLabel,
    required this.error,
    required this.sending,
    required this.onSubmit,
  });

  final ChefService? service;
  final String? slotLabel;
  final String? error;
  final bool sending;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final s = service;
    return DecoratedBox(
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
              Text(s?.title ?? 'Chưa chọn dịch vụ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge),
              Text(
                slotLabel ?? 'Chưa chọn giờ',
                style: context.textStyles.bodySmall?.copyWith(
                    color: slotLabel == null
                        ? context.vl.muted
                        : context.colors.onSurface),
              ),
              if (error != null) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Text(error!,
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.colors.error)),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(sending
                    ? 'Đang tạo đơn…'
                    : s == null
                        ? 'Tiếp tục thanh toán'
                        : 'Tiếp tục thanh toán · ${formatVnd(s.price)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
