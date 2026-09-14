import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../ai_nutrition/presentation/widgets/nutrition_chat_panel.dart';
import '../../../auth/presentation/widgets/auth_sheet.dart';
import '../view_models/trial_chat_view_model.dart';

class TrialChatView extends StatefulWidget {
  const TrialChatView({super.key});
  @override
  State<TrialChatView> createState() => _TrialChatViewState();
}

class _TrialChatViewState extends State<TrialChatView> {
  bool _authSheetOpen = false;

  Future<void> _join() async {
    if (_authSheetOpen ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    _authSheetOpen = true;
    try {
      await showAuthSheet(context);
    } finally {
      _authSheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<TrialChatViewModel>();
    return NutritionChatPanel(
      vm: vm,
      onSubmitted: () {
        if (vm.shouldPromptForAuth) _join();
      },
      banner: Selector<TrialChatViewModel, (int, int)>(
        selector: (_, model) => (model.limit.remaining, model.limit.maximum),
        builder: (context, quota, _) => Row(
          children: [
            const Icon(Icons.bubble_chart_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${quota.$1} of ${quota.$2} trial turns remaining',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: _join, child: const Text('Join')),
          ],
        ),
      ),
    );
  }
}
