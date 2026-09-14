import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/entities/nutrition_entities.dart';
import '../view_models/ai_nutrition_view_model.dart';

class NutritionChatPanel extends StatefulWidget {
  const NutritionChatPanel({
    required this.vm,
    this.banner,
    this.onSubmitted,
    super.key,
  });
  final AiNutritionViewModel vm;
  final Widget? banner;
  final VoidCallback? onSubmitted;
  @override
  State<NutritionChatPanel> createState() => _NutritionChatPanelState();
}

class _NutritionChatPanelState extends State<NutritionChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _lastMessages = const [];
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _input.text = widget.vm.draft;
    _lastMessages = widget.vm.messages;
    widget.vm.addListener(_sync);
  }

  @override
  void didUpdateWidget(NutritionChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm) {
      oldWidget.vm.removeListener(_sync);
      _input.text = widget.vm.draft;
      widget.vm.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final vm = widget.vm;
    if (_input.text != vm.draft) {
      _input.value = TextEditingValue(
        text: vm.draft,
        selection: TextSelection.collapsed(offset: vm.draft.length),
      );
    }
    if (identical(_lastMessages, vm.messages)) return;
    _lastMessages = vm.messages;
    final nearBottom = !_scroll.hasClients || _scroll.position.pixels < 120;
    if ((!nearBottom && vm.messages.isNotEmpty) || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _send([String? prompt]) async {
    final vm = widget.vm;
    final completed = await vm.submit(prompt);
    if (completed &&
        mounted &&
        identical(vm, widget.vm) &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      widget.onSubmitted?.call();
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(_sync);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final colors = Theme.of(context).colorScheme;
    return ChangeNotifierProvider<AiNutritionViewModel>.value(
      value: vm,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: _ChatLayout(
            header: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.primaryContainer,
                      child: const Icon(Icons.auto_awesome),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your plant-powered guide',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Text(
                            'Nutrition assistant · simulated AI',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: vm.clearConversation,
                      icon: const Icon(Icons.restart_alt),
                      tooltip: 'Clear conversation',
                    ),
                  ],
                ),
              ),
              if (widget.banner != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: widget.banner!,
                ),
            ],
            transcript:
                Selector<
                  AiNutritionViewModel,
                  (List<ChatMessage>, String?, bool)
                >(
                  selector: (_, model) =>
                      (model.messages, model.error, model.busy),
                  shouldRebuild: (previous, next) => previous != next,
                  builder: (context, state, _) {
                    final (messages, error, busy) = state;
                    if (messages.isEmpty) {
                      return ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        children: [
                          _ChatWelcome(
                            quickActions: vm.quickActions,
                            onPrompt: busy ? null : _send,
                          ),
                          ErrorNotice(error),
                        ],
                      );
                    }
                    final errorOffset = error == null ? 0 : 1;
                    return ListView.builder(
                      key: const ValueKey('chat-transcript'),
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      itemCount: messages.length + errorOffset,
                      itemBuilder: (context, index) {
                        if (errorOffset == 1 && index == 0) {
                          return ErrorNotice(error);
                        }
                        final message =
                            messages[messages.length - 1 - index + errorOffset];
                        return _MessageBubble(
                          key: ValueKey('chat-message-${message.id}'),
                          message: message,
                        );
                      },
                    );
                  },
                ),
            composer: Selector<AiNutritionViewModel, (bool, bool)>(
              selector: (_, model) => (model.busy, model.canSend),
              builder: (context, state, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            onChanged: vm.setDraft,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 2000,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: 'Ask something nourishing…',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: state.$1
                              ? vm.cancel
                              : state.$2
                              ? () => _send()
                              : null,
                          tooltip: state.$1 ? 'Stop response' : 'Send question',
                          icon: Icon(
                            state.$1 ? Icons.stop : Icons.arrow_upward,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      AppConstants.nutritionDisclaimer,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatLayout extends StatelessWidget {
  const _ChatLayout({
    required this.header,
    required this.transcript,
    required this.composer,
  });
  final List<Widget> header;
  final Widget transcript, composer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxHeight < MediaQuery.textScalerOf(context).scale(420);
      final content = Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          ...header,
          if (compact)
            SizedBox(
              height: (constraints.maxHeight * .6).clamp(180.0, 360.0),
              child: transcript,
            )
          else
            Expanded(child: transcript),
          composer,
        ],
      );
      // Keep every control reachable with the keyboard, large text or landscape.
      return compact ? SingleChildScrollView(child: content) : content;
    },
  );
}

class _ChatWelcome extends StatelessWidget {
  const _ChatWelcome({required this.quickActions, required this.onPrompt});
  final List<NutritionTip> quickActions;
  final void Function(String)? onPrompt;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 24),
      Icon(
        Icons.spa_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 18),
      Text(
        'Good food.\nA little guidance.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        'Ask about plant-based nutrition, everyday swaps,\nor what to make for dinner.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 28),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final tip in quickActions)
            ActionChip(
              avatar: const Icon(Icons.north_east, size: 16),
              label: Text(tip.title),
              onPressed: onPrompt == null ? null : () => onPrompt!(tip.prompt),
            ),
        ],
      ),
    ],
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, super.key});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isUser ? colors.primaryContainer : colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'YOU' : 'VEGANLIFE AI · DEMO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                message.text.isEmpty
                    ? 'Preparing a little inspiration…'
                    : message.text,
              ),
              if (message.streaming)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
