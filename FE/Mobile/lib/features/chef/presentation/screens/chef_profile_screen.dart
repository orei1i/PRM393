// lib/features/chef/presentation/screens/chef_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/chef_api_service.dart';
import '../../domain/entities/chef.dart';
import '../controllers/chef_controllers.dart';
import '../widgets/booking_sheet.dart';
import '../widgets/chef_card.dart';
import 'my_consultations_screen.dart';

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

  Future<void> _book(Chef chef, {ConsultPackage? package}) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để đặt lịch tư vấn với chuyên gia.')) {
      return;
    }
    if (!mounted) return;
    final booked = await showModalBottomSheet<Consultation>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BookingSheet(chef: chef, initialPackage: package),
    );
    if (booked == null || !mounted) return;
    ref.invalidate(myConsultationsProvider);
    _reload(); // refresh free slots
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            const Text('Đã gửi yêu cầu. Chuyên gia sẽ xác nhận trong 24 giờ.'),
        action: SnackBarAction(
          label: 'Xem lịch',
          onPressed: () => navigator.push(MyConsultationsScreen.route()),
        ),
      ),
    );
  }

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
                              onBook: (p) => _book(chef, package: p))),
                  ],
                ),
          bottomNavigationBar:
              chef == null || loadingDetail || snapshot.hasError
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
                                onPressed: () => _book(chef),
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
  const _Details({required this.chef, required this.onBook});

  final Chef chef;
  final ValueChanged<ConsultPackage> onBook;

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
              for (final s in chef.specialties) VLTag.neutral(context, s)
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
          Text('Gói tư vấn', style: context.textStyles.titleMedium),
          const SizedBox(height: 8),
          for (final p in chef.packages)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PackageTile(package: p, onTap: () => onBook(p)),
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

class PackageTile extends StatelessWidget {
  const PackageTile(
      {super.key, required this.package, this.onTap, this.selected = false});

  final ConsultPackage package;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      onTap: onTap,
      borderColor: selected ? context.colors.primary : null,
      color: selected ? context.colors.secondaryContainer : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(package.name,
                    style: context.textStyles.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(package.description,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: context.vl.muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    VLTag.neutral(context, '${package.durationMinutes} phút'),
                    VLTag.neutral(context, package.mode.label),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatVnd(package.priceVnd),
                style: context.textStyles.titleSmall?.copyWith(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (selected) ...[
                const SizedBox(height: 6),
                Icon(Icons.check_circle_rounded, color: context.colors.primary),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
