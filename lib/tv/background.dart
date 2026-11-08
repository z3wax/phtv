import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'wallpapers.dart';

ImageProvider scenicImage(int index) => ResizeImage(
  NetworkImage(scenicImages[index % scenicImages.length]),
  width: 1000,
);

/// Large media cards use landscape photographs; small action buttons keep icons.
class ScenicArt extends StatelessWidget {
  const ScenicArt({super.key, this.index = 0});
  final int index;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xff151719)),
      Image(
        image: scenicImage(index),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x10000000), Color(0x88000000)],
          ),
        ),
      ),
    ],
  );
}

class WallpaperBackground extends StatefulWidget {
  const WallpaperBackground({super.key, this.blur = 0.5, this.seconds = 60});
  final double blur;
  final int seconds;
  @override
  State<WallpaperBackground> createState() => _WallpaperBackgroundState();
}

class _WallpaperBackgroundState extends State<WallpaperBackground>
    with WidgetsBindingObserver {
  Timer? _timer;
  ImageProvider? _image;
  bool _busy = false, _foreground = true;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (WallpaperRepository.enabled) {
      _load();
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: widget.seconds.clamp(30, 600)), (
      _,
    ) {
      if (_foreground &&
          mounted &&
          TickerMode.of(context) &&
          (ModalRoute.isCurrentOf(context) ?? true)) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(WallpaperBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seconds != oldWidget.seconds && WallpaperRepository.enabled) {
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    try {
      final file = await WallpaperRepository.instance.next();
      if (file == null || !mounted) return;
      final provider = ResizeImage(FileImage(File(file.path)), width: 1920);
      await provider.evict();
      if (!mounted) return;
      var failed = false;
      await precacheImage(
        provider,
        context,
        onError: (_, _) {
          failed = true;
        },
      );
      if (!mounted || failed) return;
      final old = _image;
      setState(() {
        _image = provider;
        _revision++;
      });
      if (old != null && old != provider) unawaited(old.evict());
    } catch (_) {
      /* Keep the previous image or black background. */
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final image = _image;
    if (image != null) unawaited(image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: widget.blur * 20,
                  sigmaY: widget.blur * 20,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 900),
                  child: _image == null
                      ? const ColoredBox(color: Colors.black)
                      : Image(
                          key: ValueKey(_revision),
                          image: _image!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: Colors.black),
                        ),
                ),
              ),
            ),
          ),
          const ColoredBox(color: Color(0x80000000)),
          if (_image != null)
            const Positioned(
              right: 16,
              bottom: 8,
              child: Text(
                'Yandex Background Gallery',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ],
      ),
    ),
  );
}
