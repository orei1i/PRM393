// lib/features/chef/presentation/widgets/booking_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/chef_api_service.dart';
import '../../data/models/chef_model.dart';
import '../../domain/entities/chef.dart';
import '../screens/chef_profile_screen.dart';

/// Package → day → time → note → send request. Pops the created [Consultation].
class BookingSheet extends ConsumerStatefulWidget {
  const BookingSheet({super.key, required this.chef, this.initialPackage});

  final Chef chef;
  final ConsultPackage? initialPackage;

  @override
  ConsumerState<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends ConsumerState<BookingSheet> {
  late ConsultPackage? _package = widget.initialPackage ??
      (widget.chef.packages.isEmpty ? null : widget.chef.packages.first);
  late final List<DateTime> _slots = List.of(widget.chef.availableSlots)
    ..sort();
  late DateTime? _day = _slots.isEmpty ? null : dateOnly(_slots.first);
  DateTime? _slot;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  List<DateTime> get _days => _slots.map(dateOnly).toSet().toList()..sort();

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
    final pkg = _package;
    final slot = _slot;
    if (pkg == null || slot == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final created = await ref.read(chefApiProvider).requestConsultation(
            ConsultationRequestDto(
              chefId: widget.chef.id,
              packageId: pkg.id,
              scheduledAt: slot,
              note: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop(created.toEntity());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        if (e.code == 'slot_taken') {
          _slots.remove(slot);
          _slot = null;
        }
      });
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
    final pkg = _package;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Đặt lịch với ${widget.chef.name}',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 16),
            Text('1. Chọn gói', style: context.textStyles.titleSmall),
            const SizedBox(height: 8),
            for (final p in widget.chef.packages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PackageTile(
                    package: p,
                    selected: p.id == pkg?.id,
                    onTap: () => setState(() => _package = p)),
              ),
            const SizedBox(height: 8),
            Text('2. Chọn ngày & giờ', style: context.textStyles.titleSmall),
            const SizedBox(height: 8),
            if (_slots.isEmpty)
              Text(
                'Chuyên gia đã kín lịch 7 ngày tới. Quay lại sau nhé.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted),
              )
            else ...[
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _days.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final d = _days[i];
                    final selected = _day != null && isSameDay(d, _day!);
                    return ChoiceChip(
                      showCheckmark: false,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(weekdayShort(d),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(formatDayMonth(d)),
                        ],
                      ),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _day = d;
                        _slot = null;
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _slotsOfDay)
                    ChoiceChip(
                      label: Text(_time(s)),
                      selected: _slot == s,
                      onSelected: (_) => setState(() => _slot = s),
                    ),
                ],
              ),
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
            VLCard(
              color: context.colors.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(pkg?.name ?? 'Chưa chọn gói',
                              style: context.textStyles.labelLarge)),
                      if (pkg != null)
                        Text(
                          formatVnd(pkg.priceVnd),
                          style: context.textStyles.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                    ],
                  ),
                  if (_slot != null) ...[
                    const SizedBox(height: 4),
                    Text('${_time(_slot!)} · ${formatLongDate(_slot!)}',
                        style: context.textStyles.bodyMedium),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Chưa cần thanh toán ngay. Bạn trả qua PayOS sau khi chuyên gia xác nhận (trong 24 giờ). '
                    'Huỷ miễn phí trước giờ hẹn 12 tiếng. Chuyên gia sẽ thấy hồ sơ sức khoẻ bạn đồng ý chia sẻ.',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.muted),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.colors.error)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed:
                  pkg == null || _slot == null || _sending ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child:
                  Text(_sending ? 'Đang gửi yêu cầu…' : 'Gửi yêu cầu đặt lịch'),
            ),
          ],
        ),
      ),
    );
  }
}
