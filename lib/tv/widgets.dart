import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'model.dart';

const uzMonths = [
  'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', //
  'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr',
];
const uzWeekdays = [
  'Dushanba',
  'Seshanba',
  'Chorshanba',
  'Payshanba',
  'Juma',
  'Shanba',
  'Yakshanba', //
];

String two(int n) => n.toString().padLeft(2, '0');
String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String formatDuration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Pult bilan tanlanadigan har qanday element. Tanlanganda kattalashadi,
/// ostida soya va oq hoshiya paydo bo‘ladi (Apple TV uslubi).
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.scale = 1.06,
    this.radius = 22,
    this.ring = true,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final double scale;
  final double radius;
  final bool ring;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: r,
              boxShadow: _focused && widget.ring
                  ? [
                      const BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 34,
                        offset: Offset(0, 18),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.85),
                        spreadRadius: 3,
                      ),
                    ]
                  : const [],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: widget.builder(context, _focused),
            ),
          ),
        ),
      ),
    );
  }
}

const _palettes = <List<Color>>[
  [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  [Color(0xFFFF512F), Color(0xFFDD2476)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFF0F2027), Color(0xFF2C5364)],
  [Color(0xFFDA4453), Color(0xFF89216B)],
  [Color(0xFF2193B0), Color(0xFF6DD5ED)],
  [Color(0xFFF7971E), Color(0xFFE94E1B)],
  [Color(0xFF654EA3), Color(0xFFEAAFC8)],
  [Color(0xFF000428), Color(0xFF004E92)],
  [Color(0xFFB24592), Color(0xFFF15F79)],
  [Color(0xFF134E5E), Color(0xFF71B280)],
  [Color(0xFF1A2980), Color(0xFF26D0CE)],
];

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

List<Color> paletteFor(String seed) =>
    _palettes[_hash(seed) % _palettes.length];

/// Rasmi yo‘q narsalar uchun chiroyli “muqova”: gradient, yorug‘lik dog‘lari
/// va harakat chiziqlari. Bir xil nom — har doim bir xil rasm.
class ArtPainter extends CustomPainter {
  ArtPainter(this.seed);
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final h = _hash(seed);
    final p = paletteFor(seed);
    final rect = Offset.zero & size;
    final angle = (h % 360) * math.pi / 180;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [p[0], p[1]],
          begin: Alignment(math.cos(angle), math.sin(angle)),
          end: Alignment(-math.cos(angle), -math.sin(angle)),
        ).createShader(rect),
    );
    final d = size.longestSide;
    for (var i = 0; i < 2; i++) {
      final cx = ((h >> (i * 5)) % 100) / 100 * size.width;
      final cy = ((h >> (i * 7 + 3)) % 100) / 100 * size.height;
      canvas.drawCircle(
        Offset(cx, cy),
        d * 0.55,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: i == 0 ? 0.28 : 0.16),
                  Colors.transparent,
                ],
              ).createShader(
                Rect.fromCircle(center: Offset(cx, cy), radius: d * 0.55),
              ),
      );
    }
    // Diagonal yorug‘lik chiziqlari.
    final streak = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.1 + ((h >> i) % 80) / 100);
      streak
        ..color = Colors.white.withValues(alpha: 0.04 + (i % 3) * 0.025)
        ..strokeWidth = size.height * (0.02 + (i % 2) * 0.03)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(-d * 0.1, y + d * 0.25),
        Offset(size.width * 1.1, y - d * 0.25),
        streak,
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x55000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(ArtPainter old) => old.seed != seed;
}

/// Media uchun rasm: kanal logotipi, telefondagi rasm yoki tarmoqdagi rasm.
ImageProvider? imageFor(MediaItem item, {int? width}) {
  ImageProvider? p;
  if (item.kind == MediaKind.image) {
    p = item.isFile ? FileImage(File(item.source)) : NetworkImage(item.source);
  } else if (item.logo != null && item.logo!.startsWith('http')) {
    p = NetworkImage(item.logo!);
  }
  if (p != null && width != null) {
    return ResizeImage(p, width: width, allowUpscaling: false);
  }
  return p;
}

IconData iconFor(MediaKind k) => switch (k) {
  MediaKind.live => Icons.live_tv_rounded,
  MediaKind.video => Icons.movie_rounded,
  MediaKind.audio => Icons.music_note_rounded,
  MediaKind.image => Icons.photo_rounded,
};

class ArtBox extends StatelessWidget {
  const ArtBox({
    super.key,
    required this.seed,
    this.icon,
    this.image,
    this.cover = false,
    this.iconSize = 44,
  });

  final String seed;
  final IconData? icon;
  final ImageProvider? image;

  /// true — rasm butun maydonni egallaydi (fotosuratlar), false — logotip.
  final bool cover;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = icon == null
        ? const SizedBox.shrink()
        : Center(
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: ArtPainter(seed)),
        if (image == null)
          fallback
        else if (cover)
          Image(
            image: image!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
            gaplessPlayback: true,
          )
        else
          Padding(
            padding: const EdgeInsets.all(18),
            child: Image(
              image: image!,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
      ],
    );
  }
}

/// Shishasimon panel (dok va pastki menyu).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(12),
    this.blur = true,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );
    if (!blur) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: box,
      ),
    );
  }
}

/// Soat va sana — har 5 soniyada yangilanadi.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder});
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  late Timer _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      final n = DateTime.now();
      if (n.minute != _now.minute) setState(() => _now = n);
    });
  }

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

/// Umumiy fon: to‘q qizil-ko‘k gradient (1-dizayn).
class TvBackdrop extends StatelessWidget {
  const TvBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5B1230),
            Color(0xFF2A1240),
            Color(0xFF0B2A4A),
            Color(0xFF071A33),
          ],
          stops: [0, 0.35, 0.7, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: -200,
            top: -160,
            child: _Glow(color: Color(0xFFB0203F), size: 620),
          ),
          const Positioned(
            right: -220,
            bottom: -260,
            child: _Glow(color: Color(0xFF145C8A), size: 720),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.55), Colors.transparent],
        ),
      ),
    ),
  );
}

/// Ixcham tugma (ikonka + yozuv).
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      radius: 18,
      scale: 1.05,
      builder: (context, f) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        color: f
            ? Colors.white
            : primary
            ? const Color(0xFF3B6CFF)
            : Colors.white.withValues(alpha: 0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: f ? Colors.black : Colors.white),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: f ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ekran sarlavhasi: orqaga tugmasi + nom + o‘ngda soat.
class TvHeader extends StatelessWidget {
  const TvHeader({super.key, required this.title, this.trailing = const []});
  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TvFocusable(
          onTap: () => Navigator.maybePop(context),
          radius: 30,
          builder: (context, f) => Container(
            width: 56,
            height: 56,
            color: f ? Colors.white : Colors.white.withValues(alpha: 0.12),
            child: Icon(
              Icons.arrow_back_rounded,
              color: f ? Colors.black : Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ...trailing.expand((w) => [w, const SizedBox(width: 14)]),
        Ticker(
          builder: (_, now) => Text(
            hhmm(now),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
          ),
        ),
      ],
    );
  }
}
