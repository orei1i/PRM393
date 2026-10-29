// lib/features/booking/presentation/screens/plan_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart' show AskAiBubbleFree;
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../data/booking_api_service.dart';
import '../../data/models/booking_models.dart';
import '../../domain/booking_enums.dart';
import '../../domain/booking_rules.dart';
import '../controllers/booking_controllers.dart';
import '../widgets/booking_plan_tab.dart';

/// A day being edited: its meals by slot and the day note.
class _Draft {
  _Draft.from(PlanDayDto day)
      : meals = {for (final m in day.meals) m.slot: m},
        note = day.chefNote ?? '';

  final Map<MealSlot, PlanMealDto> meals;
  String note;
  bool dirty = false;
}

/// "Soạn kế hoạch" (chef): day chips with their state, meals per slot of
/// the booking's pattern ("Thêm món": a quick form or "Chọn từ công thức của
/// tôi"), "Sao chép từ ngày trước", a day note and "Lưu nháp". OneShot:
/// "Gửi toàn bộ kế hoạch" once every day is complete (then back to the
/// booking); DailyFeedback: "Gửi
/// ngày này" with yesterday's feedback on top. Sent days reach the member's
/// Thực đơn › "Từ chuyên gia".
class PlanEditorScreen extends ConsumerStatefulWidget {
  const PlanEditorScreen({super.key, required this.bookingId});

  final String bookingId;

  /// Completes with `true` when the whole plan was sent ("Gửi toàn bộ kế
  /// hoạch" closes the editor).
  static Route<bool> route(String bookingId) => MaterialPageRoute<bool>(
      builder: (_) => PlanEditorScreen(bookingId: bookingId));

  @override
  ConsumerState<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends ConsumerState<PlanEditorScreen> {
  BookingDto? _booking;
  List<PlanDayDto> _days = const [];
  final _drafts = <int, _Draft>{};
  final _note = TextEditingController();
  Object? _error;
  int _selected = 1;
  bool _busy = false;

  BookingApiService get _api => ref.read(bookingApiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepSelection = false}) async {
    try {
      final booking = await _api.getBooking(widget.bookingId);
      final days = await _api.plan(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _days = days;
        _error = null;
        _drafts
          ..clear()
          ..addAll({for (final d in days) d.dayIndex: _Draft.from(d)});
        if (!keepSelection) {
          _selected = days.where((d) => !d.isSent).firstOrNull?.dayIndex ?? 1;
        }
        _note.text = _drafts[_selected]?.note ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  PlanDayDto? _day(int index) =>
      _days.where((d) => d.dayIndex == index).firstOrNull;

  List<MealSlot> get _pattern => _booking?.mealPattern ?? MealPattern.standard;

  bool _complete(int index) {
    final draft = _drafts[index];
    return draft != null && _pattern.every(draft.meals.containsKey);
  }

  int get _incomplete =>
      _days.where((d) => !d.isSent && !_complete(d.dayIndex)).length;

  bool get _dirty => _drafts.values.any((d) => d.dirty);

  void _select(int index) {
    _drafts[_selected]?.note = _note.text;
    setState(() {
      _selected = index;
      _note.text = _drafts[index]?.note ?? '';
    });
  }

  void _setMeal(MealSlot slot, PlanMealDto? meal) {
    final draft = _drafts[_selected];
    if (draft == null) return;
    setState(() {
      if (meal == null) {
        draft.meals.remove(slot);
      } else {
        draft.meals[slot] = meal;
      }
      draft.dirty = true;
    });
  }

  void _copyPrevious() {
    final previous = _drafts[_selected - 1];
    final draft = _drafts[_selected];
    if (previous == null || draft == null) return;
    setState(() {
      draft.meals
        ..clear()
        ..addAll({
          for (final s in _pattern)
            if (previous.meals[s] case final m?) s: m,
        });
      draft.dirty = true;
    });
  }

  /// Saves every edited day (a draft for each).
  Future<void> _saveDirty() async {
    _drafts[_selected]?.note = _note.text;
    for (final MapEntry(key: index, value: draft) in _drafts.entries) {
      if (!draft.dirty) continue;
      await _api.savePlanDay(
        widget.bookingId,
        index,
        PlanDayRequestDto(
          meals: [
            for (final s in MealSlot.values)
              if (draft.meals[s] case final m?) m,
          ],
          chefNote: draft.note,
        ),
      );
      draft.dirty = false;
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.bookingChanged();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load(keepSelection: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveDraft() => _run(_saveDirty, 'Đã lưu nháp.');

  void _sendDay() => _run(() async {
        await _saveDirty();
        await _api.sendPlanDay(widget.bookingId, _selected);
      }, 'Đã gửi ngày $_selected cho thành viên.');

  Future<void> _sendAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gửi toàn bộ kế hoạch?'),
        content: Text(
            'Thành viên nhận cả ${_days.length} ngày và các món sẽ xuất hiện trong Thực đơn của họ. Sau khi gửi bạn không sửa được nữa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Xem lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Gửi')),
        ],
      ),
    );
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      await _saveDirty();
      await _api.sendWholePlan(widget.bookingId);
      if (!mounted) return;
      ref.bookingChanged();
      // Nothing left to edit: back to the booking, which confirms it. Every
      // draft was saved above, so no unsaved change is skipped.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  Future<void> _addMeal(MealSlot slot, PlanMealDto? current) async {
    final choice = current != null
        ? 'form'
        : await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: const Text('Nhập món mới'),
                    subtitle: const Text(
                        'Tên món, kcal, nguyên liệu, cách làm, ghi chú'),
                    onTap: () => Navigator.pop(sheetContext, 'form'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Chọn từ công thức của tôi'),
                    onTap: () => Navigator.pop(sheetContext, 'mine'),
                  ),
                ],
              ),
            ),
          );
    if (choice == null || !mounted) return;
    final PlanRecipeDto? recipe = choice == 'mine' ? await _pickMine() : null;
    if (!mounted) return;
    if (choice == 'mine' && recipe == null) return;
    final meal = await showModalBottomSheet<PlanMealDto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DishForm(
        slot: slot,
        initial: current ??
            (recipe == null ? null : PlanMealDto(slot: slot, recipe: recipe)),
      ),
    );
    if (meal != null) _setMeal(slot, meal);
  }

  /// "Chọn từ công thức của tôi": the chef's own recipes and the dishes
  /// already used in this plan.
  Future<PlanRecipeDto?> _pickMine() async {
    final used = <String, PlanRecipeDto>{
      for (final d in _drafts.values)
        for (final m in d.meals.values) m.recipe.name: m.recipe,
    };
    var own = <PlanRecipeDto>[];
    try {
      own = [
        for (final r in await ref.read(mealPlannerApiProvider).getMyRecipes())
          PlanRecipeDto(
            id: r.id,
            name: r.name,
            calories: r.nutrition.calories > 0 ? r.nutrition.calories : null,
            proteinG: r.nutrition.proteinG,
            carbsG: r.nutrition.carbsG,
            fatG: r.nutrition.fatG,
          ),
      ];
    } on ApiException {
      // Only the dishes already in the plan.
    }
    if (!mounted) return null;
    final all = [
      ...own,
      ...used.values.where((u) => !own.any((o) => o.name == u.name)),
    ];
    return showModalBottomSheet<PlanRecipeDto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: all.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Bạn chưa có công thức nào. Hãy nhập món mới.',
                    textAlign: TextAlign.center),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final r in all)
                    ListTile(
                      leading: const Icon(Icons.restaurant_menu_rounded),
                      title: Text(r.name),
                      subtitle: r.calories == null
                          ? null
                          : Text('${formatInt(r.calories!)} kcal'),
                      onTap: () => Navigator.pop(sheetContext, r),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bỏ thay đổi chưa lưu?'),
        content: const Text('Các món bạn vừa sửa chưa được lưu nháp.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ở lại')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Bỏ thay đổi')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    return AskAiBubbleFree(
      child: PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmLeave();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Soạn kế hoạch'),
            bottom: booking == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                          '${booking.member.fullName} · ${planSummary(booking.planDays, booking.bookingType)}',
                          style: context.textStyles.bodySmall),
                    ),
                  ),
          ),
          body: booking == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : SingleChildScrollView(
                          child:
                              ErrorStateView(error: _error!, onRetry: _load)),
                )
              : _editor(booking),
          bottomNavigationBar: booking == null ? null : _bottomBar(booking),
        ),
      ),
    );
  }

  Widget _editor(BookingDto b) {
    final day = _day(_selected);
    final draft = _drafts[_selected];
    if (day == null || draft == null) {
      return const Center(child: Text('Chưa có ngày nào để soạn.'));
    }
    final daily = b.bookingType == BookingType.dailyFeedback;
    final previous = _day(_selected - 1);
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DayChips(
          days: _days,
          selected: _selected,
          stateOf: (d) => d.isSent
              ? PlanDayStatus.sent
              : (_drafts[d.dayIndex]?.meals.isNotEmpty ?? false) ||
                      d.status == PlanDayStatus.draft
                  ? PlanDayStatus.draft
                  : null,
          onSelected: _select,
        ),
        const SizedBox(height: 4),
        Text('● Chưa soạn   ● Nháp   ● Đã gửi', style: muted),
        if (daily && previous != null) ...[
          const SizedBox(height: 12),
          VLCard(
            color: context.vl.aiContainer,
            borderColor: Colors.transparent,
            child: Text(
              previous.feedback == null
                  ? 'Thành viên chưa phản hồi ngày ${previous.dayIndex}.'
                  : 'Phản hồi ngày ${previous.dayIndex}: ${previous.feedback!.summary}',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.onAiContainer),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(day.title, style: context.textStyles.titleMedium),
        if (daily && !day.isSent)
          Text(
              'Hạn gửi: ${formatVnDeadline(dailySendDeadline(b.startDate, day.dayIndex))}',
              style: muted),
        const SizedBox(height: 8),
        if (day.isSent) ...[
          PlanDayCard(day: day),
          const SizedBox(height: 8),
          Text('Ngày này đã gửi cho thành viên.', style: muted),
        ] else ...[
          for (final slot in _pattern)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SlotEditor(
                slot: slot,
                meal: draft.meals[slot],
                onAdd: () => _addMeal(slot, null),
                onEdit: () => _addMeal(slot, draft.meals[slot]),
                onRemove: () => _setMeal(slot, null),
              ),
            ),
          if (_selected > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _copyPrevious,
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Sao chép từ ngày trước'),
              ),
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            onChanged: (_) => draft.dirty = true,
            decoration: const InputDecoration(
              labelText: 'Ghi chú cho ngày này',
              hintText: 'Mẹo chuẩn bị, lưu ý đi chợ…',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomBar(BookingDto b) {
    final day = _day(_selected);
    final daily = b.bookingType == BookingType.dailyFeedback;
    final allSent = _days.every((d) => d.isSent);
    final canSendDay = day != null &&
        !day.isSent &&
        _complete(_selected) &&
        (_selected == 1 || (_day(_selected - 1)?.isSent ?? false));
    final missing = _incomplete;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!daily && !allSent && missing > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Còn $missing ngày chưa đủ món',
                    textAlign: TextAlign.center,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.onCautionContainer)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || !_dirty ? null : _saveDraft,
                    child: const Text('Lưu nháp'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: daily
                      ? FilledButton(
                          onPressed: _busy || !canSendDay ? null : _sendDay,
                          child: const Text('Gửi ngày này'),
                        )
                      : FilledButton(
                          onPressed:
                              _busy || allSent || missing > 0 ? null : _sendAll,
                          child: const Text('Gửi toàn bộ kế hoạch'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChips extends StatelessWidget {
  const _DayChips({
    required this.days,
    required this.selected,
    required this.stateOf,
    required this.onSelected,
  });

  final List<PlanDayDto> days;
  final int selected;
  final PlanDayStatus? Function(PlanDayDto day) stateOf;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final d in days) ...[
            ChoiceChip(
              avatar: Icon(Icons.circle,
                  size: 10,
                  color: switch (stateOf(d)) {
                    PlanDayStatus.sent => vl.success,
                    PlanDayStatus.draft => vl.caution,
                    null => vl.muted,
                  }),
              label: Text('Ngày ${d.dayIndex} · ${formatDayMonth(d.date)}'),
              tooltip: switch (stateOf(d)) {
                PlanDayStatus.sent => 'Đã gửi',
                PlanDayStatus.draft => 'Nháp',
                null => 'Chưa soạn',
              },
              selected: d.dayIndex == selected,
              onSelected: (_) => onSelected(d.dayIndex),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.slot,
    required this.meal,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final MealSlot slot;
  final PlanMealDto? meal;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final m = meal;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return VLCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.label,
                    style: context.textStyles.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (m == null)
                  Text('Chưa có món', style: muted)
                else ...[
                  Text(m.recipe.name, style: context.textStyles.bodyMedium),
                  Text(
                    [
                      if (m.recipe.calories != null)
                        '${formatInt(m.recipe.calories!)} kcal',
                      if (m.recipe.ingredients.isNotEmpty)
                        m.recipe.ingredients.join(', '),
                    ].join(' · '),
                    style: muted,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (m == null)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Thêm món'),
            )
          else ...[
            IconButton(
                tooltip: 'Sửa món',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined)),
            IconButton(
                tooltip: 'Bỏ món',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded)),
          ],
        ],
      ),
    );
  }
}

/// Quick dish form: Tên món, kcal, Đạm / Tinh bột / Béo (optional),
/// Nguyên liệu, Cách làm, Ghi chú.
class _DishForm extends StatefulWidget {
  const _DishForm({required this.slot, this.initial});

  final MealSlot slot;
  final PlanMealDto? initial;

  @override
  State<_DishForm> createState() => _DishFormState();
}

class _DishFormState extends State<_DishForm> {
  late final PlanRecipeDto? _r = widget.initial?.recipe;
  late final _name = TextEditingController(text: _r?.name);
  late final _kcal = TextEditingController(text: _r?.calories?.toString());
  late final _protein = TextEditingController(text: _fmt(_r?.proteinG));
  late final _carbs = TextEditingController(text: _fmt(_r?.carbsG));
  late final _fat = TextEditingController(text: _fmt(_r?.fatG));
  late final _ingredients =
      TextEditingController(text: _r?.ingredients.join(', '));
  late final _instructions = TextEditingController(text: _r?.instructions);
  late final _mealNote = TextEditingController(text: widget.initial?.note);
  String? _nameError;

  static String? _fmt(double? v) =>
      v == null ? null : (v == v.roundToDouble() ? '${v.round()}' : '$v');

  @override
  void dispose() {
    for (final c in [
      _name,
      _kcal,
      _protein,
      _carbs,
      _fat,
      _ingredients,
      _instructions,
      _mealNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _grams(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _submit() {
    final error = BookingRules.dishName(_name.text);
    if (error != null) {
      setState(() => _nameError = error);
      return;
    }
    final kcal = int.tryParse(_kcal.text.trim());
    Navigator.of(context).pop(PlanMealDto(
      slot: widget.slot,
      recipe: PlanRecipeDto(
        id: _r?.id ?? '',
        name: _name.text.trim(),
        calories: kcal == null || kcal <= 0 ? null : kcal,
        proteinG: _grams(_protein),
        carbsG: _grams(_carbs),
        fatG: _grams(_fat),
        ingredients: [
          for (final i in _ingredients.text.split(RegExp(r'[,\n]')))
            if (i.trim().isNotEmpty) i.trim(),
        ],
        instructions: _instructions.text.trim(),
      ),
      note: _mealNote.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Widget grams(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder()),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Món cho ${widget.slot.label.toLowerCase()}',
                style: context.textStyles.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.initial == null,
              decoration: InputDecoration(
                labelText: 'Tên món',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _kcal,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Năng lượng (kcal)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                grams(_protein, 'Đạm (g)'),
                const SizedBox(width: 8),
                grams(_carbs, 'Tinh bột (g)'),
                const SizedBox(width: 8),
                grams(_fat, 'Béo (g)'),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ingredients,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Nguyên liệu',
                hintText: 'Đậu hũ 200 g, cà chua 2 quả…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _instructions,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Cách làm',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mealNote,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: const Text('Lưu món'),
            ),
          ],
        ),
      ),
    );
  }
}
