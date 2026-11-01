// test/video/video_controls_test.dart
// The player of the post page and the restaurant media: controls on a tap,
// auto-hide, seek, mute, fullscreen, errors; and reels keeping their gestures.
// No video plugin here: a fake controller plays.
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:veganlife_mobile/features/restaurant/domain/entities/restaurant.dart';
import 'package:veganlife_mobile/features/restaurant/presentation/widgets/restaurant_media_strip.dart';
import 'package:veganlife_mobile/features/video/presentation/widgets/video_player_view.dart';

class _FakeVideo extends VideoPlayerController {
  _FakeVideo(String url, {this.failInit = false})
      : super.networkUrl(Uri.parse(url));

  final bool failInit;
  bool disposed = false;
  final seeks = <Duration>[];
  int plays = 0;

  @override
  Future<void> initialize() async {
    if (failInit) throw Exception('no such file');
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(minutes: 5, seconds: 3),
      size: const Size(1280, 720),
      volume: 1,
    );
  }

  @override
  Future<void> play() async {
    plays++;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }
}

Future<List<_FakeVideo>> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(411, 800),
    double textScale = 1,
    bool failFirstInit = false,
    bool accessible = false}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final created = <_FakeVideo>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      videoControllerFactoryProvider.overrideWithValue((url) {
        final video =
            _FakeVideo(url, failInit: failFirstInit && created.isEmpty);
        created.add(video);
        return video;
      }),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: accessible,
          ),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  ));
  return created;
}

const _player =
    VideoPlayerView(url: 'https://cdn.test/video.mp4', coverSeed: 'seed');

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.byType(VideoPlayerView));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

double _controlsOpacity(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity;

Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 300));

void main() {
  testWidgets('the network waits for the first tap, then it plays',
      (tester) async {
    final created = await _pump(tester, _player);
    expect(created, isEmpty);
    expect(find.bySemanticsLabel('Phát video'), findsOneWidget);

    await _start(tester);
    expect(created.single.value.isPlaying, isTrue);
    expect(find.byTooltip('Tạm dừng'), findsOneWidget);
    expect(find.text('0:00 / 5:03'), findsOneWidget);
    expect(find.byTooltip('Tắt tiếng'), findsOneWidget);
    expect(find.byTooltip('Toàn màn hình'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(created.single.disposed, isTrue);
  });

  testWidgets('controls hide by themselves and a tap brings them back',
      (tester) async {
    await _pump(tester, _player);
    await _start(tester);
    expect(_controlsOpacity(tester), 1);

    await tester.pump(VideoControls.hideAfter);
    await _settle(tester);
    expect(_controlsOpacity(tester), 0);

    // Hidden controls take no taps: this one lands on the picture.
    final center = tester.getCenter(find.byType(VideoPlayerView));
    await tester.tapAt(center);
    await _settle(tester);
    expect(_controlsOpacity(tester), 1);
    await tester.pump(VideoControls.hideAfter);
    await _settle(tester);
    expect(_controlsOpacity(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paused, they stay; pausing brings them back', (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    await tester.tap(find.byTooltip('Tạm dừng'));
    await _settle(tester);
    expect(created.single.value.isPlaying, isFalse);
    expect(find.byTooltip('Phát'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(_controlsOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a screen reader keeps them on screen', (tester) async {
    await _pump(tester, _player, accessible: true);
    await _start(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(_controlsOpacity(tester), 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bar seeks on release; time follows the thumb',
      (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await tester.pump(kPressTimeoutForTest);
    expect(created.single.seeks, isEmpty, reason: 'only on release');
    expect(find.textContaining('2:'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(created.single.seeks, hasLength(1));
    expect(created.single.seeks.single.inSeconds, inInclusiveRange(120, 180));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mute and back to the volume it had', (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    await tester.tap(find.byTooltip('Tắt tiếng'));
    await tester.pump();
    expect(created.single.value.volume, 0);
    await tester.tap(find.byTooltip('Bật tiếng'));
    await tester.pump();
    expect(created.single.value.volume, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fullscreen uses the same player and comes back', (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    await tester.tap(find.byTooltip('Toàn màn hình'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Thoát toàn màn hình'), findsOneWidget);
    expect(created, hasLength(1));
    expect(created.single.value.isPlaying, isTrue);
    await tester.tap(find.byTooltip('Thoát toàn màn hình'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Toàn màn hình'), findsOneWidget);
    expect(created.single.disposed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a clip that fails to load offers a retry, which works',
      (tester) async {
    final created = await _pump(tester, _player, failFirstInit: true);
    await _start(tester);
    expect(
        find.text('Không phát được video. Chạm để thử lại.'), findsOneWidget);
    await _start(tester);
    expect(created, hasLength(2));
    expect(created.last.value.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no URL says it cannot play', (tester) async {
    await _pump(tester, const VideoPlayerView(url: null, coverSeed: 'seed'));
    await _start(tester);
    expect(
        find.text('Không phát được video. Chạm để thử lại.'), findsOneWidget);
  });

  testWidgets('playback that breaks shows "Thử lại" with a new player',
      (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    created.single.value =
        created.single.value.copyWith(errorDescription: 'boom');
    await tester.pump();
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(created, hasLength(2));
    expect(created.first.disposed, isTrue);
    expect(created.last.value.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('buffering shows a spinner, not a play button', (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    // What the plugin reports mid-play when the data runs out.
    created.single.value =
        created.single.value.copyWith(isBuffering: true, isPlaying: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Phát'), findsNothing);

    created.single.value =
        created.single.value.copyWith(isBuffering: false, isPlaying: true);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byTooltip('Tạm dừng'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the message of a broken clip sits on a dark plate',
      (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    created.single.value =
        created.single.value.copyWith(errorDescription: 'lost');
    await tester.pump();
    final plate = tester.widget<Container>(find.ancestor(
        of: find.textContaining('Không phát được video'),
        matching: find.byType(Container)));
    expect((plate.decoration! as BoxDecoration).color?.a, greaterThan(0.5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the restaurant viewer title is readable on black',
      (tester) async {
    tester.view
      ..physicalSize = const Size(411, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      // A title style with a colour of its own, as in AppTheme.
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
            titleTextStyle: TextStyle(color: Color(0xFF102030), fontSize: 20)),
      ),
      home: const RestaurantMediaViewer(
        media: RestaurantMedia(
            id: 'm1',
            type: RestaurantMediaType.image,
            url: 'https://cdn.test/quan.jpg'),
      ),
    ));
    await tester.pump();
    final title =
        tester.renderObject<RenderParagraph>(find.text('Ảnh của quán'));
    expect(title.text.style?.color, Colors.white);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the end of the clip offers "Phát lại" from the start',
      (tester) async {
    final created = await _pump(tester, _player);
    await _start(tester);
    final video = created.single;
    await video.pause();
    video.value = video.value.copyWith(position: video.value.duration);
    await tester.pump();
    await tester.tap(find.byTooltip('Phát lại'));
    await tester.pump();
    expect(video.seeks.last, Duration.zero);
    expect(video.value.isPlaying, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final fullscreen in [false, true]) {
    testWidgets(
        'no overflow at 360 dp with font scale 1.3 '
        '(${fullscreen ? 'fullscreen' : 'inline'})', (tester) async {
      await _pump(tester, _player, size: const Size(360, 640), textScale: 1.3);
      await _start(tester);
      if (fullscreen) {
        await tester.tap(find.byTooltip('Toàn màn hình'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the restaurant video has the same controls', (tester) async {
    final created = await _pump(
      tester,
      const RestaurantMediaViewer(
        media: RestaurantMedia(
            id: 'm1',
            type: RestaurantMediaType.video,
            url: 'https://cdn.test/quan.mp4'),
      ),
    );
    await _start(tester);
    expect(created.single.value.isPlaying, isTrue);
    expect(find.byTooltip('Toàn màn hình'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

/// Long enough for the slider's drag to start.
const kPressTimeoutForTest = Duration(milliseconds: 120);
