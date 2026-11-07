import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/model.dart';
import 'package:telefon_tv/tv/screens/browser_screen.dart';
import 'package:telefon_tv/tv/screens/player_screen.dart';
import 'package:telefon_tv/tv/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakePlayer extends VideoPlayerPlatform {
  int nextId = 0;
  bool autoInitialize = true;
  Duration duration = const Duration(minutes: 2);
  int mostPlaying = 0;
  final events = <int, StreamController<VideoEvent>>{};
  final playing = <int>{};
  final disposed = <int>{};
  final disposeGates = <int, Completer<void>>{};
  final sources = <int, String>{};
  final positions = <int, Duration>{};

  void initialize(int id) => events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: duration,
      size: const Size(1280, 720),
    ),
  );

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = ++nextId;
    events[id] = StreamController<VideoEvent>.broadcast(
      onListen: () {
        if (autoInitialize) initialize(id);
      },
    );
    sources[id] = dataSource.uri!;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    playing.add(playerId);
    if (playing.length > mostPlaying) mostPlaying = playing.length;
  }

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> dispose(int playerId) async {
    await disposeGates[playerId]?.future;
    disposed.add(playerId);
    playing.remove(playerId);
    await events[playerId]?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;
  @override
  Widget buildView(int playerId) => const SizedBox();
}

void main() {
  late FakePlayer fake;
  late VideoPlayerPlatform previousPlatform;
  MediaItem item(String name) => MediaItem(
    title: name,
    source: 'https://example.com/$name.mp4',
    kind: MediaKind.video,
  );

  setUp(() {
    previousPlatform = VideoPlayerPlatform.instance;
    fake = FakePlayer();
    VideoPlayerPlatform.instance = fake;
  });
  tearDown(() {
    VideoPlayerPlatform.instance = previousPlatform;
    TvServices.instance.dispose();
  });

  Future<void> setup(WidgetTester tester, List<MediaItem> items) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: TvInput.instance.navigatorKey,
        navigatorObservers: [TvInput.instance.routes],
        home: const Scaffold(body: Text('HOME')),
      ),
    );
    TvInput.instance.navigatorKey.currentState!.push(
      PlayerScreen.route(items, 0),
    );
    if (fake.autoInitialize) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'yangi video ochilganda avvalgisi to‘xtab, qaytishda davom etadi',
    (tester) async {
      await setup(tester, [item('first')]);
      expect(fake.playing, {1});

      TvServices.instance.receiveMedia([item('second')]);
      await tester.pumpAndSettle();
      expect(fake.playing, {2});

      TvInput.instance.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fake.playing, {1});
      expect(fake.mostPlaying, 1);
      await cleanUp(tester);
    },
  );

  testWidgets('brauzer ochilganda video to‘xtaydi va qaytishda davom etadi', (
    tester,
  ) async {
    await setup(tester, [item('first')]);
    TvInput.instance.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const BrowserScreen()),
    );
    await tester.pumpAndSettle();
    expect(fake.playing, isEmpty);

    // Native ijro qayta yoqilsa ham yashirin pleyer pauzada qoladi.
    fake.playing.add(1);
    fake.events[1]!.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
    await tester.pump();
    expect(fake.playing, isEmpty);

    TvInput.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fake.playing, {1});
    await cleanUp(tester);
  });

  testWidgets('qo‘lda pauza qilingan video qaytganda o‘zi yoqilmaydi', (
    tester,
  ) async {
    await setup(tester, [item('first')]);
    TvInput.instance.send(Cmd.playPause);
    await tester.pumpAndSettle();
    expect(fake.playing, isEmpty);
    TvInput.instance.navigatorKey.currentState!.push(
      PlayerScreen.route([item('second')], 0),
    );
    await tester.pumpAndSettle();
    TvInput.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fake.playing, isEmpty);
    await cleanUp(tester);
  });

  testWidgets('yashirin ekranda kech tayyor bo‘lgan video ijro etilmaydi', (
    tester,
  ) async {
    fake.autoInitialize = false;
    await setup(tester, [item('first')]);
    TvInput.instance.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const BrowserScreen()),
    );
    await tester.pumpAndSettle();
    fake.initialize(1);
    await tester.pumpAndSettle();
    expect(fake.playing, isEmpty);
    TvInput.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(fake.playing, {1});
    await cleanUp(tester);
  });

  testWidgets('kanal almashayotganida chiqish yangi pleyer yaratmaydi', (
    tester,
  ) async {
    await setup(tester, [item('first'), item('second')]);
    final gate = fake.disposeGates[1] = Completer<void>();
    TvInput.instance.send(Cmd.next);
    await tester.pump();
    TvInput.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(fake.nextId, 1);
    expect(fake.playing, isEmpty);
    await cleanUp(tester);
  });

  testWidgets('tez almashtirish faqat oxirgi tanlangan videoni ochadi', (
    tester,
  ) async {
    await setup(tester, [item('first'), item('second'), item('third')]);
    final gate = fake.disposeGates[1] = Completer<void>();
    TvInput.instance.send(Cmd.next);
    await tester.pump();
    TvInput.instance.send(Cmd.next);
    await tester.pump();
    gate.complete();
    // Native oqim obunasining asinxron yopilishini ham yakunlaymiz.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(fake.sources.values, [
      'https://example.com/first.mp4',
      'https://example.com/third.mp4',
    ]);
    expect(fake.playing, {2});
    expect(fake.mostPlaying, 1);
    await cleanUp(tester);
  });
  testWidgets('stalled live channel reconnects even without buffering events', (
    tester,
  ) async {
    fake.duration = const Duration(days: 1);
    final live = MediaItem(
      title: 'Live',
      source: 'https://example.com/live.m3u8',
      kind: MediaKind.live,
    );
    await setup(tester, [live]);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(fake.nextId, greaterThanOrEqualTo(2));
    expect(fake.sources.values.every((s) => s == live.source), isTrue);
    expect(fake.mostPlaying, 1);
    await cleanUp(tester);
  });

  testWidgets('30 minutes progressing live playback does not reconnect', (
    tester,
  ) async {
    fake.duration = const Duration(days: 1);
    final live = MediaItem(
      title: 'Live',
      source: 'https://example.com/live.m3u8',
      kind: MediaKind.live,
    );
    await setup(tester, [live]);
    for (var i = 1; i <= 900; i++) {
      fake.positions[1] = Duration(seconds: i * 2);
      await tester.pump(const Duration(seconds: 2));
    }
    expect(fake.nextId, 1);
    expect(fake.playing, {1});
    await cleanUp(tester);
  });
}
