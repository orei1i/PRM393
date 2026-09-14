import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/app_widgets.dart';
import '../../../../core/widgets/food_art.dart';
import '../view_models/video_player_view_model.dart';

class VideoPlayerMockView extends StatelessWidget {
  const VideoPlayerMockView({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VideoPlayerViewModel>();
    final post = vm.post;
    if (post == null) {
      return const EmptyState(
        title: 'Video unavailable',
        message: 'This video does not exist or has been removed.',
      );
    }
    return PageBody(
      maxWidth: 820,
      children: [
        PageHeading(
          title: post.title,
          subtitle: 'Simulated player · no video is downloaded or streamed.',
        ),
        FoodArt(height: 300, variant: post.art),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filled(
                    onPressed: vm.toggle,
                    tooltip: vm.playing ? 'Pause demo' : 'Play demo',
                    icon: Icon(vm.playing ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: vm.progress,
                      onChanged: vm.seek,
                      label: vm.elapsed,
                    ),
                  ),
                ],
              ),
              Text('${vm.elapsed} / ${vm.durationLabel}'),
              const SizedBox(height: 10),
              Text(
                vm.playing
                    ? 'Demo playing — follow the written recipe alongside.'
                    : 'Ready when you are.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
