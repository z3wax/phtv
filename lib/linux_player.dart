// Ubuntu / Linux uchun video pleyer: video_player API si, ichida mpv
// (media_kit). Asosi — video_player_media_kit (MIT, © 2023 Abdelaziz Mahdy;
// media_kit © Hitesh Kumar Saini), Telefon TV uchun o‘zgartirilgan:
//
// * Ovoz qurilmasi ochilmasa (HDMI ovozi sozlanmagan, quloqchin yo‘q) video
//   to‘xtamaydi — ovozsiz davom etadi.
// * Jonli IPTV oqimlarida davomiylik noma’lum (0) — kanal baribir ochiladi.
// * mpv ning zararsiz xato yozuvlari (apparat dekoderi, ovoz…) pleyerni
//   o‘chirmaydi; xato faqat fayl / kanal umuman ochilmasa ko‘rsatiladi.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// ignore_for_file: close_sinks

class TvLinuxPlayer extends VideoPlayerPlatform {
  final _players = HashMap<int, Player>();
  final _ready = HashMap<int, Completer<void>>();
  final _views = HashMap<int, VideoController>();
  final _events = HashMap<int, StreamController<VideoEvent>>();
  final _subs = HashMap<int, List<StreamSubscription<Object?>>>();

  static void register() {
    MediaKit.ensureInitialized();
    VideoPlayerPlatform.instance = TvLinuxPlayer();
  }

  /// mpv xato yozuvlarining ko‘pi zararsiz (apparat dekoderi, ovoz
  /// qurilmasi…): mpv o‘zi boshqa yo‘lga o‘tadi. Faqat fayl / kanal umuman
  /// ochilmasligini bildiradigan xabarlar ko‘rsatiladi; qolgan holatda
  /// pleyer ekranidagi kutish chegarasi ishlaydi.
  static bool isFatal(String message) {
    final m = message.toLowerCase();
    // Apparat dekoderi, ovoz qurilmasi — mpv o‘zi boshqa yo‘lga o‘tadi.
    const harmless = [
      'vdpau',
      'vaapi',
      'hwdec',
      'cuda',
      'codec',
      'audio',
      'ao/',
    ];
    if (harmless.any(m.contains)) return false;
    const fatal = [
      'failed to open', 'failed to recognize file format', 'no such file', //
      'loading failed', 'http error', '404', '403', 'connection refused',
      'no video or audio streams',
      'unrecognized file format',
      'permission denied',
    ];
    return fatal.any(m.contains);
  }

  @override
  Future<void> init() async {
    for (final id in _players.keys.toList()) {
      await dispose(id);
    }
  }

  @override
  Future<void> dispose(int playerId) async {
    for (final s
        in _subs.remove(playerId) ?? const <StreamSubscription<Object?>>[]) {
      await s.cancel();
    }
    await _players.remove(playerId)?.dispose();
    await _events.remove(playerId)?.close();
    _views.remove(playerId);
    _ready.remove(playerId);
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final player = Player();
    final id = player.hashCode;
    _players[id] = player;
    _ready[id] = Completer<void>();
    _views[id] = VideoController(player);
    _events[id] = StreamController<VideoEvent>();
    _subs[id] = [];

    final native = player.platform;
    if (native is NativePlayer) {
      // Ovoz qurilmasi bo‘lmasa — ovozsiz davom etish; tarmoq uzilishini kutish.
      await native.setProperty('audio-fallback-to-null', 'yes');
      await native.setProperty('network-timeout', '20');
      // Sifat va barqarorlik: HLS’da eng yuqori sifat, katta bufer,
      // uzilganda qayta ulanish.
      await native.setProperty('hls-bitrate', 'max');
      await native.setProperty('cache', 'yes');
      await native.setProperty('cache-secs', '30');
      await native.setProperty('demuxer-max-bytes', '200MiB');
      await native.setProperty('demuxer-readahead-secs', '20');
      await native.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
      );
    }
    _listen(id);

    final String resource;
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        final asset = dataSource.package == null
            ? dataSource.asset
            : 'packages/${dataSource.package}/${dataSource.asset}';
        resource = 'asset:///$asset';
      case DataSourceType.network:
      case DataSourceType.file:
      case DataSourceType.contentUri:
        final uri = dataSource.uri;
        if (uri == null) throw ArgumentError('uri must not be null');
        resource = uri;
    }
    await player.open(
      Media(resource, httpHeaders: dataSource.httpHeaders),
      play: false,
    );
    return id;
  }

  void _listen(int id) {
    final player = _players[id]!;
    final ready = _ready[id]!;
    final events = _events[id]!;
    final subs = _subs[id]!;

    var width = -1, height = -1;
    var gotTracks = false;
    var waitedForDuration = false;
    Timer? durationWait;

    void markReady() {
      if (ready.isCompleted) return;
      final hasPicture = width > 0 && height > 0;
      final audioOnly = gotTracks && width == 0 && height == 0;
      if (!hasPicture && !audioOnly) return;
      // Faylda davomiylik odatda darhol ma’lum bo‘ladi — 1,5 soniya kutamiz;
      // jonli efirda u 0 bo‘lib qoladi, shunda kutmasdan ochamiz.
      if (player.state.duration <= Duration.zero && !waitedForDuration) {
        durationWait ??= Timer(const Duration(milliseconds: 1500), () {
          waitedForDuration = true;
          markReady();
        });
        return;
      }
      durationWait?.cancel();
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          size: Size(width.toDouble(), height.toDouble()),
          duration: player.state.duration,
        ),
      );
      ready.complete();
    }

    void afterReady(VideoEvent Function() make) async {
      await ready.future;
      if (!events.isClosed) events.add(make());
    }

    subs
      ..add(
        player.stream.videoParams.listen((p) {
          width = p.dw ?? 0;
          height = p.dh ?? 0;
          markReady();
        }),
      )
      ..add(
        player.stream.tracks.listen((t) {
          // Faqat ovoz (musiqa): mpv ro‘yxatida “auto” va “no” dan boshqa
          // video yo‘lak yo‘q.
          if (t.video.length <= 2 && t.audio.length > 2) {
            gotTracks = true;
            width = 0;
            height = 0;
            markReady();
          }
        }),
      )
      ..add(
        player.stream.duration.listen((d) {
          if (d > Duration.zero) markReady();
        }),
      )
      ..add(
        player.stream.playing.listen(
          (p) => afterReady(
            () => VideoEvent(
              eventType: VideoEventType.isPlayingStateUpdate,
              isPlaying: p,
            ),
          ),
        ),
      )
      ..add(
        player.stream.completed.listen((done) {
          if (done) {
            afterReady(() => VideoEvent(eventType: VideoEventType.completed));
          }
        }),
      )
      ..add(
        player.stream.buffering.listen(
          (b) => afterReady(
            () => VideoEvent(
              eventType: b
                  ? VideoEventType.bufferingStart
                  : VideoEventType.bufferingEnd,
            ),
          ),
        ),
      )
      ..add(
        player.stream.buffer.listen(
          (b) => afterReady(
            () => VideoEvent(
              eventType: VideoEventType.bufferingUpdate,
              buffered: [DurationRange(Duration.zero, b)],
            ),
          ),
        ),
      )
      ..add(
        player.stream.error.listen((message) {
          debugPrint('mpv: $message');
          // Ochilgandan keyingi mpv xabarlari ijroni to‘xtatmaydi.
          if (ready.isCompleted || !isFatal(message) || events.isClosed) {
            return;
          }
          events.addError(PlatformException(code: 'mpv', message: message));
        }),
      );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final c = _events[playerId];
    if (c == null) throw StateError('Pleyer $playerId topilmadi');
    return c.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      _players[playerId]?.setPlaylistMode(
        looping ? PlaylistMode.single : PlaylistMode.none,
      );

  @override
  Future<void> play(int playerId) async => _players[playerId]?.play();

  @override
  Future<void> pause(int playerId) async => _players[playerId]?.pause();

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      _players[playerId]?.setVolume(volume * 100);

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _players[playerId]?.seek(position);

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async =>
      _players[playerId]?.setRate(speed);

  @override
  Future<Duration> getPosition(int playerId) async =>
      _players[playerId]?.state.position ?? Duration.zero;

  @override
  Widget buildView(int playerId) {
    final c = _views[playerId];
    if (c == null) throw StateError('Pleyer $playerId topilmadi');
    return Video(
      key: ValueKey(c),
      controller: c,
      wakelock: false,
      controls: NoVideoControls,
      fill: const Color(0x00000000),
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setWebOptions(
    int playerId,
    VideoPlayerWebOptions options,
  ) async {}
}
