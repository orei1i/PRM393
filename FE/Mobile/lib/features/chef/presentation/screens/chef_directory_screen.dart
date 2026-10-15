// lib/features/chef/presentation/screens/chef_directory_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/chef_specialties.dart';
import '../../domain/entities/chef.dart';
import '../controllers/chef_controllers.dart';
import '../widgets/chef_card.dart';
import 'chef_profile_screen.dart';
import 'my_consultations_screen.dart';

/// Tab "Chuyên gia": verified chefs & nutritionists, bookable 1-on-1.
class ChefDirectoryScreen extends ConsumerStatefulWidget {
  const ChefDirectoryScreen({super.key});

  @override
  ConsumerState<ChefDirectoryScreen> createState() =>
      _ChefDirectoryScreenState();
}

class _ChefDirectoryScreenState extends ConsumerState<ChefDirectoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(chefDirectoryProvider.notifier).search(value);
    });
    setState(() {}); // toggles the clear button
  }

  void _open(Chef chef) => Navigator.of(context)
      .push(ChefProfileScreen.route(chef.id, preview: chef));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(chefDirectoryProvider);
    final specialty = async.hasValue ? async.requireValue.specialty : null;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text('Chuyên gia'),
            actions: [
              IconButton(
                tooltip: 'Lịch tư vấn của tôi',
                onPressed: () =>
                    Navigator.of(context).push(MyConsultationsScreen.route()),
                icon: const Icon(Icons.event_note_outlined),
              ),
            ],
          ),
          const SliverToBoxAdapter(child: _UpcomingBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, chuyên môn, thành phố…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xoá',
                          onPressed: () {
                            _search.clear();
                            _onQueryChanged('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: context.vl.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: context.vl.border),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: chefSpecialties.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final value = i == 0 ? null : chefSpecialties[i - 1];
                  return ChoiceChip(
                    label: Text(value ?? 'Tất cả'),
                    selected: specialty == value,
                    onSelected: (_) => ref
                        .read(chefDirectoryProvider.notifier)
                        .setSpecialty(value),
                  );
                },
              ),
            ),
          ),
          if (async.hasValue && async.requireValue.searching)
            const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2)),
          ...switch (async) {
            AsyncData(:final value) when value.chefs.isEmpty => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: EmptyStateView(
                      icon: Icons.person_search_outlined,
                      title: 'Không tìm thấy chuyên gia phù hợp',
                      message:
                          'Thử bỏ bớt từ khoá hoặc chọn "Tất cả" chuyên môn.',
                      actionLabel: 'Xoá bộ lọc',
                      onAction: () {
                        _search.clear();
                        ref.read(chefDirectoryProvider.notifier)
                          ..setSpecialty(null)
                          ..search('');
                      },
                    ),
                  ),
                ),
              ],
            AsyncData(:final value) => [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ChefCard(
                            chef: value.chefs[i],
                            onTap: () => _open(value.chefs[i])),
                      ),
                      childCount: value.chefs.length,
                    ),
                  ),
                ),
              ],
            AsyncError(:final error) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ErrorStateView(
                        error: error,
                        onRetry: () => ref.invalidate(chefDirectoryProvider)),
                  ),
                ),
              ],
            _ => [const SliverToBoxAdapter(child: _DirectorySkeleton())],
          },
        ],
      ),
    );
  }
}

/// "Lịch sắp tới" shortcut when the member has an upcoming consultation.
class _UpcomingBanner extends ConsumerWidget {
  const _UpcomingBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myConsultationsProvider);
    final items = (async.hasValue ? async.requireValue : const <Consultation>[])
        .where(
            (c) => c.status.isUpcoming && c.scheduledAt.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final upcoming = items.isEmpty ? null : items.first;

    if (upcoming == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: VLCard(
          color: context.colors.secondaryContainer,
          borderColor: Colors.transparent,
          child: Row(
            children: [
              Icon(Icons.verified_rounded, color: context.vl.success),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Đầu bếp & chuyên gia dinh dưỡng đều đã được VeganLife xác minh chứng chỉ.',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.colors.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final t = upcoming.scheduledAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: VLCard(
        onTap: () => Navigator.of(context).push(MyConsultationsScreen.route()),
        color: context.vl.successContainer,
        borderColor: Colors.transparent,
        child: Row(
          children: [
            Icon(Icons.event_available_rounded,
                color: context.vl.onSuccessContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lịch sắp tới · ${upcoming.status.label}',
                    style: context.textStyles.labelLarge
                        ?.copyWith(color: context.vl.onSuccessContainer),
                  ),
                  Text(
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} '
                    '${formatLongDate(t)} với ${upcoming.chefName}',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.onSuccessContainer),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.vl.onSuccessContainer),
          ],
        ),
      ),
    );
  }
}

class _DirectorySkeleton extends StatelessWidget {
  const _DirectorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: VLCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 56, height: 56, radius: 28),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 160, height: 16),
                          SizedBox(height: 8),
                          SkeletonBox(height: 12),
                          SizedBox(height: 8),
                          SkeletonBox(width: 120, height: 12),
                          SizedBox(height: 12),
                          SkeletonBox(width: 90, height: 14),
                        ],
                      ),
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
