// lib/features/booking/presentation/widgets/booking_sheets.dart
//
// Bottom sheets of the booking flow: "Đề xuất giá" (PriceOfferSheet), a
// reason (decline / cancel), "Phản hồi ngày này" (DayFeedbackSheet) and the
// chef's answer to a complaint.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => child,
    );

/// Sheet body that stays above the keyboard and scrolls.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: context.textStyles.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- offer

/// "Đề xuất giá": price, days, type, start date and a note. Returns the
/// request, or null when closed.
Future<OfferRequestDto?> showPriceOfferSheet(
  BuildContext context, {
  required OfferRequestDto initial,
  String title = 'Đề xuất giá',
  int minDays = BookingRules.minPlanDays,
  int maxDays = BookingRules.maxPlanDays,
}) =>
    _sheet<OfferRequestDto>(
      context,
      PriceOfferSheet(
          initial: initial, title: title, minDays: minDays, maxDays: maxDays),
    );

class PriceOfferSheet extends StatefulWidget {
  const PriceOfferSheet({
    super.key,
    required this.initial,
    this.title = 'Đề xuất giá',
    this.minDays = BookingRules.minPlanDays,
    this.maxDays = BookingRules.maxPlanDays,
  });

  final OfferRequestDto initial;
  final String title;
  final int minDays;
  final int maxDays;

  @override
  State<PriceOfferSheet> createState() => _PriceOfferSheetState();
}

class _PriceOfferSheetState extends State<PriceOfferSheet> {
  late final _price =
      TextEditingController(text: widget.initial.price.toString());
  late final _note = TextEditingController(text: widget.initial.note);
  late int _days = widget.initial.planDays;
  late BookingType _type = widget.initial.bookingType;
  late DateTime _start = widget.initial.startDate;
  bool _attempted = false;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _priceValue => int.tryParse(_price.text.trim());

  DateTime get _today => vnDateOf(DateTime.now());

  String? get _startError => BookingRules.startDate(_start, _today);

  Future<void> _pickStart() async {
    final first = addDays(_today, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(first) ? first : _start,
      firstDate: first,
      lastDate: addDays(_today, 180),
      helpText: 'Ngày bắt đầu',
    );
    if (picked != null) setState(() => _start = dateOnly(picked));
  }

  void _submit() {
    final priceError = BookingRules.price(_priceValue);
    final noteError = BookingRules.offerNote(_note.text);
    final daysError = BookingRules.planDays(_days);
    if (priceError != null ||
        noteError != null ||
        daysError != null ||
        _startError != null) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(context).pop(OfferRequestDto(
      price: _priceValue!,
      planDays: _days,
      bookingType: _type,
      startDate: _start,
      note: _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final price = _priceValue;
    final presets = [
      for (final d in BookingRules.dayPresets)
        if (d >= widget.minDays && d <= widget.maxDays) d,
    ];
    return _SheetBody(
      title: widget.title,
      children: [
        TextField(
          key: const ValueKey('offer-price'),
          controller: _price,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Giá (đ)',
            border: const OutlineInputBorder(),
            helperText: price == null || price == 0
                ? null
                : '= ${formatVnd(price)} · ≈ ${formatVnd((price / _days).round())}/ngày',
            errorText: _attempted ? BookingRules.price(price) : null,
          ),
        ),
        const SizedBox(height: 14),
        Text('Số ngày', style: context.textStyles.titleSmall),
        const SizedBox(height: 6),
        DayCountPicker(
          value: _days,
          presets: presets,
          min: widget.minDays,
          max: widget.maxDays,
          onChanged: (v) => setState(() => _days = v),
        ),
        const SizedBox(height: 14),
        Text('Hình thức', style: context.textStyles.titleSmall),
        const SizedBox(height: 6),
        BookingTypePicker(
            value: _type, onChanged: (t) => setState(() => _type = t)),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Ngày bắt đầu'),
          subtitle: Text(
            _attempted && _startError != null
                ? _startError!
                : '${weekdayLong(_start)}, ${formatDayMonth(_start)}/${_start.year}',
            style: _attempted && _startError != null
                ? TextStyle(color: context.colors.error)
                : null,
          ),
          trailing: const Text('Đổi'),
          onTap: _pickStart,
        ),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          maxLength: BookingRules.maxOfferNote,
          decoration: const InputDecoration(
            labelText: 'Lời nhắn',
            hintText: 'Giá đã gồm những gì, cách bạn làm việc…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Gửi đề xuất'),
        ),
      ],
    );
  }
}

/// Chips 3 / 7 / 10 / 14 / 30 plus a − / + stepper.
class DayCountPicker extends StatelessWidget {
  const DayCountPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.presets = BookingRules.dayPresets,
    this.min = BookingRules.minPlanDays,
    this.max = BookingRules.maxPlanDays,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final List<int> presets;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final d in presets)
              ChoiceChip(
                label: Text('$d ngày'),
                selected: value == d,
                onSelected: (_) => onChanged(d),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Bớt 1 ngày',
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Expanded(
              child: Text('$value ngày',
                  textAlign: TextAlign.center,
                  style: context.textStyles.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            IconButton.outlined(
              tooltip: 'Thêm 1 ngày',
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Giao trọn kế hoạch một lần" / "Có phản hồi mỗi ngày" with their
/// one-line explanations.
class BookingTypePicker extends StatelessWidget {
  const BookingTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.pricePerDay,
  });

  final BookingType value;
  final ValueChanged<BookingType> onChanged;

  /// Listed price per day of each type, when known.
  final int Function(BookingType type)? pricePerDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final t in BookingType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TypeOption(
              type: t,
              selected: value == t,
              price: pricePerDay?.call(t),
              onTap: () => onChanged(t),
            ),
          ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.type,
    required this.selected,
    required this.onTap,
    this.price,
  });

  final BookingType type;
  final bool selected;
  final VoidCallback onTap;
  final int? price;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? colors.primary : context.vl.border,
            width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.primary : context.vl.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(type.explanation,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                    if (price != null && price! > 0) ...[
                      const SizedBox(height: 2),
                      Text('${formatVnd(price!)}/ngày',
                          style: context.textStyles.labelLarge?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- reason

/// A required reason (decline, cancel). Returns the trimmed text.
Future<String?> showReasonSheet(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  required String? Function(String) validate,
  String? message,
}) =>
    _sheet<String>(
      context,
      _ReasonSheet(
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        validate: validate,
        message: message,
      ),
    );

class _ReasonSheet extends StatefulWidget {
  const _ReasonSheet({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.validate,
    this.message,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String? Function(String) validate;
  final String? message;

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.validate(_text.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_text.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: widget.title,
      children: [
        if (widget.message != null) ...[
          Text(widget.message!,
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.muted)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Lý do',
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- feedback

/// "Phản hồi ngày này": stars, "Bạn đã làm theo?" and a note for tomorrow.
Future<DayFeedbackDto?> showDayFeedbackSheet(BuildContext context,
        {required PlanDayDto day}) =>
    _sheet<DayFeedbackDto>(context, DayFeedbackSheet(day: day));

class DayFeedbackSheet extends StatefulWidget {
  const DayFeedbackSheet({super.key, required this.day});

  final PlanDayDto day;

  @override
  State<DayFeedbackSheet> createState() => _DayFeedbackSheetState();
}

class _DayFeedbackSheetState extends State<DayFeedbackSheet> {
  late int _rating = widget.day.feedback?.rating ?? 0;
  late Adherence? _adherence = widget.day.feedback?.adherence;
  late final _body = TextEditingController(text: widget.day.feedback?.body);
  bool _attempted = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _submit() {
    final adherence = _adherence;
    if (_rating == 0 || adherence == null) {
      setState(() => _attempted = true);
      return;
    }
    Navigator.of(context).pop(DayFeedbackDto(
        rating: _rating, adherence: adherence, body: _body.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final error =
        context.textStyles.bodySmall?.copyWith(color: context.colors.error);
    return _SheetBody(
      title: 'Phản hồi ${widget.day.title}',
      children: [
        Text('Bạn đánh giá ngày này', style: context.textStyles.titleSmall),
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i sao',
                onPressed: () => setState(() => _rating = i),
                icon: Icon(
                  i <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                  color: const Color(0xFFF59E0B),
                  size: 32,
                ),
              ),
          ],
        ),
        if (_attempted && _rating == 0) Text('Chọn số sao.', style: error),
        const SizedBox(height: 10),
        Text('Bạn đã làm theo?', style: context.textStyles.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final a in Adherence.values)
              ChoiceChip(
                label: Text(a.label),
                selected: _adherence == a,
                onSelected: (_) => setState(() => _adherence = a),
              ),
          ],
        ),
        if (_attempted && _adherence == null)
          Text('Chọn mức bạn đã làm theo.', style: error),
        const SizedBox(height: 14),
        TextField(
          controller: _body,
          minLines: 2,
          maxLines: 5,
          maxLength: BookingRules.maxFeedbackBody,
          decoration: const InputDecoration(
            labelText: 'Góp ý cho ngày mai',
            hintText: 'Món nào hợp, món nào cần đổi…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Gửi phản hồi'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- complaint

/// The chef's answer to a complaint: text plus optional source links.
Future<ComplaintResponseRequestDto?> showComplaintResponseSheet(
        BuildContext context) =>
    _sheet<ComplaintResponseRequestDto>(
        context, const _ComplaintResponseSheet());

class _ComplaintResponseSheet extends StatefulWidget {
  const _ComplaintResponseSheet();

  @override
  State<_ComplaintResponseSheet> createState() =>
      _ComplaintResponseSheetState();
}

class _ComplaintResponseSheetState extends State<_ComplaintResponseSheet> {
  final _text = TextEditingController();
  final _link = TextEditingController();
  final _links = <String>[];
  String? _error;
  String? _linkError;

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  void _addLink() {
    final url = _link.text.trim();
    if (!BookingRules.isHttpUrl(url)) {
      setState(() =>
          _linkError = 'Liên kết phải bắt đầu bằng http:// hoặc https://');
      return;
    }
    setState(() {
      _links.add(url);
      _link.clear();
      _linkError = null;
    });
  }

  void _submit() {
    final error = BookingRules.chefResponse(_text.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(ComplaintResponseRequestDto(
      text: _text.text.trim(),
      links: [
        for (final url in _links)
          EvidenceDto(kind: EvidenceKind.link, url: url),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Phản hồi khiếu nại',
      children: [
        Text(
          'Ban quản trị đọc phản hồi của bạn cùng khiếu nại trước khi quyết định.',
          style:
              context.textStyles.bodyMedium?.copyWith(color: context.vl.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: 'Phản hồi của bạn',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Liên kết nguồn (không bắt buộc)',
                  border: const OutlineInputBorder(),
                  errorText: _linkError,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Thêm liên kết',
              onPressed: _addLink,
              icon: const Icon(Icons.add_link_rounded),
            ),
          ],
        ),
        for (final url in _links)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.link_rounded),
            title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Bỏ liên kết',
              onPressed: () => setState(() => _links.remove(url)),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Gửi phản hồi'),
        ),
      ],
    );
  }
}
