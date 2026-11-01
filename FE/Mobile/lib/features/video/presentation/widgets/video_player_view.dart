// lib/features/video/presentation/widgets/video_player_view.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';

typedef VideoControllerFactory = VideoPlayerController Function(String url);

/// Creates the player of a [VideoPlayerView]. Widget tests swap it (there is no
/// video plugin there).
final videoControllerFactoryProvider = Provider<VideoControllerFactory>(
    (ref) => (url) => VideoPlayerController.networkUrl(Uri.parse(url)));

/// 16:9 player that only touches the network after the first tap, then shows
/// [VideoControls]. Falls back to the illustrated cover when the URL is missing
/// or fails ("Chạm để thử lại"), and pauses when the app leaves the foreground.
class VideoPlayerView extends ConsumerStatefulWidget {
  const VideoPlayerView(
      {super.key, required this.url, required this.coverSeed});

  final String? url;
  final String coverSeed;

  @override
  ConsumerState<VideoPlayerView> createState() => VideoPlayerViewState();
}

class VideoPlayerViewState extends ConsumerState<VideoPlayerView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _starting = false;
  bool _failed = false;

  /// The full-screen page shows the picture; this one only keeps the place.
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (!mounted) return false;
    final VideoPlayerController controller;
    try {
      controller = ref.read(videoControllerFactoryProvider)(url);
    } catch (_) {
      setState(() {
        _controller = null;
        _failed = true;
      });
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

  Future<void> _start() async {
    if (await _ensureStarted()) await _controller!.play();
  }

  /// A clip that failed while playing starts over with a new player.
  Future<void> _retry() async {
    final broken = _controller;
    setState(() => _controller = null);
    await broken?.dispose();
    if (mounted) await _start();
  }

  /// Jump to a timestamp from the ingredient / step / transcript lists.
  Future<void> seekTo(Duration position) async {
    if (!await _ensureStarted()) return;
    final c = _controller!;
    await c.seekTo(position);
    await c.play();
  }

  Future<void> _openFullscreen() async {
    final c = _controller;
    if (c == null) return;
    setState(() => _fullscreen = true);
    final retry = await Navigator.of(context, rootNavigator: true)
        .push(_FullscreenVideoPage.route(c));
    if (!mounted) return;
    setState(() => _fullscreen = false);
    if (retry == true) await _retry();
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
            ? _fullscreen
                ? const SizedBox.expand()
                : VideoControls(
                    controller: controller,
                    onToggleFullscreen: _openFullscreen,
                    onRetry: _retry,
                  )
            : Semantics(
                button: true,
                label: _failed
                    ? 'Không phát được video. Chạm để thử lại'
                    : 'Phát video',
                child: GestureDetector(
                  onTap: _start,
                  child: FoodCover(
                    seed: widget.coverSeed,
                    aspectRatio: 16 / 9,
                    child: Center(
                      child: _starting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : _failed
                              ? const _PlayError()
                              : const Icon(Icons.play_circle_fill_rounded,
                                  size: 72, color: Colors.white),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// "Không phát được video" on a dark plate.
class _PlayError extends StatelessWidget {
  const _PlayError();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Không phát được video. Chạm để thử lại.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A started video with its controls: play/pause in the middle, seek bar,
/// "0:12 / 5:03", mute and fullscreen at the bottom. A tap on the picture shows
/// or hides them; they hide by themselves after [hideAfter] while playing, and
/// stay for as long as the video is paused or a screen reader is on. Shows a
/// spinner while buffering and "Thử lại" when playback breaks.
class VideoControls extends StatefulWidget {
  const VideoControls({
    super.key,
    required this.controller,
    required this.onToggleFullscreen,
    required this.onRetry,
    this.isFullscreen = false,
  });

  static const hideAfter = Duration(seconds: 3);

  final VideoPlayerController controller;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onRetry;
  final bool isFullscreen;

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  bool _visible = true;
  bool _wasPlaying = false;
  Timer? _hide;

  /// Where the thumb is while dragging (ms): the video seeks on release.
  double? _dragMs;

  /// What the speaker button brings back.
  double _volumeBeforeMute = 1;

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _wasPlaying = _c.value.isPlaying;
    _c.addListener(_onValue);
    if (_wasPlaying) _scheduleHide();
  }

  @override
  void didUpdateWidget(VideoControls old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onValue);
      widget.controller.addListener(_onValue);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onValue);
    _hide?.cancel();
    super.dispose();
  }

  /// Starting hides the controls after a while, pausing brings them back.
  void _onValue() {
    final playing = _c.value.isPlaying;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (playing) {
      _scheduleHide();
    } else {
      _hide?.cancel();
      if (mounted && !_visible) setState(() => _visible = true);
    }
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(VideoControls.hideAfter, () {
      if (mounted && _c.value.isPlaying && _dragMs == null) {
        setState(() => _visible = false);
      }
    });
  }

  /// Any use of a control keeps them on screen a while longer.
  void _touched() {
    if (_c.value.isPlaying) _scheduleHide();
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _touched();
    } else {
      _hide?.cancel();
    }
  }

  Future<void> _togglePlay() async {
    final value = _c.value;
    if (value.isPlaying) {
      await _c.pause();
    } else {
      if (_ended(value)) await _c.seekTo(Duration.zero);
      await _c.play();
    }
  }

  void _toggleMute() {
    final volume = _c.value.volume;
    if (volume > 0) _volumeBeforeMute = volume;
    _c.setVolume(volume > 0 ? 0 : _volumeBeforeMute);
    _touched();
  }

  static bool _ended(VideoPlayerValue v) =>
      !v.isPlaying && v.duration > Duration.zero && v.position >= v.duration;

  static String _time(Duration d) => formatDuration(d.inSeconds);

  @override
  Widget build(BuildContext context) {
    // A screen reader can't tap a picture to find the buttons.
    final alwaysVisible = MediaQuery.accessibleNavigationOf(context);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _c,
      builder: (context, value, _) {
        final visible = alwaysVisible || _visible;
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                  aspectRatio: value.aspectRatio, child: VideoPlayer(_c)),
            ),
            Semantics(
              button: true,
              label: 'Hiện hoặc ẩn điều khiển video',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleVisible,
              ),
            ),
            if (value.hasError)
              Center(child: _BrokenPlayback(onRetry: widget.onRetry))
            else ...[
              if (value.isBuffering)
                const IgnorePointer(child: Center(child: _BufferingSpinner())),
              IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: _controls(context, value),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, VideoPlayerValue value) {
    final ended = _ended(value);
    final durationMs = value.duration.inMilliseconds;
    final positionMs = math.min(value.position.inMilliseconds, durationMs);
    final shownMs = _dragMs ?? positionMs.toDouble();
    final time = '${_time(Duration(milliseconds: shownMs.round()))} / '
        '${_time(value.duration)}';
    final muted = value.volume == 0;
    const white = Colors.white;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The player reads as "not playing" while it waits for data: a play
        // button here would cover the spinner and suggest it was paused.
        if (!value.isBuffering)
          Center(
            child: IconButton(
              tooltip: ended
                  ? 'Phát lại'
                  : value.isPlaying
                      ? 'Tạm dừng'
                      : 'Phát',
              iconSize: 56,
              color: white,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.35)),
              onPressed: _togglePlay,
              icon: Icon(ended
                  ? Icons.replay_rounded
                  : value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
            ),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
            child: SafeArea(
              top: false,
              left: widget.isFullscreen,
              right: widget.isFullscreen,
              bottom: widget.isFullscreen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: 'Tua video',
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: white,
                        thumbColor: white,
                        inactiveTrackColor: Colors.white38,
                        disabledActiveTrackColor: Colors.white38,
                        disabledInactiveTrackColor: Colors.white24,
                        disabledThumbColor: Colors.white38,
                      ),
                      child: Slider(
                        value: shownMs
                            .clamp(0, math.max(durationMs, 1))
                            .toDouble(),
                        max: math.max(durationMs, 1).toDouble(),
                        semanticFormatterCallback: (_) => time,
                        onChangeStart: (_) => _hide?.cancel(),
                        onChanged: durationMs == 0
                            ? null
                            : (ms) => setState(() => _dragMs = ms),
                        onChangeEnd: (ms) async {
                          await _c.seekTo(Duration(milliseconds: ms.round()));
                          if (mounted) setState(() => _dragMs = null);
                          _touched();
                        },
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Text(
                            time,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: muted ? 'Bật tiếng' : 'Tắt tiếng',
                        color: white,
                        visualDensity: VisualDensity.compact,
                        onPressed: _toggleMute,
                        icon: Icon(muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded),
                      ),
                      IconButton(
                        tooltip: widget.isFullscreen
                            ? 'Thoát toàn màn hình'
                            : 'Toàn màn hình',
                        color: white,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onToggleFullscreen,
                        icon: Icon(widget.isFullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// On a dark plate, so it shows on a bright frame too.
class _BufferingSpinner extends StatelessWidget {
  const _BufferingSpinner();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

/// Playback stopped halfway (lost connection, unreadable file).
class _BrokenPlayback extends StatelessWidget {
  const _BrokenPlayback({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Không phát được video. Kiểm tra kết nối rồi thử lại.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

/// The same player on a black page: immersive, and sideways for a landscape
/// clip. The inline view keeps owning the controller, so "Thử lại" pops `true`
/// and it starts over there.
class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.controller});

  static Route<bool> route(VideoPlayerController controller) =>
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenVideoPage(controller: controller),
      );

  final VideoPlayerController controller;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (widget.controller.value.aspectRatio > 1) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoControls(
        controller: widget.controller,
        isFullscreen: true,
        onToggleFullscreen: () => Navigator.of(context).maybePop(),
        onRetry: () => Navigator.of(context).pop(true),
      ),
    );
  }
}
