// lib/features/booking/presentation/screens/book_chef_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_sheets.dart';
import 'booking_detail_screen.dart';

/// "Đặt chuyên gia lên thực đơn": number of days, start date, type, needs
/// (goal, allergies and meals of the day prefilled from the health profile),
/// budget, notes and whether to share the health profile. Sends a request
/// (`Requested`) and opens its booking; the price is agreed in the chat.
class BookChefPlanScreen extends ConsumerStatefulWidget {
  const BookChefPlanScreen({super.key, required this.chef});

  final Chef chef;

  static Route<void> route(Chef chef) =>
      MaterialPageRoute<void>(builder: (_) => BookChefPlanScreen(chef: chef));

  @override
  ConsumerState<BookChefPlanScreen> createState() => _BookChefPlanScreenState();
}

class _BookChefPlanScreenState extends ConsumerState<BookChefPlanScreen> {
  /// 7 days when the chef takes it, otherwise their minimum.
  late int _days = 7 >= widget.chef.minPlanDays && 7 <= widget.chef.maxPlanDays
      ? 7
      : widget.chef.minPlanDays;
  late DateTime _start = addDays(vnDateOf(DateTime.now()), 1);
  BookingType _type = BookingType.dailyFeedback;
  String _goal = 'maintain';
  final _allergies = <String>[];
  List<MealSlot> _pattern = MealPattern.standard;
  final _allergyInput = TextEditingController();
  final _budget = TextEditingController();
  final _needs = TextEditingController();
  bool _share = true;
  bool _attempted = false;
  bool _sending = false;
  bool _prefilled = false;

  /// `false` once we know the member has no health profile to share yet.
  bool _hasHealthProfile = true;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _allergyInput.dispose();
    _budget.dispose();
    _needs.dispose();
    super.dispose();
  }

  /// Goal, allergies and "Các bữa trong ngày" from the health profile.
  /// Without one (new account) the defaults stay and nothing is shared.
  Future<void> _prefill() async {
    try {
      final profile =
          (await ref.read(mealPlannerApiProvider).getHealthProfile())
              ?.toEntity();
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _hasHealthProfile = false;
          _share = false;
        });
        return;
      }
      setState(() {
        _goal = profile.goal.apiValue;
        _allergies
          ..clear()
          ..addAll(profile.allergies);
        _pattern = MealPattern.normalize(profile.mealPattern);
        _prefilled = true;
      });
    } on ApiException {
      // Keep the defaults; everything stays editable.
    }
  }

  int get _perDay =>
      widget.chef.priceFor(dailyFeedback: _type == BookingType.dailyFeedback);

  Future<void> _pickStart() async {
    final first = addDays(vnDateOf(DateTime.now()), 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(first) ? first : _start,
      firstDate: first,
      lastDate: addDays(first, 180),
      helpText: 'Bắt đầu từ',
    );
    if (picked != null) setState(() => _start = dateOnly(picked));
  }

  void _addAllergy() {
    final text = _allergyInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_allergies.contains(text)) _allergies.add(text);
      _allergyInput.clear();
    });
  }

  int? get _budgetValue {
    final raw = _budget.text.trim();
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  Future<void> _submit() async {
    final today = vnDateOf(DateTime.now());
    if (BookingRules.needs(_needs.text) != null ||
        BookingRules.startDate(_start, today) != null ||
        _pattern.isEmpty) {
      setState(() => _attempted = true);
      return;
    }
    setState(() => _sending = true);
    try {
      final booking = await ref.read(bookingApiProvider).createBooking(
            CreateBookingRequestDto(
              chefId: widget.chef.id,
              bookingType: _type,
              planDays: _days,
              startDate: _start,
              goal: _goal,
              allergies: List.of(_allergies),
              mealPattern: _pattern,
              budgetPerDay: _budgetValue,
              needs: _needs.text.trim(),
              shareHealthProfile: _share,
            ),
          );
      if (!mounted) return;
      ref.bookingChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã gửi yêu cầu. Chuyên gia sẽ báo giá trong chat.')));
      Navigator.of(context)
          .pushReplacement(BookingDetailScreen.route(booking.id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chef = widget.chef;
    final error =
        context.textStyles.bodySmall?.copyWith(color: context.colors.error);
    final presets = [
      for (final d in BookingRules.dayPresets)
        if (d >= chef.minPlanDays && d <= chef.maxPlanDays) d,
    ];
    final total = _days * _perDay;
    final startError = _attempted
        ? BookingRules.startDate(_start, vnDateOf(DateTime.now()))
        : null;
    return AskAiBubbleFree(
      child: Scaffold(
        appBar: AppBar(title: const Text('Đặt chuyên gia lên thực đơn')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                UserAvatar(name: chef.name, size: 44, verified: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chef.name,
                          style: context.textStyles.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(chef.headline,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.vl.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Số ngày', style: context.textStyles.titleMedium),
            const SizedBox(height: 6),
            DayCountPicker(
              value: _days,
              presets: presets,
              min: chef.minPlanDays,
              max: chef.maxPlanDays,
              onChanged: (v) => setState(() => _days = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Bắt đầu từ'),
              subtitle: Text(
                startError ??
                    '${weekdayLong(_start)}, ${formatDayMonth(_start)}/${_start.year}',
                style: startError == null
                    ? null
                    : TextStyle(color: context.colors.error),
              ),
              trailing: const Text('Đổi'),
              onTap: _pickStart,
            ),
            const SizedBox(height: 4),
            Text('Hình thức', style: context.textStyles.titleMedium),
            const SizedBox(height: 6),
            BookingTypePicker(
              value: _type,
              onChanged: (t) => setState(() => _type = t),
              pricePerDay: (t) =>
                  chef.priceFor(dailyFeedback: t == BookingType.dailyFeedback),
            ),
            const SizedBox(height: 12),
            Text('Nhu cầu của bạn', style: context.textStyles.titleMedium),
            if (_prefilled)
              Text('Lấy từ Hồ sơ sức khoẻ — sửa được cho riêng yêu cầu này.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 8),
            Text('Mục tiêu', style: context.textStyles.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final g in bookingGoalChoices)
                  ChoiceChip(
                    label: Text(bookingGoalLabel(g)),
                    selected: _goal == g,
                    onSelected: (_) => setState(() => _goal = g),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Dị ứng', style: context.textStyles.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_allergies.isEmpty)
                  Text('Không có',
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted)),
                for (final a in _allergies)
                  InputChip(
                    label: Text(allergenLabel(a)),
                    onDeleted: () => setState(() => _allergies.remove(a)),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _allergyInput,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addAllergy(),
                    decoration: const InputDecoration(
                        hintText: 'Thêm thành phần bạn dị ứng…'),
                  ),
                ),
                IconButton(
                  tooltip: 'Thêm dị ứng',
                  onPressed: _addAllergy,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Các bữa trong ngày', style: context.textStyles.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in MealSlot.values)
                  FilterChip(
                    label: Text(s.label),
                    selected: _pattern.contains(s),
                    onSelected: (on) => setState(() => _pattern =
                        MealPattern.normalize(on
                            ? [..._pattern, s]
                            : _pattern.where((x) => x != s))),
                  ),
              ],
            ),
            if (_pattern.isEmpty) Text('Chọn ít nhất 1 bữa', style: error),
            const SizedBox(height: 14),
            TextField(
              controller: _budget,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Ngân sách đi chợ mỗi ngày (không bắt buộc)',
                suffixText: 'đ',
                helperText: _budgetValue == null
                    ? null
                    : '${formatVnd(_budgetValue!)}/ngày',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _needs,
              minLines: 4,
              maxLines: 10,
              maxLength: BookingRules.maxNeeds,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nhu cầu & ghi chú',
                hintText:
                    'VD: Mình muốn giảm 3 kg trong tháng, bữa sáng dưới 15 phút, không ăn hành sống…',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                errorText: _attempted ? BookingRules.needs(_needs.text) : null,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _share,
              onChanged:
                  _hasHealthProfile ? (v) => setState(() => _share = v) : null,
              title: const Text('Chia sẻ hồ sơ sức khoẻ với chuyên gia'),
              subtitle: Text(_hasHealthProfile
                  ? 'Chiều cao, cân nặng, nhu cầu năng lượng — chỉ chuyên gia này xem được.'
                  : 'Bạn chưa có hồ sơ sức khoẻ. Thiết lập ở Tôi › Hồ sơ sức khoẻ để chia sẻ.'),
            ),
            const SizedBox(height: 8),
            VLCard(
              color: context.vl.successContainer,
              borderColor: Colors.transparent,
              child: Text(
                '≈ $_days ngày × ${formatVnd(_perDay)} = ${formatVnd(total)} '
                '(giá cuối do hai bên thoả thuận)',
                style: context.textStyles.bodyMedium?.copyWith(
                    color: context.vl.onSuccessContainer,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Bạn chưa phải trả tiền lúc này. Sau khi hai bên đồng ý giá, bạn thanh toán qua '
              'PaymentOS và VeganLife giữ tiền đến 3 ngày sau khi kế hoạch kết thúc.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(_sending ? 'Đang gửi…' : 'Gửi yêu cầu'),
            ),
          ],
        ),
      ),
    );
  }
}
