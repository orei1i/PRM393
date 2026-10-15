// lib/features/video/presentation/widgets/video_player_view.dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/widgets/food_cover.dart';

/// 16:9 player that only touches the network after the first tap.
/// Falls back to the illustrated cover when the URL is missing or fails.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView(
      {super.key, required this.url, required this.coverSeed});

  final String? url;
  final String coverSeed;

  @override
  State<VideoPlayerView> createState() => VideoPlayerViewState();
}

class VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _controller;
  bool _starting = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _ensureStarted() async {
    final existing = _controller;
    if (existing != null && existing.value.isInitialized) return true;
    final url = widget.url;
    if (url == null || _starting) {
      if (url == null) setState(() => _failed = true);
      return false;
    }
    await existing?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    if (!mounted) {
      await controller.dispose();
      return false;
    }
    setState(() {
      _controller = controller;
      _starting = true;
      _failed = false;
    });
    try {
      await controller.initialize();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _starting = false);
    return controller.value.isInitialized;
  }

  Future<void> _togglePlay() async {
    if (!await _ensureStarted()) return;
    final c = _controller!;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  /// Jump to a timestamp from the ingredient / step / transcript lists.
  Future<void> seekTo(Duration position) async {
    if (!await _ensureStarted()) return;
    final c = _controller!;
    await c.seekTo(position);
    await c.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        // Inline null check so `controller` is promoted (a bool local doesn't promote).
        child: controller != null && controller.value.isInitialized
            ? ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) => GestureDetector(
                  onTap: _togglePlay,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: AspectRatio(
                            aspectRatio: value.aspectRatio,
                            child: VideoPlayer(controller)),
                      ),
                      AnimatedOpacity(
                        opacity: value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: const Center(
                          child: Icon(Icons.play_circle_fill_rounded,
                              size: 64, color: Colors.white),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.only(top: 12),
                          colors: VideoProgressColors(
                            playedColor:
                                Theme.of(context).colorScheme.secondary,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : GestureDetector(
                onTap: _togglePlay,
                child: FoodCover(
                  seed: widget.coverSeed,
                  aspectRatio: 16 / 9,
                  child: Center(
                    child: _starting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : _failed
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Không phát được video. Chạm để thử lại.',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              )
                            : const Icon(Icons.play_circle_fill_rounded,
                                size: 72, color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }
}
