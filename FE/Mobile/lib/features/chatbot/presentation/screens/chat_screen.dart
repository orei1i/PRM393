// lib/features/chatbot/presentation/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/account_button.dart';
import '../../../../core/widgets/demo_data_banner.dart';
import '../../domain/entities/chat_message.dart';
import '../controllers/chat_controller.dart';
import '../widgets/chat_composer.dart';
import '../widgets/guest_trial_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/trial_exhausted_sheet.dart';

/// Asks about the member's own menu: a guest has none.
const _personalPrompts = ['Giải thích lượng sắt mỗi ngày của tôi'];

const _quickPrompts = [
  ..._personalPrompts,
  'Gợi ý món thay thế đậu hũ',
  'Đậu hũ có phải đạm hoàn chỉnh?',
  'Người ăn chay bổ sung B12 thế nào?',
];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  bool _pinnedToBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      final distance =
          _scroll.position.maxScrollExtent - _scroll.position.pixels;
      final pinned = distance < 80;
      if (pinned != _pinnedToBottom) setState(() => _pinnedToBottom = pinned);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animated && !MediaQuery.disableAnimationsOf(context)) {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));

    // One-shot: show the sign-in sheet when the guest runs out of questions.
    ref.listen(chatControllerProvider.select((s) => s.showTrialExhausted),
        (previous, show) {
      if (!show) return;
      final current = ref.read(chatControllerProvider);
      TrialExhaustedSheet.show(context,
              pendingPrompt: current.pendingPrompt,
              remaining: current.trialRemaining ?? 0,
              limit: current.trialLimit)
          .whenComplete(controller.consumeTrialExhaustedEvent);
    });

    // Follow the stream while the user is at the bottom ("pinned").
    ref.listen(chatControllerProvider.select((s) => s.messages),
        (previous, next) {
      final added = (previous?.length ?? 0) < next.length;
      if (added || _pinnedToBottom) _scrollToBottom(animated: added);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        // Opened from the "Hỏi AI" bubble (a pushed route) → back arrow.
        leading: Navigator.of(context).canPop()
            ? const BackButton()
            : Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: context.colors.tertiary,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.auto_awesome,
                      color: context.colors.onTertiary, size: 20),
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('VeganLife AI'),
            Text(
              'Mọi câu trả lời đều có nguồn trích dẫn',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
          ],
        ),
        actions: [
          if (!isGuest)
            IconButton(
              tooltip: 'Cuộc trò chuyện mới',
              onPressed:
                  chat.messages.isEmpty ? null : controller.newConversation,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          const AccountButton(),
        ],
      ),
      body: Column(
        children: [
          if (DemoDataBanner.visibleFor(BackendModule.chatbot))
            const DemoDataBanner(module: BackendModule.chatbot),
          if (chat.trialRemaining case final remaining?)
            GuestTrialBanner(
              remaining: remaining,
              limit: chat.trialLimit,
              onSignIn: () => TrialExhaustedSheet.show(context,
                  pendingPrompt: chat.pendingPrompt,
                  remaining: remaining,
                  limit: chat.trialLimit),
            ),
          Expanded(
            child: Stack(
              children: [
                if (chat.messages.isEmpty)
                  _WelcomeView(onPrompt: controller.send, isGuest: isGuest)
                else
                  ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: chat.messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, i) {
                      final m = chat.messages[i];
                      return MessageBubble(
                        key: ValueKey(m.id),
                        message: m,
                        onRetry: () => controller.retry(m.id),
                        onFeedback: (helpful) =>
                            ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(helpful
                                ? 'Cảm ơn bạn đã góp ý!'
                                : 'Cảm ơn! Góp ý sẽ giúp AI trả lời tốt hơn.'),
                          ),
                        ),
                      );
                    },
                  ),
                if (!_pinnedToBottom && chat.messages.isNotEmpty)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FilledButton.tonalIcon(
                        onPressed: _scrollToBottom,
                        icon:
                            const Icon(Icons.arrow_downward_rounded, size: 18),
                        label: const Text('Tin mới nhất'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ChatComposer(
            isStreaming: chat.isStreaming,
            onSend: controller.send,
            onStop: controller.stop,
            quickPrompts: _quickPrompts,
            showQuickPrompts:
                chat.messages.isNotEmpty && !_hasActiveAnswer(chat.messages),
          ),
        ],
      ),
    );
  }

  bool _hasActiveAnswer(List<ChatMessage> messages) =>
      messages.any((m) => m.isInProgress);
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.onPrompt, required this.isGuest});

  final ValueChanged<String> onPrompt;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: vl.aiContainer, borderRadius: BorderRadius.circular(16)),
          child: Icon(Icons.eco_outlined, color: vl.ai, size: 28),
        ),
        const SizedBox(height: 16),
        Text('Hỏi gì về ăn chay cũng được',
            style: context.textStyles.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Câu trả lời dựa trên tài liệu của WHO, NIH và đầu bếp đã xác minh, kèm thực đơn của bạn nếu bạn đã đăng nhập.',
          style: context.textStyles.bodyLarge?.copyWith(color: vl.muted),
        ),
        const SizedBox(height: 20),
        for (final prompt in _quickPrompts)
          if (!isGuest || !_personalPrompts.contains(prompt))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () => onPrompt(prompt),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: vl.ai),
                    const SizedBox(width: 10),
                    Expanded(child: Text(prompt)),
                  ],
                ),
              ),
            ),
        if (!BackendModules.isHybrid) ...[
          const SizedBox(height: 8),
          Text(
            'Chế độ mock: thêm "#offline" vào câu hỏi để thử trạng thái mất mạng giữa chừng.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
        ],
      ],
    );
  }
}
