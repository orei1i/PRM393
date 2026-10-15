// lib/features/chef/presentation/screens/chef_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../commerce/data/models/order_model.dart';
import '../../../commerce/presentation/controllers/commerce_controllers.dart';
import '../../../commerce/presentation/screens/payment_screen.dart';
import '../../../commerce/presentation/screens/service_content_screen.dart';
import '../../../commerce/presentation/widgets/commerce_ui.dart';
import '../../data/chef_api_service.dart';
import '../../domain/entities/chef.dart';
import '../widgets/booking_sheet.dart';
import '../widgets/chef_card.dart';
import '../widgets/purchase_sheet.dart';
import '../widgets/service_tile.dart';

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
    return !me.isGuest && chef.userId != null && chef.userId == me.userId;
  }

  /// Order created in a sheet → refresh slots and lists, then pay.
  Future<void> _pay(OrderDto? order) async {
    if (order == null || !mounted) return;
    ref.read(commerceRevisionProvider.notifier).bump();
    _reload(); // the held slot leaves the calendar
    await Navigator.of(context).push(PaymentScreen.route(order.id));
    if (mounted) _reload(); // expired / cancelled orders release it again
  }

  Future<bool> _signedInBuyer(Chef chef, String reason) async {
    if (!await ensureSignedIn(context, ref, reason: reason)) return false;
    if (!mounted) return false;
    if (_isOwn(chef)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Đây là dịch vụ của bạn, không tự đặt được.')));
      return false;
    }
    return true;
  }

  Future<void> _book(Chef chef, {ChefService? service}) async {
    if (!await _signedInBuyer(
        chef, 'Đăng nhập để đặt lịch tư vấn với chuyên gia.')) {
      return;
    }
    if (!mounted) return;
    final order = await showModalBottomSheet<OrderDto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BookingSheet(chef: chef, initialService: service),
    );
    await _pay(order);
  }

  Future<void> _buy(Chef chef, ChefService service) async {
    if (!await _signedInBuyer(
        chef, 'Đăng nhập để mua khoá học, thực đơn của chuyên gia.')) {
      return;
    }
    if (!mounted) return;
    final order = await showModalBottomSheet<OrderDto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PurchaseSheet(chef: chef, service: service),
    );
    await _pay(order);
  }

  void _openContent(ChefService service) => Navigator.of(context)
      .push(ServiceContentScreen.route(service.id, title: service.title));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Chef>(
      future: _future,
      builder: (context, snapshot) {
        final chef = snapshot.data ?? widget.preview;
        final loadingDetail = snapshot.connectionState != ConnectionState.done;

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
                          chef: chef,
                          isOwn: _isOwn(chef),
                          owned: ref.watch(ownedServiceIdsProvider),
                          onBook: (s) => _book(chef, service: s),
                          onBuy: (s) => _buy(chef, s),
                          onOpenContent: _openContent,
                        ),
                      ),
                  ],
                ),
          bottomNavigationBar: chef == null ||
                  loadingDetail ||
                  snapshot.hasError ||
                  chef.consultServices.isEmpty ||
                  _isOwn(chef)
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
                              formatVnd(chef.startingPriceVnd),
                              style: context.textStyles.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _book(chef,
                                service: chef.consultServices.first),
                            icon: const Icon(Icons.event_available_rounded),
                            label: const Text('Đặt lịch tư vấn'),
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
  const _Details({
    required this.chef,
    required this.isOwn,
    required this.owned,
    required this.onBook,
    required this.onBuy,
    required this.onOpenContent,
  });

  final Chef chef;

  /// The signed-in chef looking at their own public page.
  final bool isOwn;

  /// Packages the member can already open.
  final Set<String> owned;
  final ValueChanged<ChefService> onBook;
  final ValueChanged<ChefService> onBuy;
  final ValueChanged<ChefService> onOpenContent;

  Widget? _action(ChefService s) {
    if (isOwn) return null;
    if (s.type == ServiceType.consult) {
      return FilledButton.tonalIcon(
        onPressed: () => onBook(s),
        icon: const Icon(Icons.event_available_rounded, size: 18),
        label: const Text('Đặt lịch tư vấn'),
      );
    }
    if (owned.contains(s.id)) {
      return OutlinedButton.icon(
        onPressed: () => onOpenContent(s),
        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
        label: const Text('Mở nội dung'),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => onBuy(s),
      icon: const Icon(Icons.shopping_bag_outlined, size: 18),
      label: const Text('Mua gói'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Stat(value: formatInt(chef.consultCount), label: 'buổi tư vấn'),
              _Stat(value: '${chef.yearsExperience} năm', label: 'kinh nghiệm'),
              _Stat(
                  value: formatDecimal(chef.rating),
                  label: '${formatInt(chef.reviewCount)} đánh giá'),
            ],
          ),
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
          const SizedBox(height: 16),
          Text('Dịch vụ', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          if (isOwn)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VLCard(
                color: context.vl.aiContainer,
                borderColor: Colors.transparent,
                child: Text(
                  'Đây là trang công khai của bạn. Sửa dịch vụ trong Tôi › Bảng điều khiển chuyên gia.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.onAiContainer),
                ),
              ),
            ),
          if (chef.services.isEmpty)
            Text('Chuyên gia chưa mở dịch vụ nào.',
                style: context.textStyles.bodyMedium
                    ?.copyWith(color: context.vl.muted)),
          for (final s in chef.services)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ServiceTile(service: s, action: _action(s)),
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
