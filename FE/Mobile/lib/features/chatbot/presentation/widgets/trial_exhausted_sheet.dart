// lib/features/chatbot/presentation/widgets/trial_exhausted_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../auth/presentation/auth_navigation.dart';
import '../../../auth/presentation/widgets/auth_widgets.dart';

/// Shown on the guest question after the free ones run out (never on a
/// timer); the held question is sent automatically after sign-in. Also opened
/// from the trial banner's "Đăng nhập" while questions remain — the copy then
/// invites instead of saying the trial is over.
///
/// "Đăng nhập" / "Tạo tài khoản" open the auth screens over the sheet; the
/// sheet closes itself once the guest is signed in.
class TrialExhaustedSheet extends StatelessWidget {
  const TrialExhaustedSheet({
    super.key,
    this.pendingPrompt,
    this.remaining = 0,
    this.limit = Env.guestTrialLimit,
  });

  final String? pendingPrompt;

  /// Free questions the guest still has; `0` = exhausted.
  final int remaining;
  final int limit;

  static Future<void> show(
    BuildContext context, {
    String? pendingPrompt,
    int remaining = 0,
    int limit = Env.guestTrialLimit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TrialExhaustedSheet(
          pendingPrompt: pendingPrompt, remaining: remaining, limit: limit),
    );
  }

  Future<void> _open(BuildContext context, {required bool register}) async {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final ok = register
        ? await AuthNavigation.register(navigator)
        : await AuthNavigation.login(navigator);
    if (ok && route != null) completeRoute<Object?>(navigator, route, null);
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final exhausted = remaining <= 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: vl.aiContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.auto_awesome, color: vl.ai),
          ),
          const SizedBox(height: 16),
          Text(exhausted ? 'Tiếp tục trò chuyện' : 'Hỏi AI không giới hạn',
              style: context.textStyles.headlineSmall),
          const SizedBox(height: 6),
          Text(
            exhausted
                ? 'Bạn đã dùng hết $limit lượt hỏi miễn phí. Đăng nhập miễn phí để hỏi tiếp, '
                    'với câu trả lời dựa trên cơ thể và tủ lạnh của chính bạn.'
                : 'Bạn vẫn còn $remaining/$limit lượt hỏi miễn phí. Đăng nhập miễn phí để hỏi '
                    'không giới hạn, với câu trả lời dựa trên cơ thể và tủ lạnh của chính bạn.',
            style: context.textStyles.bodyLarge?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 18),
          const _Benefit(
              icon: Icons.calendar_month_rounded,
              text:
                  'Thực đơn 7 ngày theo chiều cao, cân nặng, mục tiêu và dị ứng'),
          const _Benefit(
              icon: Icons.document_scanner_outlined,
              text: 'Quét tủ lạnh, AI gợi ý món từ nguyên liệu bạn có'),
          const _Benefit(
              icon: Icons.forum_outlined,
              text: 'Hỏi không giới hạn, mọi câu trả lời đều có nguồn'),
          const SizedBox(height: 16),
          AuthChoiceButtons(
            onLogin: () => _open(context, register: false),
            onRegister: () => _open(context, register: true),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Để sau'),
            ),
          ),
          if (pendingPrompt != null)
            Text(
              'Câu hỏi "$pendingPrompt" sẽ được gửi ngay sau khi bạn đăng nhập.',
              textAlign: TextAlign.center,
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
            ),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.colors.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: context.colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: context.textStyles.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
