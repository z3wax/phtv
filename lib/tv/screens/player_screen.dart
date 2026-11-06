import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../input.dart';
import '../model.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';

/// Video, jonli kanal, musiqa va rasmlar uchun to‘liq ekranli pleyer.
///
/// Pult: OK — panel / pauza, ←→ — 10 soniya (kanalda — oldingi/keyingi),
/// ↑↓ — kanal almashtirish, ⏮⏭ — oldingi/keyingi, Orqaga — chiqish.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.items, required this.index});
  final List<MediaItem> items;
  final int index;

  static Route<void> route(List<MediaItem> items, int index) =>
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => PlayerScreen(items: items, index: index),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      );

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late int _i = widget.index;
  VideoPlayerController? _c;
  String? _error;
  bool _overlay = true;
  bool _slideshow = false;
  double _volume = 1;
  Timer? _hide, _save, _slide;
  final _playFocus = FocusNode(debugLabel: 'play');

  MediaItem get _item => widget.items[_i];

  /// Jonli kanal: hozirgi manba (asosiy yoki zaxira) va urinilganlar.
  int _alt = 0;
  DateTime? _bufferingSince;

  String _sourceFor(MediaItem item) {
    if (!item.isLive || _alt == 0) return item.source;
    final alts = TvStore.instance.alternatesFor(item.source);
    return _alt <= alts.length ? alts[_alt - 1] : item.source;
  }

  /// Manba ishlamadi yoki qotib qoldi — shu kanalning keyingi manbasi.
  bool _tryNextSource() {
    final item = _item;
    if (!item.isLive) return false;
    final alts = TvStore.instance.alternatesFor(item.source);
    if (_alt >= alts.length) return false;
    _alt++;
    TvServices.instance.showToast(
      'Boshqa manba: ${_alt + 1} / ${alts.length + 1}',
    );
    _open(keepSource: true);
    return true;
  }

  @override
  void initState() {
    super.initState();
    TvInput.instance.push(_onCmd);
    _save = Timer.periodic(const Duration(seconds: 5), (_) => _remember());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open();
      _playFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    TvInput.instance.remove(_onCmd);
    _remember();
    _hide?.cancel();
    _save?.cancel();
    _slide?.cancel();
    _c?.dispose();
    _playFocus.dispose();
    TvServices.instance.updateState({'title': null, 'kind': null});
    super.dispose();
  }

  void _remember() {
    final c = _c;
    if (c != null && c.value.isInitialized && !_item.isLive) {
      _item.positionMs = c.value.position.inMilliseconds;
      _item.durationMs = c.value.duration.inMilliseconds;
    }
    TvStore.instance.remember(_item);
  }

  Future<void> _open({bool keepSource = false}) async {
    if (!keepSource) _alt = 0;
    _bufferingSince = null;
    final old = _c;
    _c = null;
    _slide?.cancel();
    setState(() => _error = null);
    await old?.dispose();
    final item = _item;
    TvStore.instance.remember(item);
    TvServices.instance.updateState({
      'title': item.title,
      'kind': item.kind.name,
    });
    _showOverlay();
    if (item.kind == MediaKind.image) {
      if (_slideshow) {
        _slide = Timer(const Duration(seconds: 6), () => _step(1));
      }
      return;
    }
    final source = _sourceFor(item);
    final c = item.isFile
        ? VideoPlayerController.file(File(source))
        : VideoPlayerController.networkUrl(
            Uri.parse(source),
            formatHint: source.contains('.m3u8') ? VideoFormat.hls : null,
            httpHeaders: const {'User-Agent': 'TelefonTV/1.0'},
          );
    setState(() => _c = c);
    try {
      await c.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || _c != c) return;
      if (!item.isLive && item.positionMs > 5000 && item.progress < 0.95) {
        await c.seekTo(Duration(milliseconds: item.positionMs));
      }
      await c.setVolume(_volume);
      await c.play();
      c.addListener(() => _onTick(c));
      setState(() {});
    } catch (_) {
      if (!mounted || _c != c) return;
      if (_tryNextSource()) return;
      setState(
        () => _error = item.isLive
            ? 'Kanal hozir efirda emas yoki manzil ishlamayapti'
            : 'Bu faylni ochib bo‘lmadi',
      );
    }
  }

  bool _ended = false;
  void _onTick(VideoPlayerController c) {
    final v = c.value;
    // Jonli kanal 15 soniyadan ko‘p qotib qolsa — zaxira manbaga o‘tamiz.
    if (_item.isLive && v.isBuffering) {
      _bufferingSince ??= DateTime.now();
      if (DateTime.now().difference(_bufferingSince!).inSeconds > 15 &&
          _c == c) {
        _bufferingSince = null;
        if (_tryNextSource()) return;
      }
    } else {
      _bufferingSince = null;
    }
    if (v.hasError && _error == null && mounted && _c == c) {
      if (_tryNextSource()) return;
      setState(
        () =>
            _error = 'Ijro to‘xtadi: ${v.errorDescription ?? 'tarmoq xatosi'}',
      );
    }
    final done =
        v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying;
    if (done && !_ended) {
      _ended = true;
      _item.positionMs = 0;
      if (widget.items.length > 1 && _i < widget.items.length - 1) _step(1);
    } else if (!done) {
      _ended = false;
    }
  }

  void _step(int d) {
    if (widget.items.length < 2) return;
    _remember();
    _i = (_i + d) % widget.items.length;
    if (_i < 0) _i += widget.items.length;
    _open();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    c.value.isPlaying ? c.pause() : c.play();
    _showOverlay();
    setState(() {});
  }

  void _seek(int seconds) {
    final c = _c;
    if (c == null || !c.value.isInitialized || _item.isLive) return;
    final to = c.value.position + Duration(seconds: seconds);
    c.seekTo(
      to < Duration.zero
          ? Duration.zero
          : (to > c.value.duration ? c.value.duration : to),
    );
  }

  void _setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    _c?.setVolume(_volume);
    TvServices.instance.showToast('Ovoz: ${(_volume * 100).round()}%');
  }

  void _showOverlay() {
    if (!mounted) return;
    if (!_overlay) setState(() => _overlay = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          (_c?.value.isPlaying ?? _item.kind == MediaKind.image) &&
          _error == null) {
        setState(() => _overlay = false);
      }
    });
  }

  bool _onCmd(Cmd cmd) {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return false;
    final wasVisible = _overlay;
    _showOverlay();
    switch (cmd) {
      case Cmd.playPause:
        _toggle();
        return true;
      case Cmd.next:
        _step(1);
        return true;
      case Cmd.prev:
        _step(-1);
        return true;
      case Cmd.volUp:
        _setVolume(_volume + 0.1);
        return true;
      case Cmd.volDown:
        _setVolume(_volume - 0.1);
        return true;
      case Cmd.mute:
        _setVolume(_volume > 0 ? 0 : 1);
        return true;
      case Cmd.ok:
        if (!wasVisible) {
          _playFocus.requestFocus();
          return true;
        }
        return false; // tanlangan tugma bosiladi
      case Cmd.left || Cmd.right:
        if (wasVisible) return false; // panel tugmalari orasida yurish
        final d = cmd == Cmd.right ? 1 : -1;
        if (_item.isLive || _item.kind == MediaKind.image) {
          _step(d);
        } else {
          _seek(10 * d);
        }
        return true;
      case Cmd.up || Cmd.down:
        if (_item.isLive && widget.items.length > 1) {
          _step(cmd == Cmd.up ? -1 : 1);
          return true;
        }
        return wasVisible ? false : true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final c = _c;
    final fav = TvStore.instance.isFavorite(item.source);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            _overlay ? setState(() => _overlay = false) : _showOverlay(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.kind == MediaKind.image)
              Image(
                image: imageFor(item)!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Rasmni ochib bo‘lmadi')),
              )
            else if (item.kind == MediaKind.audio)
              _MusicArt(item: item)
            else if (c != null && c.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
              ),
            if (item.kind != MediaKind.image &&
                _error == null &&
                (c == null || !c.value.isInitialized))
              const Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(strokeWidth: 4),
                ),
              ),
            if (_error != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.signal_wifi_bad_rounded,
                      size: 72,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ],
                ),
              ),
            IgnorePointer(
              ignoring: !_overlay,
              child: AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: _Overlay(
                  item: item,
                  controller: c,
                  index: _i,
                  count: widget.items.length,
                  favorite: fav,
                  slideshow: _slideshow,
                  playFocus: _playFocus,
                  onPlay: () => _error != null ? _open() : _toggle(),
                  onPrev: () => _step(-1),
                  onNext: () => _step(1),
                  onFavorite: () =>
                      setState(() => TvStore.instance.toggleFavorite(item)),
                  onSlideshow: () {
                    setState(() => _slideshow = !_slideshow);
                    _slide?.cancel();
                    if (_slideshow) {
                      _slide = Timer(
                        const Duration(seconds: 6),
                        () => _step(1),
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MusicArt extends StatelessWidget {
  const _MusicArt({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: ArtPainter('music-${item.title}')),
        Container(color: Colors.black38),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 40,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: ArtBox(
                  seed: item.title,
                  icon: Icons.music_note_rounded,
                  iconSize: 110,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Musiqa',
                style: TextStyle(fontSize: 20, color: Color(0xFFFF6FA5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.item,
    required this.controller,
    required this.index,
    required this.count,
    required this.favorite,
    required this.slideshow,
    required this.playFocus,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
    required this.onFavorite,
    required this.onSlideshow,
  });

  final MediaItem item;
  final VideoPlayerController? controller;
  final int index, count;
  final bool favorite, slideshow;
  final FocusNode playFocus;
  final VoidCallback onPlay, onPrev, onNext, onFavorite, onSlideshow;

  Widget _round(
    IconData icon,
    VoidCallback onTap, {
    FocusNode? node,
    double size = 64,
  }) => TvFocusable(
    onTap: onTap,
    focusNode: node,
    radius: size / 2,
    scale: 1.12,
    builder: (context, f) => Container(
      width: size,
      height: size,
      color: f ? Colors.white : Colors.white.withValues(alpha: 0.16),
      child: Icon(
        icon,
        size: size * 0.5,
        color: f ? Colors.black : Colors.white,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC000000),
                Colors.transparent,
                Colors.transparent,
                Color(0xEE000000),
              ],
              stops: [0, 0.25, 0.6, 1],
            ),
          ),
        ),
        Positioned(
          left: 56,
          right: 56,
          top: 34,
          child: Row(
            children: [
              if (item.isLive)
                Container(
                  margin: const EdgeInsets.only(right: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'JONLI',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count > 1)
                Text(
                  '${index + 1} / $count',
                  style: const TextStyle(fontSize: 20, color: Colors.white70),
                ),
              const SizedBox(width: 20),
              Ticker(
                builder: (_, now) =>
                    Text(hhmm(now), style: const TextStyle(fontSize: 24)),
              ),
            ],
          ),
        ),
        Positioned(
          left: 56,
          right: 56,
          bottom: 30,
          child: Column(
            children: [
              if (c != null && !item.isLive)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (context, v, _) {
                    final total = v.duration.inMilliseconds;
                    final p = total > 0
                        ? v.position.inMilliseconds / total
                        : 0.0;
                    return Row(
                      children: [
                        Text(
                          formatDuration(v.position),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: p.clamp(0.0, 1.0),
                              minHeight: 7,
                              backgroundColor: Colors.white24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          formatDuration(v.duration),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (count > 1) ...[
                    _round(Icons.skip_previous_rounded, onPrev),
                    const SizedBox(width: 24),
                  ],
                  if (c != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (context, v, _) => _round(
                        v.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPlay,
                        node: playFocus,
                        size: 78,
                      ),
                    )
                  else
                    _round(
                      item.kind == MediaKind.image
                          ? (slideshow
                                ? Icons.pause_rounded
                                : Icons.slideshow_rounded)
                          : Icons.refresh_rounded,
                      item.kind == MediaKind.image ? onSlideshow : onPlay,
                      node: playFocus,
                      size: 78,
                    ),
                  if (count > 1) ...[
                    const SizedBox(width: 24),
                    _round(Icons.skip_next_rounded, onNext),
                  ],
                  if (item.isLive) ...[
                    const SizedBox(width: 40),
                    _round(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      onFavorite,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
