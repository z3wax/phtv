import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'store.dart';

/// Harakat (animatsiya) sozlamalari. Testlarda cheksiz animatsiyalar o‘chadi.
class TvMotion {
  static bool enabled = !Platform.environment.containsKey('FLUTTER_TEST');
}

/// Ekranlar orasidagi o‘tish: yengil kattalashish va paydo bo‘lish
/// (Apple TV’dagidek).
class TvPageTransitions extends PageTransitionsBuilder {
  const TvPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final out = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: inCurve,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(inCurve),
        child: AnimatedBuilder(
          animation: out,
          builder: (context, c) => Transform.scale(
            scale: 1 - 0.04 * out.value,
            child: Opacity(opacity: 1 - 0.5 * out.value, child: c),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bir marta: pastdan suzib, paydo bo‘lish ([delay] — navbat).
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 28,
  });
  final Widget child;
  final Duration delay;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final total = const Duration(milliseconds: 650) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// Fonda sekin suzuvchi rangli yorug‘liklar.
class DriftingGlows extends StatefulWidget {
  const DriftingGlows({super.key, required this.glows});

  /// (rang, o‘lcham, boshlang‘ich joy −1..1).
  final List<(Color, double, Alignment)> glows;

  @override
  State<DriftingGlows> createState() => _DriftingGlowsState();
}

class _DriftingGlowsState extends State<DriftingGlows>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    TvStore.instance.settings.addListener(_sync);
    _sync();
  }

  /// Sozlamalarda “Fon harakati” o‘chirilsa — yorug‘liklar to‘xtaydi.
  void _sync() {
    final on = TvMotion.enabled && TvStore.instance.settings.value.motionOn;
    if (on && !_c.isAnimating) {
      _c.repeat();
    } else if (!on && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    TvStore.instance.settings.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value * 2 * math.pi;
            return Stack(
              fit: StackFit.expand,
              children: [
                for (final (i, (color, size, at)) in widget.glows.indexed)
                  Align(
                    alignment: Alignment(
                      at.x + 0.18 * math.sin(t + i * 2.1),
                      at.y + 0.14 * math.cos(t * 0.8 + i * 1.3),
                    ),
                    child: Transform.scale(
                      scale: 1 + 0.08 * math.sin(t * 1.3 + i),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              color.withValues(alpha: 0.5),
                              color.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tizim yoqilganda — ilova ochilganda, televizor ulanganda, uyqudan
/// uyg‘onganda — televizordagidek “z3wax tv” yuklanish ekrani: ekran nur
/// chizig‘i bo‘lib yonadi, belgi paydo bo‘ladi, ustidan yorug‘lik o‘tadi,
/// pastda yuklanish chizig‘i to‘ladi va hammasi yumshoq yo‘qoladi.
class TvSplash extends StatefulWidget {
  const TvSplash({super.key});

  static final _replays = ValueNotifier<int>(0);

  /// Yuklanish ekranini qaytadan ko‘rsatish (masalan, uyqudan uyg‘onganda).
  static void replay() {
    if (TvMotion.enabled) _replays.value++;
  }

  @override
  State<TvSplash> createState() => _TvSplashState();
}

class _TvSplashState extends State<TvSplash>
    with SingleTickerProviderStateMixin {
  /// Shu nuqtadan boshlab ekran yo‘qola boshlaydi.
  static const _leaveAt = 0.86;

  late final AnimationController _c;
  bool _done = !TvMotion.enabled;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    TvSplash._replays.addListener(_replay);
    if (!_done) _run(0);
  }

  void _run(double from) {
    _c.forward(from: from).whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  void _replay() {
    if (!mounted) return;
    setState(() => _done = false);
    _run(0);
  }

  /// Bosilsa — kutmasdan yo‘qoladi.
  void _skip() {
    if (_c.isAnimating && _c.value < _leaveAt) _run(_leaveAt);
  }

  @override
  void dispose() {
    TvSplash._replays.removeListener(_replay);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          double seg(double a, double b, [Curve curve = Curves.linear]) =>
              curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
          // 1) Ekran yonadi: o‘rtada nur chizig‘i eniga yoyiladi, keyin
          //    butun ekranga ochilib, so‘nadi (kineskopli televizordagidek).
          final lineW = seg(0, 0.07, Curves.easeOutCubic);
          final lineH = seg(0.07, 0.15, Curves.easeInCubic);
          final lineAlpha = (1 - 0.9 * lineH) * (1 - seg(0.15, 0.3));
          final glow = seg(0.12, 0.4, Curves.easeOut);
          // 2) Belgi va yozuv navbat bilan paydo bo‘ladi.
          final logo = seg(0.16, 0.36, Curves.easeOutBack);
          final word = seg(0.22, 0.42, Curves.easeOutCubic);
          final tv = seg(0.28, 0.48, Curves.easeOutCubic);
          // 3) Yorug‘lik o‘tadi, yuklanish chizig‘i to‘ladi.
          final shine = seg(0.4, 0.78);
          final bar = seg(0.34, 0.44);
          final load = seg(0.36, 0.84, Curves.easeInOutCubic);
          // 4) Yengil kattalashib, yo‘qoladi.
          final leave = seg(_leaveAt, 1, Curves.easeInCubic);
          return IgnorePointer(
            ignoring: leave > 0.5,
            child: Opacity(
              opacity: 1 - leave,
              child: ColoredBox(
                color: Colors.black,
                child: DefaultTextStyle(
                  style: const TextStyle(decoration: TextDecoration.none),
                  child: LayoutBuilder(
                    builder: (context, box) => Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(
                          opacity: glow * (1 - leave),
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                radius: 0.85,
                                colors: [
                                  Color(0x3A3B6CFF),
                                  Color(0x0D3B6CFF),
                                  Color(0x00000000),
                                ],
                                stops: [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                        if (lineAlpha > 0.01)
                          Center(
                            child: Opacity(
                              opacity: lineAlpha,
                              child: Container(
                                width: box.maxWidth * lineW,
                                height: math.max(2, box.maxHeight * lineH),
                                // O‘rtasi yorug‘, chetlari xira — nur kabi.
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x55DCE6FF),
                                      Color(0xFFFFFFFF),
                                      Color(0x55DCE6FF),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xCC9DB8FF),
                                      blurRadius: 26,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Transform.scale(
                                scale: 1 + 0.06 * leave,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ShaderMask(
                                      blendMode: BlendMode.modulate,
                                      shaderCallback: (rect) => LinearGradient(
                                        colors: const [
                                          Color(0xFFC4C4CA),
                                          Color(0xFFFFFFFF),
                                          Color(0xFFC4C4CA),
                                        ],
                                        stops: [
                                          (shine * 1.5 - 0.5).clamp(0.0, 1.0),
                                          (shine * 1.5 - 0.25).clamp(0.0, 1.0),
                                          (shine * 1.5).clamp(0.0, 1.0),
                                        ],
                                      ).createShader(rect),
                                      child: _Wordmark(
                                        logo: logo,
                                        word: word,
                                        tv: tv,
                                      ),
                                    ),
                                    const SizedBox(height: 46),
                                    Opacity(
                                      opacity: bar,
                                      child: _LoadBar(value: load),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// “z3wax tv” belgisi; [logo], [word], [tv] — har bir qismning paydo
/// bo‘lishi (0..1).
class _Wordmark extends StatelessWidget {
  const _Wordmark({this.logo = 1, this.word = 1, this.tv = 1});
  final double logo;
  final double word;
  final double tv;

  @override
  Widget build(BuildContext context) {
    Widget slide(double v, Widget child) => Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(26 * (1 - v), 0), child: child),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Belgi: yumaloq kvadrat ichida “z”.
        Opacity(
          opacity: logo.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.6 + 0.4 * logo,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF5AC8FA).withValues(alpha: 0.35),
                    blurRadius: 30,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'z',
                style: TextStyle(
                  fontSize: 76,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 22),
        slide(
          word,
          const Text(
            'z3wax',
            style: TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w800,
              letterSpacing: -3,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 14),
        slide(
          tv,
          const Text(
            'tv',
            style: TextStyle(
              fontSize: 96,
              fontWeight: FontWeight.w300,
              letterSpacing: -2,
              color: Colors.white,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Belgi ostidagi ingichka yuklanish chizig‘i.
class _LoadBar extends StatelessWidget {
  const _LoadBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Color(0x885AC8FA), blurRadius: 10),
            ],
          ),
        ),
      ),
    );
  }
}
