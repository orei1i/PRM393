// lib/features/chatbot/presentation/widgets/trial_exhausted_sheet.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/google_sign_in_button.dart';

/// Shown on the 4th guest question (never on a timer). The held question is
/// sent automatically after sign-in.
class TrialExhaustedSheet extends StatelessWidget {
  const TrialExhaustedSheet({super.key, this.pendingPrompt});

  final String? pendingPrompt;

  static Future<void> show(BuildContext context, {String? pendingPrompt}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TrialExhaustedSheet(pendingPrompt: pendingPrompt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: vl.aiContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.auto_awesome, color: vl.ai),
          ),
          const SizedBox(height: 16),
          Text('Tiếp tục trò chuyện', style: context.textStyles.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Bạn đã dùng hết 3 lượt hỏi miễn phí. Đăng nhập miễn phí để hỏi tiếp, '
            'với câu trả lời dựa trên cơ thể và tủ lạnh của chính bạn.',
            style: context.textStyles.bodyLarge?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 18),
          const _Benefit(icon: Icons.calendar_month_rounded, text: 'Thực đơn 7 ngày theo chiều cao, cân nặng, mục tiêu và dị ứng'),
          const _Benefit(icon: Icons.document_scanner_outlined, text: 'Quét tủ lạnh, AI gợi ý món từ nguyên liệu bạn có'),
          const _Benefit(icon: Icons.forum_outlined, text: 'Hỏi không giới hạn, mọi câu trả lời đều có nguồn'),
          const SizedBox(height: 16),
          GoogleSignInButton(onSignedIn: () => Navigator.of(context).maybePop()),
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
