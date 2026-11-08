import 'package:flutter/material.dart';

import '../m3u.dart';
import '../model.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';
import 'player_screen.dart';

const _all = 'Hammasi';
const _favs = 'Sevimlilar';

/// Jonli TV: IPTV kanallar, guruhlar va sevimlilar.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, this.favoritesOnly = false});
  final bool favoritesOnly;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late String _group = widget.favoritesOnly ? _favs : _all;
  bool _loading = false;
  bool _hdOnly = false;
  final _firstChannel = FocusNode(debugLabel: 'firstChannel');

  @override
  void dispose() {
    _firstChannel.dispose();
    super.dispose();
  }

  Future<void> _load(String url) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final n = await TvStore.instance.loadPlaylistFromUrl(url);
      TvServices.instance.showToast(
        n > 0 ? '$n ta kanal yuklandi' : 'Pleylistda kanal topilmadi',
      );
      if (n > 0 && mounted) {
        setState(() => _group = _all);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _firstChannel.requestFocus(),
        );
      }
    } catch (_) {
      TvServices.instance.showToast(
        'Yuklab bo‘lmadi — internetni yoki manzilni tekshiring',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Barcha tanlangan to‘plamlar: O‘zbekiston, Kino, Bolalar, Sport…
  Future<void> _loadPacks([Set<String>? ids]) async {
    if (_loading) return;
    setState(() => _loading = true);
    TvServices.instance.showToast('Kanallar yuklanmoqda…');
    try {
      final n = await TvStore.instance.loadPacks(ids: ids);
      TvServices.instance.showToast(
        n > 0
            ? '$n ta kanal yuklandi'
            : 'Yuklab bo‘lmadi — internetni tekshiring',
      );
      if (n > 0 && mounted) {
        setState(() => _group = _all);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _firstChannel.requestFocus(),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choosePacks() async {
    final chosen = {...TvStore.instance.selectedPacks};
    final names = <String, List<ChannelPack>>{};
    for (final p in channelPacks) {
      names.putIfAbsent(p.name, () => []).add(p);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: const Color(0xFF15161C),
          title: const Text('Kanal to‘plamlari'),
          content: SizedBox(
            width: 560,
            height: 430,
            child: ListView(
              children: [
                for (final e in names.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TvFocusable(
                      radius: 12,
                      scale: 1.02,
                      autofocus: e.key == names.keys.first,
                      onTap: () => setLocal(() {
                        final on = e.value.every((p) => chosen.contains(p.id));
                        for (final p in e.value) {
                          on ? chosen.remove(p.id) : chosen.add(p.id);
                        }
                      }),
                      builder: (context, f) {
                        final on = e.value.every((p) => chosen.contains(p.id));
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: f
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.06),
                          child: Row(
                            children: [
                              Icon(
                                on
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: f
                                    ? Colors.black
                                    : (on
                                          ? const Color(0xFF34C759)
                                          : Colors.white54),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: f ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TvButton(
              icon: Icons.close_rounded,
              label: 'Bekor',
              onTap: () => Navigator.pop(ctx, false),
            ),
            TvButton(
              icon: Icons.download_rounded,
              label: 'Yuklash',
              primary: true,
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok == true && chosen.isNotEmpty) await _loadPacks(chosen);
  }

  void _askUrl() {
    TvServices.instance.editText(
      context,
      title: 'M3U pleylist manzili',
      value: TvStore.instance.settings.value.playlistUrl,
      onSubmit: (v) {
        final url = v.trim();
        if (url.startsWith('http')) _load(url);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = TvStore.instance;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: ListenableBuilder(
            listenable: Listenable.merge([store.channels, store.favorites]),
            builder: (context, _) {
              final channels = store.channels.value;
              final groups = <String>[
                _all,
                _favs,
                ...{for (final c in channels) c.group},
              ];
              final all = switch (_group) {
                _all => channels,
                _favs => store.favorites.value,
                final g => channels.where((c) => c.group == g).toList(),
              };
              final list = _hdOnly
                  ? all.where((c) => c.quality >= 720).toList()
                  : all;
              return Column(
                children: [
                  TvHeader(
                    title: 'Jonli TV',
                    trailing: [
                      if (_loading)
                        const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      if (channels.isNotEmpty) ...[
                        Text(
                          '${channels.length} ta kanal',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),
                        TvButton(
                          icon: _hdOnly ? Icons.hd_rounded : Icons.hd_outlined,
                          label: _hdOnly ? 'Faqat HD' : 'Hammasi',
                          primary: _hdOnly,
                          onTap: () => setState(() => _hdOnly = !_hdOnly),
                        ),
                        TvButton(
                          icon: Icons.layers_rounded,
                          label: 'To‘plamlar',
                          onTap: _choosePacks,
                        ),
                        TvButton(
                          icon: Icons.refresh_rounded,
                          label: 'Yangilash',
                          onTap: _loadPacks,
                        ),
                        TvButton(
                          icon: Icons.link_rounded,
                          label: 'Manzil',
                          onTap: _askUrl,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: channels.isEmpty && _group != _favs
                        ? _Empty(
                            loading: _loading,
                            onDefault: _loadPacks,
                            onUrl: _askUrl,
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 240,
                                child: ListView.builder(
                                  padding: const EdgeInsets.only(
                                    bottom: 30,
                                    top: 6,
                                    left: 6,
                                    right: 6,
                                  ),
                                  itemCount: groups.length,
                                  itemBuilder: (context, i) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TvFocusable(
                                      radius: 14,
                                      scale: 1.03,
                                      onTap: () =>
                                          setState(() => _group = groups[i]),
                                      builder: (context, f) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 12,
                                        ),
                                        color: f
                                            ? Colors.white
                                            : groups[i] == _group
                                            ? Colors.white.withValues(
                                                alpha: 0.18,
                                              )
                                            : Colors.transparent,
                                        child: Text(
                                          groups[i],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 19,
                                            fontWeight: groups[i] == _group
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: f
                                                ? Colors.black
                                                : Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: list.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Sevimlilar hali yo‘q.\nKanal ochilganda yulduzcha tugmasini bosing.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 22,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )
                                    : GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          8,
                                          12,
                                          40,
                                        ),
                                        cacheExtent: 800,
                                        gridDelegate:
                                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent: 240,
                                              childAspectRatio: 1.3,
                                              mainAxisSpacing: 22,
                                              crossAxisSpacing: 22,
                                            ),
                                        itemCount: list.length,
                                        itemBuilder: (context, i) =>
                                            _ChannelCard(
                                              item: list[i],
                                              focusNode: i == 0
                                                  ? _firstChannel
                                                  : null,
                                              favorite: store.isFavorite(
                                                list[i].source,
                                              ),
                                              onTap: () =>
                                                  Navigator.of(context).push(
                                                    PlayerScreen.route(list, i),
                                                  ),
                                            ),
                                      ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.item,
    required this.onTap,
    required this.favorite,
    this.focusNode,
  });
  final MediaItem item;
  final VoidCallback onTap;
  final bool favorite;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onTap: onTap,
      focusNode: focusNode,
      radius: 18,
      builder: (context, f) => Stack(
        fit: StackFit.expand,
        children: [
          ArtBox(
            seed: item.title,
            icon: Icons.live_tv_rounded,
            image: imageFor(item, width: 300),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
                stops: [0.45, 1],
              ),
            ),
          ),
          if (item.qualityLabel.isNotEmpty)
            Positioned(
              top: 8,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: item.quality >= 1080
                      ? const Color(0xFFFFD60A)
                      : Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.qualityLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          if (favorite)
            const Positioned(
              top: 8,
              right: 10,
              child: Icon(
                Icons.star_rounded,
                color: Color(0xFFFFC83D),
                size: 24,
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.loading,
    required this.onDefault,
    required this.onUrl,
  });
  final bool loading;
  final VoidCallback onDefault, onUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.satellite_alt_rounded,
            size: 90,
            color: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 18),
          const Text(
            'Kanallar hali qo‘shilmagan',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '1000+ ochiq kanal: O‘zbekiston, kino, seriallar, bolalar, sport, musiqa, rus tilida — yoki o‘z IPTV pleylistingiz (M3U).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvButton(
                icon: Icons.flag_rounded,
                label: loading ? 'Yuklanmoqda…' : 'O‘zbekiston kanallari',
                primary: true,
                autofocus: true,
                onTap: onDefault,
              ),
              const SizedBox(width: 18),
              TvButton(
                icon: Icons.link_rounded,
                label: 'Pleylist manzili',
                onTap: onUrl,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
