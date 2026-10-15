// lib/features/chef_studio/presentation/screens/suggestion_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/data/chef_suggestion_api_service.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../data/models/chef_client_models.dart';
import '../controllers/chef_clients_controllers.dart';
import '../widgets/chef_only_gate.dart';

/// "Đề xuất món" for one client: dish name, kcal, ingredients, a note and
/// the meal / day the chef has in mind. Sent dishes appear in the client's
/// Thực đơn › Chọn món › Từ chuyên gia. Pops with the snackbar message.
class SuggestionFormScreen extends ConsumerStatefulWidget {
  const SuggestionFormScreen({super.key, required this.client});

  final ChefClientDto client;

  static Route<String> route(ChefClientDto client) => MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => SuggestionFormScreen(client: client),
      );

  @override
  ConsumerState<SuggestionFormScreen> createState() =>
      _SuggestionFormScreenState();
}

class _SuggestionFormScreenState extends ConsumerState<SuggestionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _ingredients = TextEditingController();
  final _note = TextEditingController();
  MealSlot? _slot;
  DateTime? _day;
  bool _sending = false;
  bool _attempted = false;

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _ingredients.dispose();
    _note.dispose();
    super.dispose();
  }

  /// One per line or separated by commas.
  List<String> get _ingredientList => _ingredients.text
      .split(RegExp(r'[\n,]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  String? _validateName(String? v) {
    final n = v?.trim() ?? '';
    if (n.length < SuggestionRules.nameMin) {
      return 'Nhập tên món (ít nhất ${SuggestionRules.nameMin} ký tự).';
    }
    if (n.length > SuggestionRules.nameMax) {
      return 'Tên món tối đa ${SuggestionRules.nameMax} ký tự.';
    }
    return null;
  }

  String? _validateKcal(String? v) {
    final raw = v?.trim() ?? '';
    if (raw.isEmpty) return null;
    final kcal = int.tryParse(raw);
    if (kcal == null ||
        kcal < SuggestionRules.caloriesMin ||
        kcal > SuggestionRules.caloriesMax) {
      return 'Từ ${SuggestionRules.caloriesMin} đến ${formatInt(SuggestionRules.caloriesMax)} kcal, hoặc để trống.';
    }
    return null;
  }

  String? _validateIngredients(String? _) =>
      _ingredientList.length > SuggestionRules.ingredientsMax
          ? 'Tối đa ${SuggestionRules.ingredientsMax} nguyên liệu.'
          : null;

  Future<void> _send() async {
    final invalid = _form.currentState?.validateGranularly() ?? const {};
    if (invalid.isNotEmpty) {
      setState(() => _attempted = true);
      final target = invalid.first.context;
      if (target.mounted) {
        await Scrollable.ensureVisible(target,
            alignment: 0.2, duration: const Duration(milliseconds: 250));
      }
      return;
    }
    final request = SendChefSuggestionDto(
      name: _name.text.trim(),
      calories: int.tryParse(_kcal.text.trim()),
      ingredients: _ingredientList,
      note: _note.text.trim(),
      slot: _slot,
      targetDate: _day,
    );
    setState(() => _sending = true);
    try {
      await ref
          .read(chefSuggestionApiProvider)
          .send(widget.client.userId, request);
      HapticFeedback.lightImpact();
      ref.read(chefSuggestionRevisionProvider.notifier).bump();
      if (!mounted) return;
      Navigator.of(context).pop(
          'Đã gửi "${request.name}" cho ${widget.client.fullName}. Món sẽ hiện trong Thực đơn › Từ chuyên gia của khách.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final allergies = client.health?.allergies ?? const <String>[];
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    String dayLabel(DateTime d) => switch (d.difference(today).inDays) {
          0 => 'Hôm nay',
          1 => 'Ngày mai',
          _ => '${weekdayShort(d)} ${formatDayMonth(d)}',
        };

    return Scaffold(
      appBar: AppBar(title: const Text('Đề xuất món')),
      body: ChefOnlyGate(
        child: Form(
          key: _form,
          autovalidateMode: _attempted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          // Not lazy: every field must exist to be validated and scrolled to.
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    UserAvatar(name: client.fullName, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Gửi cho ${client.fullName}',
                              style: context.textStyles.titleMedium),
                          Text(
                            'Món sẽ hiện trong Thực đơn › Từ chuyên gia của khách.',
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: context.vl.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (allergies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  VLCard(
                    color: context.vl.cautionContainer,
                    borderColor: context.vl.cautionBorder,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: context.vl.onCautionContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Khách dị ứng: ${allergies.map(allergenLabel).join(', ')}. '
                            'Món có chất này sẽ bị cảnh báo trong thực đơn của khách.',
                            style: context.textStyles.bodySmall?.copyWith(
                                color: context.vl.onCautionContainer,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  maxLength: SuggestionRules.nameMax,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Tên món',
                    hintText: 'VD: Bún gạo lứt xào rau củ',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _kcal,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Năng lượng (kcal, không bắt buộc)',
                    hintText: '450',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateKcal,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ingredients,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Nguyên liệu (không bắt buộc)',
                    hintText:
                        'Mỗi dòng một nguyên liệu, hoặc cách nhau dấu phẩy',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateIngredients,
                ),
                const SizedBox(height: 16),
                Text('Bữa', style: context.textStyles.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Bữa nào cũng được'),
                      selected: _slot == null,
                      onSelected: (_) => setState(() => _slot = null),
                    ),
                    for (final slot in MealSlot.values)
                      ChoiceChip(
                        label: Text(slot.label),
                        selected: _slot == slot,
                        onSelected: (_) => setState(() => _slot = slot),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Dành cho ngày', style: context.textStyles.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Ngày nào cũng được'),
                      selected: _day == null,
                      onSelected: (_) => setState(() => _day = null),
                    ),
                    for (final d in days)
                      ChoiceChip(
                        label: Text(dayLabel(d)),
                        selected: _day == d,
                        onSelected: (_) => setState(() => _day = d),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: SuggestionRules.noteMax,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Lời nhắn cho khách (không bắt buộc)',
                    hintText: 'VD: Giàu đạm, hợp bữa tối sau buổi tập.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: _sending
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.onPrimary),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_sending ? 'Đang gửi…' : 'Gửi đề xuất'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
