// lib/features/reels/presentation/screens/reels_player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../community/domain/entities/post.dart';
import '../../domain/reel.dart';
import '../widgets/reel_page.dart';

/// Full-screen vertical Reels player: swipe up for the next clip, tap to
/// pause, like / comment / share / save on the right, author, caption and
/// "Xem công thức" at the bottom. Clips autoplay muted; the speaker button
/// turns sound on for the whole session.
class ReelsPlayerScreen extends ConsumerStatefulWidget {
  const ReelsPlayerScreen(
      {super.key, required this.reels, this.initialIndex = 0});

  final List<Reel> reels;
  final int initialIndex;

  static Route<void> route(List<Reel> reels, {int initialIndex = 0}) =>
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            ReelsPlayerScreen(reels: reels, initialIndex: initialIndex),
      );

  @override
  ConsumerState<ReelsPlayerScreen> createState() => _ReelsPlayerScreenState();
}

class _ReelsPlayerScreenState extends ConsumerState<ReelsPlayerScreen> {
  late final List<Reel> _reels = [...widget.reels];
  late int _current =
      widget.initialIndex.clamp(0, _reels.isEmpty ? 0 : _reels.length - 1);
  late final _pages = PageController(initialPage: _current);
  bool _muted = true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _changed(int index, Post post) =>
      setState(() => _reels[index] = _reels[index].withPost(post));

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_reels.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Chưa có reel nào. Quay lại sau nhé!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ),
              )
            else
              PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                itemCount: _reels.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) => ReelPage(
                  key: ValueKey(_reels[i].id),
                  reel: _reels[i],
                  active: i == _current,
                  muted: _muted,
                  onChanged: (post) => _changed(i, post),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: IconButton.styleFrom(
                            backgroundColor: const Color(0x59000000),
                            minimumSize: const Size(48, 48)),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Reels',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              shadows: [Shadow(blurRadius: 6)]),
                        ),
                      ),
                      if (_reels.isNotEmpty)
                        IconButton(
                          tooltip: _muted ? 'Bật tiếng' : 'Tắt tiếng',
                          onPressed: () => setState(() => _muted = !_muted),
                          style: IconButton.styleFrom(
                              backgroundColor: const Color(0x59000000),
                              minimumSize: const Size(48, 48)),
                          icon: Icon(
                              _muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              color: Colors.white),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
