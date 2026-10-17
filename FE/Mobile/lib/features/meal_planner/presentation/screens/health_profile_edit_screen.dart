// lib/features/meal_planner/presentation/screens/health_profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/energy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../data/meal_planner_api_service.dart';
import '../../domain/entities/health_profile.dart';
import '../../domain/entities/meal_slot.dart';
import '../controllers/meal_plan_controller.dart';
import '../widgets/allergy_input.dart';
import '../widgets/bmi_gauge.dart';

/// Edit body stats (height, weight, gender, birth year, activity), goal,
/// allergies (free text with suggestions) and the meals of the day, with a
/// live BMI and energy-need preview. Opened from Thực đơn (health card) and
/// Tôi ("Hồ sơ sức khoẻ"). A member without a profile yet (new account)
/// gets the same form empty ("Thiết lập hồ sơ sức khoẻ").
class HealthProfileEditScreen extends ConsumerStatefulWidget {
  const HealthProfileEditScreen({super.key});

  /// Pops with `true` once the profile was saved.
  static Route<bool> route() => MaterialPageRoute<bool>(
        builder: (_) => const HealthProfileEditScreen(),
      );

  @override
  ConsumerState<HealthProfileEditScreen> createState() =>
      _HealthProfileEditScreenState();
}

class _HealthProfileEditScreenState
    extends ConsumerState<HealthProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _birthYear = TextEditingController();

  /// The saved profile; `null` while loading and when there is none yet
  /// (then [_loaded] tells the two apart).
  HealthProfile? _initial;
  bool _loaded = false;
  Object? _loadError;
  HealthGoal _goal = HealthGoal.maintain;
  Gender? _gender;
  ActivityLevel _activity = ActivityLevel.light;
  List<String> _allergies = [];
  Set<MealSlot> _pattern = {...MealPattern.standard};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _height.addListener(_changed);
    _weight.addListener(_changed);
    _birthYear.addListener(_changed);
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _birthYear.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final profile =
          (await ref.read(mealPlannerApiProvider).getHealthProfile())
              ?.toEntity();
      if (!mounted) return;
      setState(() {
        _loaded = true;
        // None yet: an empty form with the defaults below.
        if (profile == null) return;
        _initial = profile;
        _height.text = profile.heightCm.round().toString();
        _weight.text = _weightText(profile.weightKg);
        _birthYear.text = profile.birthYear?.toString() ?? '';
        _goal = profile.goal;
        _gender = profile.gender;
        _activity = profile.activityLevel;
        _allergies = [...profile.allergies];
        _pattern = {...profile.mealPattern};
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// 66 → "66", 65.5 → "65,5".
  static String _weightText(double kg) =>
      kg == kg.roundToDouble() ? kg.round().toString() : formatDecimal(kg);

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  double? get _heightCm => _parse(_height.text);
  double? get _weightKg => _parse(_weight.text);
  int? get _year => int.tryParse(_birthYear.text.trim());

  static String? validateHeight(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Nhập chiều cao.';
    final cm = _parse(text);
    if (cm == null || cm < 100 || cm > 230) {
      return 'Chiều cao từ 100 đến 230 cm';
    }
    return null;
  }

  static String? validateWeight(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Nhập cân nặng.';
    final kg = _parse(text);
    if (kg == null) return 'Cân nặng chưa hợp lệ.';
    final decimals = text.replaceAll(',', '.').split('.');
    if (decimals.length > 1 && decimals[1].length > 1) {
      return 'Cân nặng chỉ lấy 1 chữ số thập phân';
    }
    if (kg < 30 || kg > 250) return 'Cân nặng từ 30 đến 250 kg';
    return null;
  }

  /// Optional, but when typed it must give an age of 13–100.
  static String? validateBirthYear(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final year = int.tryParse(text);
    if (year == null || !Energy.isValidBirthYear(year)) {
      return 'Năm sinh không hợp lệ (13–100 tuổi)';
    }
    return null;
  }

  /// BMI of what is typed, or `null` while either value is invalid.
  double? get _previewBmi {
    if (validateHeight(_height.text) != null ||
        validateWeight(_weight.text) != null) {
      return null;
    }
    return Bmi.calculate(heightCm: _heightCm!, weightKg: _weightKg!);
  }

  /// The energy estimate of what is typed, or `null` while incomplete.
  HealthProfile? get _preview {
    final bmi = _previewBmi;
    final year = _year;
    if (bmi == null ||
        _gender == null ||
        year == null ||
        validateBirthYear(_birthYear.text) != null) {
      return null;
    }
    return HealthProfile(
      heightCm: _heightCm!,
      weightKg: _weightKg!,
      bmi: bmi,
      goal: _goal,
      gender: _gender,
      birthYear: year,
      activityLevel: _activity,
    );
  }

  bool get _dirty {
    if (!_loaded) return false;
    final initial = _initial;
    if (initial == null) {
      // Setting one up: anything entered or picked.
      return _height.text.trim().isNotEmpty ||
          _weight.text.trim().isNotEmpty ||
          _birthYear.text.trim().isNotEmpty ||
          _goal != HealthGoal.maintain ||
          _gender != null ||
          _activity != ActivityLevel.light ||
          _allergies.isNotEmpty ||
          _pattern.length != MealPattern.standard.length ||
          !_pattern.containsAll(MealPattern.standard);
    }
    return _heightCm != initial.heightCm.roundToDouble() ||
        _weightKg != initial.weightKg ||
        _goal != initial.goal ||
        _gender != initial.gender ||
        _year != initial.birthYear ||
        _activity != initial.activityLevel ||
        _allergies.length != initial.allergies.length ||
        !_allergies.toSet().containsAll(initial.allergies) ||
        _pattern.length != initial.mealPattern.length ||
        !_pattern.containsAll(initial.mealPattern);
  }

  bool get _patternChanged {
    final initial = _initial;
    return initial != null &&
        (_pattern.length != initial.mealPattern.length ||
            !_pattern.containsAll(initial.mealPattern));
  }

  Future<void> _save() async {
    final initial = _initial;
    if (!_loaded ||
        _pattern.isEmpty ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final keepSnack = MediaQuery.accessibleNavigationOf(context);
    final navigator = Navigator.of(context);
    final planner = ref.read(mealPlanControllerProvider.notifier);
    final hasPlan =
        ref.read(mealPlanControllerProvider).valueOrNull?.plan != null;
    final regenerates = _patternChanged && hasPlan;
    try {
      await planner.updateHealthProfile(
        heightCm: _heightCm!,
        weightKg: _weightKg!,
        goal: _goal,
        allergies: _allergies,
        dietaryRestrictions: initial?.dietaryRestrictions ?? const [],
        gender: _gender,
        birthYear: _year,
        activityLevel: _activity,
        mealPattern: MealPattern.normalize(_pattern),
      );
      ref.invalidate(profileHealthProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          persist: keepSnack,
          content: Text(regenerates
              ? 'Đã lưu hồ sơ sức khoẻ. Đang tạo lại thực đơn theo các bữa bạn chọn…'
              : 'Đã lưu hồ sơ sức khoẻ'),
          action: regenerates
              ? null
              : SnackBarAction(
                  label: hasPlan ? 'Tạo lại thực đơn' : 'Tạo thực đơn',
                  onPressed: () => planner.generatePlan(),
                ),
        ));
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ thay đổi?'),
        content: const Text('Thông tin bạn vừa sửa chưa được lưu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ thay đổi'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop(false);
  }

  Future<void> _pickYear() async {
    final now = DateTime.now();
    final current = _year ?? now.year - 25;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chọn năm sinh'),
        content: SizedBox(
          width: 300,
          height: 320,
          child: YearPicker(
            firstDate: DateTime(now.year - Energy.maxAge),
            lastDate: DateTime(now.year - Energy.minAge),
            selectedDate: DateTime(current.clamp(
                now.year - Energy.maxAge, now.year - Energy.minAge)),
            onChanged: (d) => Navigator.of(context).pop(d.year),
          ),
        ),
      ),
    );
    if (picked != null) _birthYear.text = '$picked';
  }

  @override
  Widget build(BuildContext context) {
    final dirty = _dirty;
    return PopScope<bool>(
      canPop: !dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hồ sơ sức khoẻ'),
          actions: [
            if (_loaded)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed:
                      dirty && !_saving && _pattern.isNotEmpty ? _save : null,
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
                ),
              ),
          ],
        ),
        body: GuestGate(
          icon: Icons.monitor_heart_outlined,
          title: 'Hồ sơ sức khoẻ của bạn',
          message:
              'Đăng nhập để lưu chỉ số cơ thể, mục tiêu, dị ứng và các bữa trong ngày cho thực đơn AI.',
          benefits: const [
            'BMI và nhu cầu năng lượng theo chỉ số của bạn',
            'Thực đơn tự loại món chứa chất bạn dị ứng',
          ],
          child: _body(context),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
                header: true,
                child: Text(title, style: context.textStyles.titleMedium)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted)),
            ],
          ],
        ),
      );

  Widget _body(BuildContext context) {
    if (_loadError case final error?) {
      return Center(
        child: SingleChildScrollView(
            child: ErrorStateView(error: error, onRetry: _load)),
      );
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final vl = context.vl;
    final bmi = _previewBmi;
    final energy = _preview;
    final validYear = validateBirthYear(_birthYear.text) == null ? _year : null;
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          if (_initial == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Thiết lập hồ sơ sức khoẻ',
                      style: context.textStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Bạn chưa có hồ sơ sức khoẻ. Điền chỉ số cơ thể, mục tiêu '
                    'và dị ứng rồi bấm "Lưu" để AI tính nhu cầu năng lượng và '
                    'lên thực đơn phù hợp.',
                    style:
                        context.textStyles.bodySmall?.copyWith(color: vl.muted),
                  ),
                ],
              ),
            ),
          VLCard(
            child: Row(
              children: [
                if (bmi != null)
                  BmiGauge(bmi: bmi, width: 120)
                else
                  SizedBox(
                    width: 120,
                    child: Icon(Icons.monitor_weight_outlined,
                        size: 48, color: vl.muted),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bmi == null
                            ? 'Nhập chiều cao và cân nặng hợp lệ để xem BMI'
                            : 'BMI ${formatDecimal(bmi)} · ${Bmi.categorize(bmi).label} (chuẩn châu Á)',
                        key: const ValueKey('bmi-preview'),
                        style: context.textStyles.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      if (energy != null) ...[
                        Text(
                          'Nhu cầu ≈ ${Energy.formatKcal(energy.tdee!)} kcal/ngày',
                          key: const ValueKey('energy-preview'),
                          style: context.textStyles.titleSmall
                              ?.copyWith(color: context.colors.primary),
                        ),
                        Text(
                          'BMR ${Energy.formatKcal(energy.bmr!)} kcal · '
                          'thực đơn nhắm ${Energy.formatKcal(energy.dailyKcalTarget!)} kcal (${_goal.label.toLowerCase()})',
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: vl.muted),
                        ),
                      ] else
                        Text(
                          'Thêm giới tính và năm sinh để tính nhu cầu năng lượng chính xác hơn',
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: vl.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _section(context, 'Chỉ số cơ thể'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: validateHeight,
                  decoration: const InputDecoration(
                    labelText: 'Chiều cao (cm)',
                    errorMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _weight,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: validateWeight,
                  decoration: const InputDecoration(
                    labelText: 'Cân nặng (kg)',
                    errorMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Giới tính', style: context.textStyles.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<Gender>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              for (final g in Gender.values)
                ButtonSegment(value: g, label: Text(g.label)),
            ],
            selected: {if (_gender != null) _gender!},
            onSelectionChanged: (v) =>
                setState(() => _gender = v.isEmpty ? _gender : v.first),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _birthYear,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: validateBirthYear,
            decoration: InputDecoration(
              labelText: 'Năm sinh',
              hintText: 'VD: 1997',
              errorMaxLines: 2,
              suffixText: validYear == null
                  ? null
                  : '${Energy.ageFrom(validYear)} tuổi',
              border: const OutlineInputBorder(),
              prefixIcon: IconButton(
                tooltip: 'Chọn năm sinh',
                onPressed: _pickYear,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Mức vận động', style: context.textStyles.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in ActivityLevel.values)
                ChoiceChip(
                  label: Text(a.label),
                  selected: _activity == a,
                  onSelected: (_) => setState(() => _activity = a),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_activity.description,
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          _section(context, 'Mục tiêu'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final goal in HealthGoal.values)
                ChoiceChip(
                  label: Text(goal.label),
                  selected: _goal == goal,
                  onSelected: (_) => setState(() => _goal = goal),
                ),
            ],
          ),
          _section(context, 'Dị ứng',
              hint:
                  'Thực đơn AI sẽ tránh các thành phần này; món từ nguồn khác được gắn cảnh báo.'),
          AllergyInput(
            values: _allergies,
            onChanged: (v) => setState(() => _allergies = v),
          ),
          _section(context, 'Các bữa trong ngày',
              hint:
                  'Thực đơn sẽ có các bữa này mỗi ngày; bạn vẫn thêm được bữa cho riêng một ngày.'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in MealPatternPreset.values)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: MealPatternPreset.of(_pattern) == preset,
                  onSelected: (_) =>
                      setState(() => _pattern = {...preset.slots}),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final slot in MealSlot.values)
                FilterChip(
                  label: Text(slot.label),
                  selected: _pattern.contains(slot),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _pattern.add(slot);
                    } else {
                      _pattern.remove(slot);
                    }
                  }),
                ),
            ],
          ),
          if (_pattern.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Chọn ít nhất 1 bữa',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.colors.error)),
            )
          else if (_patternChanged)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Lưu xong, thực đơn tuần này sẽ được tạo lại theo các bữa mới.',
                  style:
                      context.textStyles.bodySmall?.copyWith(color: vl.muted)),
            ),
          const SizedBox(height: 20),
          Text(
            'Dùng cho thực đơn AI và chỉ chia sẻ với chuyên gia khi bạn đặt chuyên gia. Ước tính năng lượng theo công thức Mifflin–St Jeor, chỉ mang tính tham khảo.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
        ],
      ),
    );
  }
}
