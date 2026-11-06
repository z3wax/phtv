import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    if (TvMotion.enabled) _c.repeat();
  }

  @override
  void dispose() {
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

/// Ilova ochilganda: “z3wax tv” — Apple TV’ning ochilishiga o‘xshab,
/// qora fonda paydo bo‘ladi, ustidan yorug‘lik o‘tadi va yo‘qoladi.
class TvSplash extends StatefulWidget {
  const TvSplash({super.key});

  @override
  State<TvSplash> createState() => _TvSplashState();
}

class _TvSplashState extends State<TvSplash>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  bool _done = !TvMotion.enabled;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // 0–0.25: paydo bo‘lish (xiradan aniqqa), 0.25–0.7: yorug‘lik o‘tadi,
        // 0.78–1: hammasi yengil kattalashib, yo‘qoladi.
        final appear = Curves.easeOutCubic.transform((t / 0.25).clamp(0, 1));
        final shine = ((t - 0.22) / 0.5).clamp(0.0, 1.0);
        final leave = Curves.easeInCubic.transform(
          ((t - 0.78) / 0.22).clamp(0, 1),
        );
        return IgnorePointer(
          ignoring: leave > 0.6,
          child: Opacity(
            opacity: 1 - leave,
            child: ColoredBox(
              color: Colors.black,
              child: Center(
                child: Transform.scale(
                  scale: (0.9 + 0.1 * appear) * (1 + 0.08 * leave),
                  child: DefaultTextStyle(
                    style: const TextStyle(decoration: TextDecoration.none),
                    child: Opacity(
                      opacity: appear,
                      child: ShaderMask(
                        blendMode: BlendMode.modulate,
                        shaderCallback: (rect) => LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: const [
                            Color(0xFFBDBDC2),
                            Color(0xFFFFFFFF),
                            Color(0xFFBDBDC2),
                          ],
                          stops: [
                            (shine - 0.25).clamp(0.0, 1.0),
                            shine,
                            (shine + 0.25).clamp(0.0, 1.0),
                          ],
                        ).createShader(rect),
                        child: const _Wordmark(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Belgi: yumaloq kvadrat ichida “z”.
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
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
        const SizedBox(width: 22),
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
        const SizedBox(width: 14),
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
      ],
    );
  }
}
