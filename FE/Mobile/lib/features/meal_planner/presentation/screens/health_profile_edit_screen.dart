// lib/features/meal_planner/presentation/screens/health_profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../profile/presentation/controllers/profile_controller.dart';
import '../../data/meal_planner_api_service.dart';
import '../../domain/entities/health_profile.dart';
import '../controllers/meal_plan_controller.dart';
import '../widgets/bmi_gauge.dart';

/// Edit height, weight, goal and allergies with a live BMI preview.
/// Opened from Thực đơn (health card) and Tôi ("Hồ sơ sức khoẻ").
class HealthProfileEditScreen extends ConsumerStatefulWidget {
  const HealthProfileEditScreen({super.key});

  /// Pops with `true` once the profile was saved.
  static Route<bool> route() => MaterialPageRoute<bool>(
        builder: (_) => const HealthProfileEditScreen(),
      );

  /// Allergens offered as chips (labels from `allergenLabel`).
  static const allergenIds = [
    'peanut',
    'tree_nut',
    'soy',
    'gluten',
    'sesame',
    'mustard',
    'celery',
  ];

  @override
  ConsumerState<HealthProfileEditScreen> createState() =>
      _HealthProfileEditScreenState();
}

class _HealthProfileEditScreenState
    extends ConsumerState<HealthProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  HealthProfile? _initial;
  Object? _loadError;
  HealthGoal _goal = HealthGoal.maintain;
  final Set<String> _allergies = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _height.addListener(_changed);
    _weight.addListener(_changed);
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final profile =
          (await ref.read(mealPlannerApiProvider).getHealthProfile())
              .toEntity();
      if (!mounted) return;
      setState(() {
        _initial = profile;
        _height.text = profile.heightCm.round().toString();
        _weight.text = _weightText(profile.weightKg);
        _goal = profile.goal;
        _allergies
          ..clear()
          ..addAll(profile.allergies);
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

  /// BMI of what is typed, or `null` while either value is invalid.
  double? get _previewBmi {
    if (validateHeight(_height.text) != null ||
        validateWeight(_weight.text) != null) {
      return null;
    }
    return Bmi.calculate(heightCm: _heightCm!, weightKg: _weightKg!);
  }

  bool get _dirty {
    final initial = _initial;
    if (initial == null) return false;
    return _heightCm != initial.heightCm.roundToDouble() ||
        _weightKg != initial.weightKg ||
        _goal != initial.goal ||
        _allergies.length != initial.allergies.length ||
        !_allergies.containsAll(initial.allergies);
  }

  Future<void> _save() async {
    final initial = _initial;
    if (initial == null || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final planner = ref.read(mealPlanControllerProvider.notifier);
    try {
      await planner.updateHealthProfile(
        heightCm: _heightCm!,
        weightKg: _weightKg!,
        goal: _goal,
        allergies: [
          for (final id in HealthProfileEditScreen.allergenIds)
            if (_allergies.contains(id)) id,
          // Keep allergens this screen doesn't offer.
          ..._allergies
              .where((a) => !HealthProfileEditScreen.allergenIds.contains(a)),
        ],
        dietaryRestrictions: initial.dietaryRestrictions,
      );
      ref.invalidate(profileHealthProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: const Text('Đã lưu hồ sơ sức khoẻ'),
          action: SnackBarAction(
            label: 'Tạo lại thực đơn',
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
            if (_initial != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: dirty && !_saving ? _save : null,
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
              'Đăng nhập để lưu chiều cao, cân nặng, mục tiêu và dị ứng cho thực đơn AI.',
          benefits: const [
            'BMI và mục tiêu dinh dưỡng theo chuẩn châu Á',
            'Thực đơn tự loại món chứa chất bạn dị ứng',
          ],
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadError case final error?) {
      return Center(
        child: SingleChildScrollView(
            child: ErrorStateView(error: error, onRetry: _load)),
      );
    }
    if (_initial == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final vl = context.vl;
    final bmi = _previewBmi;
    return Form(
      key: _form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
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
                      const SizedBox(height: 4),
                      Text(
                        'Cập nhật ngay khi bạn sửa chiều cao, cân nặng.',
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Chỉ số cơ thể', style: context.textStyles.titleMedium),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          Text('Mục tiêu', style: context.textStyles.titleMedium),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          Text('Dị ứng', style: context.textStyles.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Thực đơn AI sẽ tránh các món chứa thành phần này; món từ nguồn khác được gắn cảnh báo.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in HealthProfileEditScreen.allergenIds)
                FilterChip(
                  label: Text(allergenLabel(id)),
                  selected: _allergies.contains(id),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _allergies.add(id);
                    } else {
                      _allergies.remove(id);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Dùng cho thực đơn AI và chỉ chia sẻ với chuyên gia khi bạn đặt lịch.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
        ],
      ),
    );
  }
}
