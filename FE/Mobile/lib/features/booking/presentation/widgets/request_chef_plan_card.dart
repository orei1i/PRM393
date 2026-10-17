// lib/features/booking/presentation/widgets/request_chef_plan_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../chef/presentation/screens/chef_directory_screen.dart';

/// Thực đơn › "Cần thực đơn riêng? Nhờ chuyên gia thiết kế" (plan D13b):
/// opens the chef directory in pick mode → chef profile → "Đặt chuyên gia
/// lên thực đơn". Guests are asked to sign in first. Sits right after the
/// pantry card in `meal_planner_screen.dart`.
class RequestChefPlanCard extends ConsumerWidget {
  const RequestChefPlanCard({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để nhờ chuyên gia thiết kế thực đơn riêng.')) {
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ChefDirectoryScreen(pickMode: true)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    return VLCard(
      color: vl.successContainer,
      borderColor: Colors.transparent,
      onTap: () => _open(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.support_agent_rounded, color: vl.onSuccessContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cần thực đơn riêng? Nhờ chuyên gia thiết kế',
                    style: context.textStyles.titleSmall?.copyWith(
                        color: vl.onSuccessContainer,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  'Đầu bếp, chuyên gia dinh dưỡng lên kế hoạch 3–30 ngày theo mục tiêu, '
                  'dị ứng và khẩu vị của bạn. Tiền được VeganLife giữ đến khi kế hoạch xong.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: vl.onSuccessContainer),
                ),
                const SizedBox(height: 8),
                Text('Nhờ chuyên gia lên thực đơn ›',
                    style: context.textStyles.labelLarge?.copyWith(
                        color: vl.onSuccessContainer,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
