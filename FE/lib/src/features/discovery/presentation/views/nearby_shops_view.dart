import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../domain/entities/shop_entities.dart';
import '../view_models/nearby_shops_view_model.dart';

class NearbyShopsView extends StatelessWidget {
  const NearbyShopsView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NearbyShopsViewModel>();
    return PageBody(
      children: [
        const PageHeading(
          eyebrow: 'Good things nearby',
          title: 'Find your local green.',
          subtitle: 'Fictional sample listings · Ho Chi Minh City',
        ),
        TextFormField(
          initialValue: vm.query,
          onChanged: vm.setQuery,
          decoration: const InputDecoration(
            hintText: 'Search shops, cafés, and neighborhoods',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('List'),
                  icon: Icon(Icons.view_list_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Map'),
                  icon: Icon(Icons.map_outlined),
                ),
              ],
              selected: {vm.mapMode},
              onSelectionChanged: (s) => vm.setMap(s.first),
            ),
            ...NearbyShopsViewModel.kinds.map(
              (kind) => ChoiceChip(
                label: Text(kind),
                selected: vm.kind == kind,
                onSelected: (_) => vm.setKind(kind),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Distance from a fixed demo location, nearest first. No live GPS, opening hours, or verified reviews.',
        ),
        const SizedBox(height: 20),
        if (vm.results.isEmpty)
          const EmptyState(
            title: 'No places found',
            message: 'Try a different search or category.',
          ),
        if (vm.mapMode && vm.results.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 330,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MapPainter(Theme.of(context).colorScheme),
                    ),
                  ),
                  const Positioned(
                    left: 16,
                    right: 16,
                    top: 16,
                    child: StatusBadge('SCHEMATIC · NOT A NAVIGATION MAP'),
                  ),
                  for (final (index, item) in vm.results.indexed)
                    Align(
                      alignment: Alignment(
                        -.65 + (index % 3) * .6,
                        -.2 + (index ~/ 3) * .8,
                      ),
                      child: Tooltip(
                        message: '${item.shop.name} · ${item.distanceLabel}',
                        child: IconButton.filled(
                          onPressed: () => vm.selectShop(item.shop.id),
                          icon: const Icon(Icons.location_on),
                          tooltip: item.shop.name,
                        ),
                      ),
                    ),
                  const Align(
                    alignment: Alignment(0, .4),
                    child: Chip(
                      avatar: Icon(Icons.my_location, size: 16),
                      label: Text('Demo location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (vm.selected != null)
            _ShopCard(
              result: vm.selected!,
              onSelect: () => _showDetails(context, vm.selected!),
            ),
        ] else
          AdaptiveCards(
            minWidth: 320,
            children: [
              for (final item in vm.results)
                _ShopCard(
                  result: item,
                  onSelect: () => _showDetails(context, item),
                ),
            ],
          ),
      ],
    );
  }

  void _showDetails(
    BuildContext context,
    ShopResult result,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.shop.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(result.shop.description),
            const SizedBox(height: 12),
            Text(
              '${result.shop.address}\n${result.distanceLabel} from demo location',
            ),
            const SizedBox(height: 18),
            const Text(
              'This is a fictional listing for UI testing. Verify real venues before visiting.',
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.result, required this.onSelect});
  final ShopResult result;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.storefront_outlined, size: 30),
            ),
            const Spacer(),
            StatusBadge(result.distanceLabel),
          ],
        ),
        const SizedBox(height: 18),
        Text(result.shop.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('${result.shop.kind} · ★ ${result.shop.rating} (sample)'),
        const SizedBox(height: 12),
        Text(result.shop.description),
        const SizedBox(height: 12),
        Text(result.shop.address, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onSelect, child: const Text('View details')),
      ],
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.colors);
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainerHighest,
    );
    final road = Paint()
      ..color = colors.surface
      ..strokeWidth = 16;
    for (var x = -200.0; x < size.width; x += 80) {
      canvas.drawLine(Offset(x, 0), Offset(x + 170, size.height), road);
    }
    for (var y = 60.0; y < size.height; y += 75) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 50), road);
    }
    canvas.drawOval(
      Rect.fromLTWH(size.width * .6, 100, 160, 80),
      Paint()..color = colors.primaryContainer,
    );
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => colors != oldDelegate.colors;
}
