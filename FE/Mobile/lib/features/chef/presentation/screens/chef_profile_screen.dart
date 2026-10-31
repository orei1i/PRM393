// lib/features/chef/presentation/screens/chef_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/mock_persona.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../booking/presentation/screens/book_chef_plan_screen.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/chef_api_service.dart';
import '../../domain/entities/chef.dart';
import '../widgets/chef_card.dart';

/// A chef's public page: bio, certificates and "Thiết kế thực đơn theo yêu
/// cầu" with the listed prices and "Đặt chuyên gia lên thực đơn" (members
/// only; guests are asked to sign in).
class ChefProfileScreen extends ConsumerStatefulWidget {
  const ChefProfileScreen({super.key, required this.chefId, this.preview});

  final String chefId;

  /// Directory item shown instantly while the detail loads.
  final Chef? preview;

  static Route<void> route(String chefId, {Chef? preview}) =>
      MaterialPageRoute<void>(
          builder: (_) => ChefProfileScreen(chefId: chefId, preview: preview));

  @override
  ConsumerState<ChefProfileScreen> createState() => _ChefProfileScreenState();
}

class _ChefProfileScreenState extends ConsumerState<ChefProfileScreen> {
  late Future<Chef> _future = _load();

  Future<Chef> _load() async =>
      (await ref.read(chefApiProvider).getChef(widget.chefId)).toEntity();

  // Block body: an arrow would return the Future and trip setState's assert.
  void _reload() => setState(() {
        _future = _load();
      });

  bool _isOwn(Chef chef) {
    final me = ref.read(sessionControllerProvider);
    return !me.isGuest &&
        chef.userId != null &&
        chef.userId == mockPersonaId(me);
  }

  Future<void> _book(Chef chef) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để đặt chuyên gia lên thực đơn cho bạn.')) {
      return;
    }
    if (!mounted) return;
    if (_isOwn(chef)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đây là hồ sơ của bạn, không tự đặt được.')));
      return;
    }
    await Navigator.of(context).push(BookChefPlanScreen.route(chef));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Chef>(
      future: _future,
      builder: (context, snapshot) {
        final chef = snapshot.data ?? widget.preview;
        final loadingDetail = snapshot.connectionState != ConnectionState.done;
        final own = chef != null && _isOwn(chef);

        return Scaffold(
          body: chef == null
              ? Center(
                  child: snapshot.hasError
                      ? ErrorStateView(error: snapshot.error!, onRetry: _reload)
                      : const CircularProgressIndicator(),
                )
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      expandedHeight: 150,
                      flexibleSpace: FlexibleSpaceBar(
                        background: FoodCover(seed: chef.name, height: 190),
                      ),
                    ),
                    SliverToBoxAdapter(child: _Header(chef: chef)),
                    if (loadingDetail)
                      const SliverToBoxAdapter(
                        child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator())),
                      )
                    else if (snapshot.hasError)
                      SliverToBoxAdapter(
                        child: ErrorStateView(
                            error: snapshot.error!, onRetry: _reload),
                      )
                    else
                      SliverToBoxAdapter(
                        child: _Details(
                            chef: chef, isOwn: own, onBook: () => _book(chef)),
                      ),
                  ],
                ),
          bottomNavigationBar: chef == null ||
                  loadingDetail ||
                  snapshot.hasError ||
                  own ||
                  !chef.acceptingBookings
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Từ',
                                style: context.textStyles.bodySmall
                                    ?.copyWith(color: context.vl.muted)),
                            Text(
                              '${formatVnd(chef.startingPriceVnd)}/ngày',
                              style: context.textStyles.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _book(chef),
                            icon: const Icon(Icons.edit_calendar_outlined),
                            label: const Text('Đặt chuyên gia lên thực đơn'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.chef});

  final Chef chef;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: chef.name, size: 64, verified: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chef.name,
                        style: context.textStyles.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(chef.headline,
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.vl.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RatingLine(chef: chef),
          const SizedBox(height: 10),
          VLTag(
            label: 'Đã xác minh bởi VeganLife',
            icon: Icons.verified_rounded,
            background: context.vl.successContainer,
            foreground: context.vl.onSuccessContainer,
          ),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details(
      {required this.chef, required this.isOwn, required this.onBook});

  final Chef chef;

  /// The signed-in chef looking at their own public page.
  final bool isOwn;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stat(value: formatInt(chef.consultCount), label: 'lượt tư vấn'),
              _Stat(value: '${chef.yearsExperience} năm', label: 'kinh nghiệm'),
              _Stat(
                  value: formatDecimal(chef.rating),
                  label: '${formatInt(chef.reviewCount)} đánh giá'),
            ],
          ),
          const SizedBox(height: 16),
          _BookingOffer(chef: chef, isOwn: isOwn, onBook: onBook),
          const SizedBox(height: 20),
          Text('Giới thiệu', style: context.textStyles.titleMedium),
          const SizedBox(height: 6),
          Text(chef.bio,
              style: context.textStyles.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // Wraps instead of overflowing at large text sizes.
              for (final s in chef.specialties)
                StatusPill(
                  label: s,
                  background: context.colors.surfaceContainer,
                  foreground: context.colors.onSurfaceVariant,
                ),
            ],
          ),
          if (chef.certificates.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Chứng chỉ', style: context.textStyles.titleMedium),
            const SizedBox(height: 4),
            for (final c in chef.certificates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.workspace_premium_outlined,
                    color: context.colors.primary),
                title: Text(c),
              ),
          ],
        ],
      ),
    );
  }
}

/// "Thiết kế thực đơn theo yêu cầu": listed prices, plan length and the
/// booking button (or why there is none).
class _BookingOffer extends StatelessWidget {
  const _BookingOffer(
      {required this.chef, required this.isOwn, required this.onBook});

  final Chef chef;
  final bool isOwn;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu_rounded,
                  color: context.colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Thiết kế thực đơn theo yêu cầu',
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Từ ${formatVnd(chef.pricePerDay)}/ngày · Có phản hồi mỗi ngày: '
            '${formatVnd(chef.feedbackPricePerDay)}/ngày · '
            '${chef.minPlanDays}–${chef.maxPlanDays} ngày · '
            'Giá cuối do hai bên thoả thuận',
            style: context.textStyles.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Bạn gửi nhu cầu, trao đổi và thoả thuận giá trong chat. Tiền được VeganLife giữ '
            'đến 3 ngày sau khi kế hoạch kết thúc; có vấn đề thì bạn khiếu nại kèm bằng chứng.',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 12),
          if (isOwn)
            VLCard(
              color: vl.aiContainer,
              borderColor: Colors.transparent,
              child: Text(
                'Đây là hồ sơ của bạn. Sửa giá trong Tôi › Chuyên gia › Hồ sơ & bảng giá.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: vl.onAiContainer),
              ),
            )
          else if (!chef.acceptingBookings)
            VLCard(
              color: vl.cautionContainer,
              borderColor: Colors.transparent,
              child: Text('Chuyên gia đang tạm ngưng nhận yêu cầu',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: vl.onCautionContainer)),
            )
          else
            FilledButton.tonalIcon(
              onPressed: onBook,
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Đặt chuyên gia lên thực đơn'),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: context.textStyles.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(label,
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted)),
        ],
      ),
    );
  }
}
