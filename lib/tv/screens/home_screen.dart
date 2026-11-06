import 'dart:io';

import 'package:flutter/material.dart';

import '../../platform.dart';

import '../input.dart';
import '../model.dart';
import '../services.dart';
import '../store.dart';
import '../weather.dart';
import '../widgets.dart';
import 'apps_screen.dart';
import 'files_screen.dart';
import 'live_screen.dart';
import 'pair_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'sleep_screen.dart';

/// Bosh ekran: 1-sahifa — vidjetlar va dok, 2-sahifa — media markazi.
/// Pultda pastga/tepaga bosib sahifalar almashadi.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _page = 0;
  final _firstFocus = [
    FocusNode(debugLabel: 'page0'),
    FocusNode(debugLabel: 'page1'),
  ];

  @override
  void initState() {
    super.initState();
    TvInput.instance.push(_onCmd);
  }

  @override
  void dispose() {
    TvInput.instance.remove(_onCmd);
    for (final n in _firstFocus) {
      n.dispose();
    }
    super.dispose();
  }

  bool _onCmd(Cmd cmd) {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return false;
    switch (cmd) {
      case Cmd.down || Cmd.up:
        final down = cmd == Cmd.down;
        if (!TvInput.instance.moveFocus(
          down ? TraversalDirection.down : TraversalDirection.up,
        )) {
          if (down && _page == 0) _goPage(1);
          if (!down && _page == 1) _goPage(0);
        }
        return true;
      case Cmd.back || Cmd.home:
        if (_page == 1) _goPage(0);
        return true; // bosh ekrandan chiqib ketmaymiz
      default:
        return false;
    }
  }

  void _goPage(int p) {
    if (p == _page) return;
    setState(() => _page = p);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstFocus[p].requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Android TV pultidagi “Orqaga” — 2-sahifadan 1-sahifaga.
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goPage(0);
      },
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Telefon ekranida barmoq bilan tepaga/pastga surish.
        onVerticalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) _goPage(1);
          if (v > 300) _goPage(0);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey(_page);
                final dir = _page == 1 ? 1.0 : -1.0;
                final offset = Tween(
                  begin: Offset(0, incoming ? 0.25 * dir : -0.25 * dir),
                  end: Offset.zero,
                ).animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(_page),
                child: _page == 0
                    ? _WidgetsPage(firstFocus: _firstFocus[0])
                    : _MediaPage(
                        firstFocus: _firstFocus[1],
                        onHome: () => _goPage(0),
                      ),
              ),
            ),
            Positioned(
              left: 44,
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 2; i++)
                      GestureDetector(
                        onTap: () => _goPage(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          width: 9,
                          height: i == _page ? 26 : 9,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(
                              alpha: i == _page ? 0.95 : 0.35,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Amallar ---------------- */

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

void openLive(BuildContext context, {bool favorites = false}) =>
    _push(context, LiveScreen(favoritesOnly: favorites));

void openFiles(BuildContext context, [MediaKind? filter]) =>
    _push(context, FilesScreen(filter: filter));

void playItem(BuildContext context, MediaItem item) {
  if (item.isLive) {
    final list = TvStore.instance.channels.value;
    final i = list.indexWhere((c) => c.source == item.source);
    if (i >= 0) {
      Navigator.of(context).push(PlayerScreen.route(list, i));
      return;
    }
  }
  Navigator.of(context).push(PlayerScreen.route([item], 0));
}

class _App {
  const _App(this.name, this.icon, this.colors, this.open);
  final String name;
  final IconData icon;
  final List<Color> colors;
  final void Function(BuildContext) open;
}

final _apps = <_App>[
  _App('Jonli TV', Icons.live_tv_rounded, const [
    Color(0xFFFF3B5C),
    Color(0xFFB0102E),
  ], openLive),
  _App(
    'YouTube',
    Icons.smart_display_rounded,
    const [Color(0xFFFF2D2D), Color(0xFFB80000)],
    (_) => TvServices.instance.openApp('https://www.youtube.com/', 'YouTube'),
  ),
  _App('Filmlar', Icons.movie_rounded, const [
    Color(0xFF2B2B2B),
    Color(0xFF0E0E0E),
  ], (c) => openFiles(c, MediaKind.video)),
  _App('Rasmlar', Icons.photo_library_rounded, const [
    Color(0xFFFFB800),
    Color(0xFFFF5E62),
  ], (c) => openFiles(c, MediaKind.image)),
  _App('Musiqa', Icons.music_note_rounded, const [
    Color(0xFFFC5C7D),
    Color(0xFF6A3093),
  ], (c) => openFiles(c, MediaKind.audio)),
  _App(
    'Brauzer',
    Icons.public_rounded,
    const [Color(0xFF00C6FF), Color(0xFF0072FF)],
    (_) => TvServices.instance.openApp('https://www.google.com/', 'Brauzer'),
  ),
  // TV qutisi / stik va Android telefondagi barcha ilovalar.
  if (Platform.isAndroid)
    _App('Ilovalar', Icons.apps_rounded, const [
      Color(0xFF6366F1),
      Color(0xFF312E81),
    ], (c) => _push(c, const AppsScreen())),
  // Fleshkaga yozish — telefon uchun (kompyuterda kerak emas).
  if (!isDesktop)
    _App('USB', Icons.usb_rounded, const [
      Color(0xFF34D399),
      Color(0xFF047857),
    ], (_) => TvServices.instance.showUsb()),
  _App('Pult', Icons.settings_remote_rounded, const [
    Color(0xFF8E8E93),
    Color(0xFF48484A),
  ], (c) => _push(c, const PairScreen())),
  _App('Sozlamalar', Icons.settings_rounded, const [
    Color(0xFF6B7280),
    Color(0xFF374151),
  ], (c) => _push(c, const SettingsScreen())),
];

/* ---------------- 1-sahifa: vidjetlar ---------------- */

class _WidgetsPage extends StatelessWidget {
  const _WidgetsPage({required this.firstFocus});
  final FocusNode firstFocus;

  @override
  Widget build(BuildContext context) {
    return TvBackdrop(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(110, 52, 90, 26),
        child: Column(
          children: [
            const _TopBar(),
            const Spacer(),
            SizedBox(
              height: 330,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    width: 300,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _RecentCard()),
                        SizedBox(height: 22),
                        Expanded(child: _WeatherCard()),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(child: _HeroCard(focusNode: firstFocus)),
                  const SizedBox(width: 28),
                  const SizedBox(
                    width: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ContinueCard()),
                        SizedBox(height: 22),
                        Expanded(child: _RemoteCard()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const _Dock(),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    const big = TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w300,
      height: 1.15,
    );
    return Ticker(
      builder: (context, now) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${now.day} ${uzMonths[now.month - 1]}', style: big),
              Text(uzWeekdays[now.weekday - 1], style: big),
            ],
          ),
          const Spacer(),
          ValueListenableBuilder<int>(
            valueListenable: TvServices.instance.remotes,
            builder: (context, n, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  n == 0 ? 'Telefoningiz — pult' : '$n ta pult ulangan',
                  style: TextStyle(
                    fontSize: 17,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hhmm(now),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFFF2D95),
                  Color(0xFF7B5CFF),
                  Color(0xFF00D1FF),
                  Color(0xFF2EF2B5),
                  Color(0xFFFF2D95),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7B5CFF).withValues(alpha: 0.6),
                  blurRadius: 24,
                ),
              ],
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: const Icon(
              Icons.settings_remote_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

/// Oq vidjet: oxirgi ko‘rilgan.
class _RecentCard extends StatelessWidget {
  const _RecentCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MediaItem>>(
      valueListenable: TvStore.instance.history,
      builder: (context, history, _) {
        final item = history.firstOrNull;
        return TvFocusable(
          onTap: () =>
              item == null ? openLive(context) : playItem(context, item),
          builder: (context, f) => Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ArtBox(
                      seed: item?.title ?? 'Telefon TV',
                      icon: item == null
                          ? Icons.play_arrow_rounded
                          : iconFor(item.kind),
                      image: item == null ? null : imageFor(item, width: 240),
                      cover: item?.kind == MediaKind.image,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Icon(
                          item == null
                              ? Icons.history_rounded
                              : iconFor(item.kind),
                          color: const Color(0xFFFF2D78),
                          size: 22,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'OXIRGI KO‘RILGAN',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item?.title ?? 'Hali hech narsa',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        item?.kindLabel ?? 'Jonli TV’dan boshlang',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFFF2D78),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Ko‘k vidjet: ob-havo (Open-Meteo).
class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: () => _push(context, const SettingsScreen()),
      builder: (context, f) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3AA3E8), Color(0xFF1E6FC0)],
          ),
        ),
        child: ValueListenableBuilder<Weather?>(
          valueListenable: WeatherService.instance.weather,
          builder: (context, w, _) {
            if (w == null) {
              final city =
                  cities[TvStore.instance.settings.value.city.clamp(
                        0,
                        cities.length - 1,
                      )]
                      .name;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Row(
                    children: [
                      Icon(Icons.cloud_sync_rounded, size: 34),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ob-havo yuklanmoqda…',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.city,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${w.temp.round()}°',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w300,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(
                          weatherIcon(w.code),
                          color: const Color(0xFFFFD54F),
                          size: 24,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          weatherText(w.code),
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'Y:${w.max.round()}° P:${w.min.round()}°',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final h in w.hours)
                      Column(
                        children: [
                          Text(
                            two(h.hour),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Icon(
                            weatherIcon(h.code),
                            size: 16,
                            color: const Color(0xFFFFD54F),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${h.temp.round()}°',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Markaziy katta karta: tavsiya etilgan kanal yoki “Jonli TV”.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.focusNode});
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final store = TvStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        store.channels,
        store.favorites,
        store.history,
      ]),
      builder: (context, _) {
        final channels = store.channels.value;
        final lastLive = store.history.value.where((e) => e.isLive).firstOrNull;
        final featured =
            lastLive ??
            store.favorites.value.firstOrNull ??
            channels.firstOrNull;
        final title = featured?.title ?? 'Jonli TV';
        final subtitle = featured == null
            ? 'O‘zbekiston kanallarini bir bosishda qo‘shing'
            : '${featured.group.isEmpty ? 'Jonli efir' : featured.group} · ${channels.length} ta kanal';
        final logo = featured == null ? null : imageFor(featured, width: 500);
        return TvFocusable(
          focusNode: focusNode,
          autofocus: true,
          scale: 1.04,
          radius: 24,
          onTap: () => featured == null
              ? openLive(context)
              : playItem(context, featured),
          builder: (context, f) => Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: ArtPainter('hero-$title')),
              if (logo != null)
                Positioned(
                  right: 30,
                  top: 30,
                  bottom: 80,
                  width: 240,
                  child: Image(
                    image: logo,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                )
              else
                Positioned(
                  right: -30,
                  top: -10,
                  child: Icon(
                    Icons.live_tv_rounded,
                    size: 300,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [Color(0xCC000000), Colors.transparent],
                    stops: [0, 0.7],
                  ),
                ),
              ),
              Positioned(
                left: 24,
                top: 22,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'JONLI',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 26,
                right: 26,
                bottom: 22,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        fontFamily: 'serif',
                        letterSpacing: 0.5,
                        shadows: [Shadow(blurRadius: 18, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 17,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Binafsha vidjet: tugallanmagan video yoki musiqa.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MediaItem>>(
      valueListenable: TvStore.instance.history,
      builder: (context, history, _) {
        final item = history
            .where(
              (e) =>
                  !e.isLive &&
                  e.durationMs > 0 &&
                  e.progress < 0.95 &&
                  e.kind != MediaKind.image,
            )
            .firstOrNull;
        final left = item == null
            ? 0
            : ((item.durationMs - item.positionMs) / 60000).ceil();
        return TvFocusable(
          onTap: () => item == null
              ? openFiles(context, MediaKind.audio)
              : playItem(context, item),
          builder: (context, f) => Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E2DE2), Color(0xFFD62F9B)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ArtBox(
                          seed: item?.title ?? 'musiqa',
                          icon: item == null
                              ? Icons.music_note_rounded
                              : iconFor(item.kind),
                          iconSize: 26,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      item == null
                          ? Icons.graphic_eq_rounded
                          : Icons.podcasts_rounded,
                      size: 24,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  item == null ? 'MUSIQA' : '$left DAQ. QOLDI',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item?.title ?? 'Telefondagi qo‘shiqlar',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Oq vidjet: ulangan pultlar.
class _RemoteCard extends StatelessWidget {
  const _RemoteCard();

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: () => _push(context, const PairScreen()),
      builder: (context, f) => Container(
        color: Colors.white,
        padding: const EdgeInsets.all(14),
        child: ValueListenableBuilder<int>(
          valueListenable: TvServices.instance.remotes,
          builder: (context, n, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFFF2F2F7), Color(0xFFB8B8C0)],
                    center: Alignment(-0.3, -0.4),
                  ),
                ),
                child: const Icon(
                  Icons.phone_iphone_rounded,
                  color: Colors.black54,
                  size: 30,
                ),
              ),
              const Spacer(),
              Text(
                n > 0 ? 'ULANGAN' : 'PULT',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: Colors.black45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                n > 0 ? '$n ta pult' : 'Telefonni ulash',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastdagi shishasimon dok — ilovalar.
class _Dock extends StatelessWidget {
  const _Dock();

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 30,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final app in _apps)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: _DockIcon(
                label: app.name,
                onTap: () => app.open(context),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: app.colors,
                    ),
                  ),
                  child: Icon(app.icon, color: Colors.white, size: 32),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DockIcon extends StatefulWidget {
  const _DockIcon({
    required this.label,
    required this.onTap,
    required this.child,
    this.circle = false,
  });
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool circle;

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvFocusable(
          onTap: widget.onTap,
          scale: 1.18,
          radius: widget.circle ? 30 : 16,
          onFocusChange: (f) => setState(() => _f = f),
          builder: (context, f) =>
              SizedBox(width: 60, height: 60, child: widget.child),
        ),
        const SizedBox(height: 6),
        AnimatedOpacity(
          opacity: _f ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Text(
            widget.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/* ---------------- 2-sahifa: media markazi ---------------- */

class _Tile {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.open,
    this.item,
    this.progress,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final void Function(BuildContext) open;
  final MediaItem? item;
  final double? progress;
}

class _MediaPage extends StatefulWidget {
  const _MediaPage({required this.firstFocus, required this.onHome});
  final FocusNode firstFocus;
  final VoidCallback onHome;

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  int _focused = 0;

  List<_Tile> _tiles(List<MediaItem> history) => [
    for (final h in history.take(6))
      _Tile(
        title: h.title,
        subtitle: h.isLive
            ? 'Jonli efir · ${h.group.isEmpty ? 'kanal' : h.group}'
            : h.durationMs > 0
            ? '${(h.progress * 100).round()}% ko‘rilgan'
            : h.kindLabel,
        icon: iconFor(h.kind),
        item: h,
        progress: h.isLive || h.durationMs == 0 ? null : h.progress,
        open: (c) => playItem(c, h),
      ),
    _Tile(
      title: 'Jonli TV',
      subtitle: 'Televizion kanallar',
      icon: Icons.live_tv_rounded,
      open: openLive,
    ),
    _Tile(
      title: 'YouTube',
      subtitle: 'Videolar va kliplar',
      icon: Icons.smart_display_rounded,
      open: (_) =>
          TvServices.instance.openApp('https://www.youtube.com/', 'YouTube'),
    ),
    _Tile(
      title: 'Filmlar',
      subtitle: 'Telefondagi videolar',
      icon: Icons.movie_rounded,
      open: (c) => openFiles(c, MediaKind.video),
    ),
    _Tile(
      title: 'Musiqa',
      subtitle: 'Qo‘shiqlaringiz',
      icon: Icons.album_rounded,
      open: (c) => openFiles(c, MediaKind.audio),
    ),
    _Tile(
      title: 'Rasmlar',
      subtitle: 'Galereya va slayd-shou',
      icon: Icons.photo_library_rounded,
      open: (c) => openFiles(c, MediaKind.image),
    ),
    _Tile(
      title: 'Brauzer',
      subtitle: 'Istalgan sayt',
      icon: Icons.public_rounded,
      open: (_) =>
          TvServices.instance.openApp('https://www.google.com/', 'Brauzer'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<MediaItem>>(
      valueListenable: TvStore.instance.history,
      builder: (context, history, _) {
        final tiles = _tiles(history);
        final cur = tiles[_focused.clamp(0, tiles.length - 1)];
        return Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _Backdrop(
                key: ValueKey(cur.title + cur.icon.codePoint.toString()),
                tile: cur,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xCC000000), Color(0x22000000)],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD000000)],
                  stops: [0.35, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(110, 44, 70, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Media markazi',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const Spacer(),
                      Ticker(
                        builder: (_, now) => Text(
                          hhmm(now),
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(cur.title),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cur.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 20)],
                          ),
                        ),
                        Text(
                          cur.subtitle,
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 236,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < tiles.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 22),
                              child: _GameCard(
                                tile: tiles[i],
                                focusNode: i == 0 ? widget.firstFocus : null,
                                onFocus: () => setState(() => _focused = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(child: _IconBar(onHome: widget.onHome)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({super.key, required this.tile});
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final img = tile.item?.kind == MediaKind.image
        ? imageFor(tile.item!, width: 1280)
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: ArtPainter('bg-${tile.title}')),
        if (img != null)
          Image(
            image: img,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(),
          )
        else
          Align(
            alignment: const Alignment(0.75, -0.2),
            child: Icon(
              tile.icon,
              size: 420,
              color: Colors.white.withValues(alpha: 0.13),
            ),
          ),
      ],
    );
  }
}

/// PlayStation uslubidagi karta: tanlanganda kattalashib, foizni ko‘rsatadi.
class _GameCard extends StatefulWidget {
  const _GameCard({required this.tile, required this.onFocus, this.focusNode});
  final _Tile tile;
  final VoidCallback onFocus;
  final FocusNode? focusNode;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  bool _f = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    final item = t.item;
    return TvFocusable(
      focusNode: widget.focusNode,
      scale: 1.0,
      radius: 20,
      onTap: () => t.open(context),
      onFocusChange: (f) {
        setState(() => _f = f);
        if (f) widget.onFocus();
      },
      builder: (context, f) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: _f ? 196 : 158,
        height: _f ? 228 : 158,
        color: const Color(0xFF1B1D24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ArtBox(
                seed: t.title,
                icon: t.icon,
                image: item == null ? null : imageFor(item, width: 400),
                cover: item?.kind == MediaKind.image,
                iconSize: 54,
              ),
            ),
            if (_f)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                color: const Color(0xFF14161C),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          t.progress != null
                              ? '${(t.progress! * 100).round()}%'
                              : (item?.isLive ?? false)
                              ? 'LIVE'
                              : 'Ochish',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (t.progress != null || item != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white70),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item?.isLive ?? false
                                  ? 'Efirda'
                                  : 'Davom etmoqda',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          item == null
                              ? Icons.open_in_new_rounded
                              : Icons.play_circle_fill_rounded,
                          size: 15,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item == null ? 'Kirish' : 'Davom ettirish',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (t.progress != null)
              LinearProgressIndicator(
                value: t.progress,
                minHeight: 4,
                backgroundColor: Colors.white12,
                color: const Color(0xFF3B6CFF),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pastki ikonka paneli (PlayStation uslubi).
class _IconBar extends StatelessWidget {
  const _IconBar({required this.onHome});
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, VoidCallback)>[
      (
        Icons.star_rounded,
        'Sevimlilar',
        () => openLive(context, favorites: true),
      ),
      (
        Icons.music_note_rounded,
        'Musiqa',
        () => openFiles(context, MediaKind.audio),
      ),
      (
        Icons.settings_remote_rounded,
        'Pult',
        () => _push(context, const PairScreen()),
      ),
      (Icons.home_rounded, 'Bosh sahifa', onHome),
      (Icons.folder_rounded, 'Fayllar', () => openFiles(context)),
      (
        Icons.settings_rounded,
        'Sozlamalar',
        () => _push(context, const SettingsScreen()),
      ),
      (
        Icons.power_settings_new_rounded,
        'Uyqu',
        () => _push(context, const SleepScreen()),
      ),
    ];
    return Glass(
      radius: 26,
      blur: false,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, label, onTap) in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _DockIcon(
                label: label,
                circle: true,
                onTap: onTap,
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.06),
                  child: Icon(icon, size: 28, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
