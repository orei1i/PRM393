// lib/features/meal_planner/presentation/widgets/adjust_plan_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/plan_adjustment.dart';
import '../controllers/meal_plan_controller.dart';

/// One message in the conversation.
class _Turn {
  _Turn.user(this.text)
      : fromAi = false,
        proposal = null,
        selected = {};

  _Turn.ai(this.text, {this.proposal})
      : fromAi = true,
        selected = {
          for (final c in proposal?.changes ?? const <PlanChange>[]) c.id
        };

  final String text;
  final bool fromAi;
  final PlanAdjustment? proposal;

  /// Ticked change ids (all by default).
  final Set<String> selected;

  /// `null` until the member applies or skips the proposal.
  String? outcome;
}

/// "Chỉnh thực đơn với AI": the member asks in plain words (or taps a
/// suggestion), the AI answers with a proposal — a list of changes with
/// checkboxes — and nothing changes until "Áp dụng thay đổi". "Bỏ qua"
/// keeps the plan as it is. Every proposed dish is vegan and avoids the
/// member's allergies.
class AdjustPlanSheet extends ConsumerStatefulWidget {
  const AdjustPlanSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.92,
          child: AdjustPlanSheet(),
        ),
      );

  @override
  ConsumerState<AdjustPlanSheet> createState() => _AdjustPlanSheetState();
}

class _AdjustPlanSheetState extends ConsumerState<AdjustPlanSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  AdjustScope _scope = AdjustScope.day;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? text]) async {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _turns.add(_Turn.user(message));
      _busy = true;
    });
    _toBottom();
    try {
      final proposal = await ref
          .read(mealPlanControllerProvider.notifier)
          .proposeAdjustment(message, _scope);
      if (!mounted) return;
      setState(() => _turns.add(_Turn.ai(proposal.reply,
          proposal: proposal.changes.isEmpty ? null : proposal)));
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _turns.add(_Turn.ai('Chưa xử lý được yêu cầu. ${describeError(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _toBottom();
    }
  }

  Future<void> _apply(_Turn turn) async {
    final proposal = turn.proposal!;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final count = await ref
          .read(mealPlanControllerProvider.notifier)
          .applyAdjustment(proposal, turn.selected);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Đã áp dụng $count thay đổi vào thực đơn.')));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _turns.add(_Turn.ai('Chưa áp dụng được. ${describeError(e)}'));
      });
      _toBottom();
    }
  }

  void _skip(_Turn turn) =>
      setState(() => turn.outcome = 'Đã bỏ qua đề xuất này.');

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: vl.ai),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Chỉnh thực đơn với AI',
                      style: context.textStyles.titleLarge),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SegmentedButton<AdjustScope>(
              showSelectedIcon: false,
              segments: [
                for (final s in AdjustScope.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {_scope},
              onSelectionChanged:
                  _busy ? null : (v) => setState(() => _scope = v.first),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              children: [
                const _Bubble(
                  fromAi: true,
                  text: 'Bạn muốn chỉnh thực đơn thế nào? Mình chỉ đề xuất món '
                      'thuần chay và tránh các thành phần bạn dị ứng; bạn '
                      'xem lại rồi mới áp dụng.',
                ),
                for (final turn in _turns) ...[
                  _Bubble(fromAi: turn.fromAi, text: turn.text),
                  if (turn.proposal != null)
                    _ProposalCard(
                      turn: turn,
                      busy: _busy,
                      onToggle: (id, on) => setState(() {
                        if (on) {
                          turn.selected.add(id);
                        } else {
                          turn.selected.remove(id);
                        }
                      }),
                      onApply: () => _apply(turn),
                      onSkip: () => _skip(turn),
                    ),
                ],
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        Text('AI đang xem thực đơn…',
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: vl.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final example in adjustPlanExamples)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(example),
                      onPressed: _busy ? null : () => _send(example),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 300,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Bạn muốn chỉnh gì?',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'Gửi',
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromAi, required this.text});

  final bool fromAi;
  final String text;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    return Align(
      alignment: fromAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: fromAi ? vl.aiContainer : cs.primary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: context.textStyles.bodyMedium
              ?.copyWith(color: fromAi ? vl.onAiContainer : cs.onPrimary),
        ),
      ),
    );
  }
}

/// The changes of one proposal, each with a checkbox, then "Áp dụng thay
/// đổi" / "Bỏ qua".
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.turn,
    required this.busy,
    required this.onToggle,
    required this.onApply,
    required this.onSkip,
  });

  final _Turn turn;
  final bool busy;
  final void Function(String id, bool on) onToggle;
  final VoidCallback onApply;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final changes = turn.proposal!.changes;
    final done = turn.outcome != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VLCard(
        borderColor: vl.aiBorder,
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in changes)
              CheckboxListTile(
                value: turn.selected.contains(c.id),
                onChanged:
                    done || busy ? null : (on) => onToggle(c.id, on ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.only(left: 4),
                title: Text(c.label, style: context.textStyles.bodyMedium),
              ),
            const SizedBox(height: 6),
            if (done)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(turn.outcome!,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.muted)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    FilledButton(
                      onPressed: busy || turn.selected.isEmpty ? null : onApply,
                      child: const Text('Áp dụng thay đổi'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : onSkip,
                      child: const Text('Bỏ qua'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
