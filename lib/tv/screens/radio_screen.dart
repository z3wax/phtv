import 'package:flutter/material.dart';

import '../model.dart';
import '../radio.dart';
import '../services.dart';
import '../widgets.dart';
import 'files_screen.dart';
import 'player_screen.dart';

/// Radio: O‘zbekiston, rus tilida, turkcha va dunyo bo‘ylab internet
/// radiolari (fayl so‘ramaydi). “Mening musiqam” — yuborilgan fayllar.
class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key, this.directory});
  final RadioDirectory? directory;

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  static final _cache = <String, List<MediaItem>>{};
  late final _dir = widget.directory ?? RadioDirectory();
  int _section = 0;
  String? _query;
  List<MediaItem> _stations = const [];
  bool _loading = false;
  String? _error;
  final _firstStation = FocusNode(debugLabel: 'firstStation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(0));
  }

  @override
  void dispose() {
    _firstStation.dispose();
    super.dispose();
  }

  Future<void> _open(int i, {String? query}) async {
    final key = query == null ? 's$i' : 'q$query';
    setState(() {
      _section = i;
      _query = query;
      _error = null;
      _stations = _cache[key] ?? const [];
      _loading = _stations.isEmpty;
    });
    if (_stations.isNotEmpty) return;
    try {
      final list = query == null
          ? await _dir.section(RadioDirectory.sections[i].$2)
          : await _dir.search(query);
      _cache[key] = list;
      if (!mounted || _section != i || _query != query) return;
      setState(() {
        _stations = list;
        _loading = false;
        if (list.isEmpty) _error = 'Bu bo‘limda radio topilmadi';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Radio ro‘yxatini ochib bo‘lmadi — internetni tekshiring';
      });
    }
  }

  void _search() => TvServices.instance.editText(
    context,
    title: 'Radio nomi (masalan: Oriat, Europa Plus)',
    value: _query ?? '',
    onSubmit: (v) {
      final q = v.trim();
      if (q.isNotEmpty) _open(-1, query: q);
    },
  );

  @override
  Widget build(BuildContext context) {
    final sections = RadioDirectory.sections;
    Widget tab(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap, {
      bool autofocus = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        radius: 14,
        scale: 1.03,
        autofocus: autofocus,
        onTap: onTap,
        builder: (context, f) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: f
              ? Colors.white
              : selected
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(icon, size: 22, color: f ? Colors.black : Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: f ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            children: [
              TvHeader(
                title: 'Radio',
                trailing: [
                  if (_loading)
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  if (_stations.isNotEmpty)
                    Text(
                      '${_stations.length} ta stansiya',
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 250,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 30),
                        children: [
                          for (var i = 0; i < sections.length; i++)
                            tab(
                              sections[i].$1,
                              Icons.radio_rounded,
                              _query == null && _section == i,
                              () => _open(i),
                              autofocus: i == 0,
                            ),
                          tab(
                            'Qidirish',
                            Icons.search_rounded,
                            _query != null,
                            _search,
                          ),
                          tab(
                            'Mening musiqam',
                            Icons.library_music_rounded,
                            false,
                            () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const FilesScreen(filter: MediaKind.audio),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(fontSize: 22, color: Colors.white70),
            ),
            const SizedBox(height: 18),
            TvButton(
              icon: Icons.refresh_rounded,
              label: 'Qayta urinish',
              onTap: () {
                _cache.remove(_query == null ? 's$_section' : 'q$_query');
                _open(_section, query: _query);
              },
            ),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.95,
        mainAxisSpacing: 22,
        crossAxisSpacing: 22,
      ),
      itemCount: _stations.length,
      itemBuilder: (context, i) {
        final s = _stations[i];
        return TvFocusable(
          focusNode: i == 0 ? _firstStation : null,
          radius: 18,
          onTap: () =>
              Navigator.of(context).push(PlayerScreen.route(_stations, i)),
          builder: (context, f) => Container(
            color: const Color(0xFF17181F),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ArtBox(
                    seed: s.title,
                    icon: Icons.radio_rounded,
                    image: s.logo == null ? null : NetworkImage(s.logo!),
                    iconSize: 50,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        s.group.replaceFirst('Radio · ', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
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
