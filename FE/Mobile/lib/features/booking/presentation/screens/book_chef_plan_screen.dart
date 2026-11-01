// lib/features/booking/presentation/screens/book_chef_plan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/navigation/app_nav.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../chef/domain/entities/chef.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_form_widgets.dart';
import '../widgets/booking_sheets.dart';
import '../widgets/number_stepper_field.dart';
import 'booking_detail_screen.dart';

/// "Đặt chuyên gia lên thực đơn": number of days, start date, type, for whom,
/// needs (goal, allergies and meals of the day prefilled from the health
/// profile), budget, notes and the card of what the chef will see. "Cho gia
/// đình" drops everything personal and asks for the number of people. The
/// estimate stays at the bottom next to "Gửi yêu cầu". Sends a request
/// (`Requested`) and opens its booking right above the shell (the directory,
/// profile and form are closed); the price is agreed in the chat.
class BookChefPlanScreen extends ConsumerStatefulWidget {
  const BookChefPlanScreen({super.key, required this.chef});

  final Chef chef;

  static Route<void> route(Chef chef) =>
      MaterialPageRoute<void>(builder: (_) => BookChefPlanScreen(chef: chef));

  @override
  ConsumerState<BookChefPlanScreen> createState() => _BookChefPlanScreenState();
}

class _BookChefPlanScreenState extends ConsumerState<BookChefPlanScreen> {
  /// The chef's limits, inside the app's.
  late final int _minDays = widget.chef.minPlanDays < BookingRules.minPlanDays
      ? BookingRules.minPlanDays
      : widget.chef.minPlanDays;
  late final int _maxDays = widget.chef.maxPlanDays > BookingRules.maxPlanDays
      ? BookingRules.maxPlanDays
      : widget.chef.maxPlanDays;

  /// 7 days when the chef takes it, otherwise their minimum.
  late int _days = NumberStepperField.clampTo(7, _minDays, _maxDays);
  bool _daysValid = true;
  late DateTime _start = addDays(vnDateOf(DateTime.now()), 1);
  BookingType _type = BookingType.dailyFeedback;
  BookingAudience _audience = BookingAudience.self;
  int _people = 4;
  bool _peopleValid = true;
  String _goal = 'maintain';
  final _allergies = <String>[];
  List<MealSlot> _pattern = MealPattern.standard;
  final _allergyInput = TextEditingController();
  final _budget = TextEditingController();
  final _needs = TextEditingController();
  final _daysKey = GlobalKey();
  final _peopleKey = GlobalKey();
  final _needsKey = GlobalKey();
  bool _share = true;
  bool _attempted = false;
  bool _sending = false;
  bool _prefilled = false;
  ShareProfileState _profileState = ShareProfileState.loading;

  /// The profile the chef would get, as the card shows it.
  Map<String, dynamic>? _healthJson;

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
    if (_profileState != ShareProfileState.loading) {
      setState(() => _profileState = ShareProfileState.loading);
    }
    try {
      final profile =
          (await ref.read(mealPlannerApiProvider).getHealthProfile())
              ?.toEntity();
      if (!mounted) return;
      if (profile == null) {
        setState(() => _profileState = ShareProfileState.missing);
        return;
      }
      setState(() {
        _goal = profile.goal.apiValue;
        for (final a in profile.allergies) {
          if (!_allergies.contains(a)) _allergies.add(a);
        }
        _pattern = MealPattern.normalize(profile.mealPattern);
        _healthJson = memberHealthFromProfile(profile);
        _profileState = ShareProfileState.loaded;
        _prefilled = true;
      });
    } catch (_) {
      // Keep the defaults; everything stays editable and nothing is shared.
      if (mounted) setState(() => _profileState = ShareProfileState.failed);
    }
  }

  bool get _family => _audience == BookingAudience.family;

  /// The switch is on and there is a profile the card could show.
  bool get _sharing =>
      !_family && _share && _profileState == ShareProfileState.loaded;

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
    if (picked != null && mounted) setState(() => _start = dateOnly(picked));
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

  String? get _needsError => _family
      ? BookingRules.familyNote(_needs.text)
      : BookingRules.needs(_needs.text);

  /// The first thing to fix, so the message under it is on screen: the bar
  /// with the button is fixed, the field may be far above it.
  GlobalKey? get _firstInvalid {
    if (!_daysValid) return _daysKey;
    if (_family && !_peopleValid) return _peopleKey;
    return _needsError != null ? _needsKey : null;
  }

  Future<void> _submit() async {
    final today = vnDateOf(DateTime.now());
    final invalid = _firstInvalid;
    if (invalid != null ||
        BookingRules.startDate(_start, today) != null ||
        _pattern.isEmpty) {
      setState(() => _attempted = true);
      final target = invalid?.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(target,
            duration: const Duration(milliseconds: 250), alignment: 0.2);
      }
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
              audience: _audience,
              familySize: _family ? _people : null,
              goal: _sharing ? _goal : null,
              allergies: List.of(_allergies),
              mealPattern: _pattern,
              budgetPerDay: _budgetValue,
              needs: _needs.text.trim(),
              shareHealthProfile: _sharing,
              healthSnapshot: _sharing ? _healthJson : null,
            ),
          );
      if (!mounted) return;
      ref.bookingChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đã gửi yêu cầu. Chuyên gia sẽ báo giá trong chat.')));
      // The directory / profile / form are done with: Back from the
      // request returns to the tab it was started from.
      AppNav.resetTo(
          Navigator.of(context), BookingDetailScreen.route(booking.id));
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
    final startError = _attempted
        ? BookingRules.startDate(_start, vnDateOf(DateTime.now()))
        : null;
    return AskAiBubbleFree(
      child: Scaffold(
        appBar: AppBar(title: const Text('Đặt chuyên gia lên thực đơn')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
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
                  Text('Số ngày',
                      key: _daysKey, style: context.textStyles.titleMedium),
                  const SizedBox(height: 6),
                  NumberStepperField(
                    fieldKey: const ValueKey('booking-days'),
                    value: _days,
                    min: _minDays,
                    max: _maxDays,
                    unit: 'ngày',
                    onChanged: (v) => setState(() => _days = v),
                    onValidityChanged: (v) => setState(() => _daysValid = v),
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
                    pricePerDay: (t) => chef.priceFor(
                        dailyFeedback: t == BookingType.dailyFeedback),
                  ),
                  const SizedBox(height: 12),
                  Text(_family ? 'Nhu cầu của gia đình' : 'Nhu cầu của bạn',
                      style: context.textStyles.titleMedium),
                  if (_prefilled && !_family)
                    Text(
                        'Lấy từ Hồ sơ sức khoẻ — sửa được cho riêng yêu cầu này.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
                  const SizedBox(height: 8),
                  Text('Đặt cho', style: context.textStyles.titleSmall),
                  const SizedBox(height: 6),
                  SegmentedButton<BookingAudience>(
                    showSelectedIcon: false,
                    segments: [
                      for (final a in BookingAudience.values)
                        ButtonSegment(value: a, label: Text(a.label)),
                    ],
                    selected: {_audience},
                    onSelectionChanged: (s) =>
                        setState(() => _audience = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (_family) ...[
                    Text('Số người',
                        key: _peopleKey, style: context.textStyles.titleSmall),
                    const SizedBox(height: 6),
                    NumberStepperField(
                      fieldKey: const ValueKey('booking-people'),
                      value: _people,
                      min: BookingRules.minFamilySize,
                      max: BookingRules.maxFamilySize,
                      unit: 'người',
                      onChanged: (v) => setState(() => _people = v),
                      onValidityChanged: (v) =>
                          setState(() => _peopleValid = v),
                    ),
                    const SizedBox(height: 12),
                  ] else if (_sharing) ...[
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
                  ],
                  Text('Dị ứng', style: context.textStyles.titleSmall),
                  if (_family)
                    Text('Thêm dị ứng của mọi người trong nhà.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
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
                              hintText: 'Thêm thành phần dị ứng…'),
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
                  Text('Các bữa trong ngày',
                      style: context.textStyles.titleSmall),
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
                  if (_pattern.isEmpty)
                    Text('Chọn ít nhất 1 bữa', style: error),
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
                    key: _needsKey,
                    controller: _needs,
                    minLines: _family ? 2 : 4,
                    maxLines: 10,
                    maxLength: BookingRules.maxNeeds,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _family
                          ? 'Ghi chú cho chuyên gia (không bắt buộc)'
                          : 'Nhu cầu & ghi chú',
                      hintText: _family
                          ? 'VD: Nhà có 2 bé, thích món nước, nấu một nồi ăn cả nhà…'
                          : 'VD: Mình muốn giảm 3 kg trong tháng, bữa sáng dưới 15 phút, không ăn hành sống…',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                      errorText: _attempted ? _needsError : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SharedProfileCard(
                    audience: _audience,
                    familySize: _people,
                    allergies: _allergies,
                    goal: _goal,
                    health: _healthJson == null
                        ? null
                        : MemberHealthDto.fromJson(_healthJson!),
                    state: _profileState,
                    share: _share,
                    onShareChanged: (v) => setState(() => _share = v),
                    onRetry: _prefill,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bạn chưa phải trả tiền lúc này. Sau khi hai bên đồng ý giá, bạn '
                    'thanh toán và VeganLife giữ tiền đến ${BookingRules.holdDays} '
                    'ngày sau khi chuyên gia hoàn thành hợp đồng.',
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.muted),
                  ),
                ],
              ),
            ),
            BookingEstimateBar(
              estimate: BookingEstimate(
                days: _days,
                pricePerDay: _perDay,
                type: _type,
                audience: _audience,
                familySize: _people,
                daysValid: _daysValid,
              ),
              sending: _sending,
              onSubmit: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
