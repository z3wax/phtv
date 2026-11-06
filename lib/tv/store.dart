import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'assistant/ai.dart';
import 'm3u.dart';
import 'model.dart';
import 'sites.dart';

@immutable
class TvSettings {
  const TvSettings({
    this.city = 0,
    this.overscan = 0,
    this.playlistUrl = '',
    this.motion,
  });

  /// Ob-havo uchun shahar (weather.dart dagi ro‘yxatdan).
  final int city;

  /// Televizor chetlarni kesib qo‘ysa — ekran chetidan foiz hisobida bo‘sh joy.
  final int overscan;
  final String playlistUrl;

  /// Fondagi suzuvchi yorug‘liklar. null — qurilmaga qarab: Ubuntu’da
  /// o‘chiq (videokartasiz kompyuterda ekranni buzishi mumkin), boshqalarda yoniq.
  final bool? motion;

  bool get motionOn => motion ?? !Platform.isLinux;

  TvSettings copyWith({
    int? city,
    int? overscan,
    String? playlistUrl,
    bool? motion,
  }) => TvSettings(
    city: city ?? this.city,
    overscan: overscan ?? this.overscan,
    playlistUrl: playlistUrl ?? this.playlistUrl,
    motion: motion ?? this.motion,
  );

  Map<String, Object?> toJson() => {
    'city': city,
    'overscan': overscan,
    'playlistUrl': playlistUrl,
    if (motion != null) 'motion': motion,
  };

  static TvSettings fromJson(Object? j) {
    if (j is! Map) return const TvSettings();
    return TvSettings(
      city: (j['city'] as num?)?.toInt() ?? 0,
      overscan: (j['overscan'] as num?)?.toInt() ?? 0,
      playlistUrl: (j['playlistUrl'] as String?) ?? '',
      motion: j['motion'] as bool?,
    );
  }
}

/// Telefondagi barcha ma’lumot: sozlamalar, kanallar, tarix, sevimlilar.
/// Hech narsa serverga yuborilmaydi.
class TvStore {
  TvStore._();
  static final instance = TvStore._();

  final settings = ValueNotifier<TvSettings>(const TvSettings());
  final channels = ValueNotifier<List<MediaItem>>(const []);
  final history = ValueNotifier<List<MediaItem>>(const []);
  final favorites = ValueNotifier<List<MediaItem>>(const []);
  final library = ValueNotifier<List<MediaItem>>(const []);

  /// AI yordamchi: bepul xizmat, kalit, ovozli javob.
  final assistant = ValueNotifier<AiConfig>(const AiConfig());

  /// Bosh ekrandagi kino saytlari (manzillari o‘zgartirilgan va qo‘shilganlari bilan).
  final sites = ValueNotifier<List<Site>>(defaultSites);
  Map<String, String> _siteUrls = {};
  List<Site> _customSites = [];

  /// Boshqa telefonlar pult bo‘lib ulanishi uchun PIN.
  String remoteKey = '';
  bool _loaded = false;

  SharedPreferencesAsync? _prefsOrNull() {
    try {
      return SharedPreferencesAsync();
    } catch (_) {
      return null; // testlarda va kutilmagan platformalarda — faqat xotirada
    }
  }

  Future<String?> _get(String key) async {
    try {
      return await _prefsOrNull()?.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _set(String key, Object value) async {
    try {
      await _prefsOrNull()?.setString(key, jsonEncode(value));
    } catch (_) {}
  }

  Future<Object?> _getJson(String key) async {
    final s = await _get(key);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  List<MediaItem> _items(Object? j) => [
    if (j is List)
      for (final e in j)
        if (MediaItem.fromJson(e) case final item?) item,
  ];

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    settings.value = TvSettings.fromJson(await _getJson('settings'));
    history.value = _items(await _getJson('history'));
    favorites.value = _items(await _getJson('favorites'));
    library.value = _items(await _getJson('library'));
    final playlist = await _getJson('playlist');
    if (playlist is String && playlist.isNotEmpty) {
      _applyChannels(parseM3u(playlist));
    }
    final packs = await _getJson('packs');
    if (packs is List) selectedPacks = {for (final p in packs) '$p'};
    final updated = await _getJson('channelsUpdated');
    if (updated is int) channelsUpdated = updated;
    assistant.value = AiConfig.fromJson(await _getJson('assistant'));
    final siteJson = await _getJson('sites');
    if (siteJson is Map) {
      final urls = siteJson['urls'];
      if (urls is Map) {
        _siteUrls = {
          for (final e in urls.entries)
            if (e.value is String) '${e.key}': e.value as String,
        };
      }
      final custom = siteJson['custom'];
      if (custom is List) {
        _customSites = [
          for (final e in custom)
            if (Site.fromJson(e) case final site?) site,
        ];
      }
      _publishSites();
    }
    final key = await _getJson('remoteKey');
    remoteKey = key is String && key.length == 4
        ? key
        : (Random.secure().nextInt(9000) + 1000).toString();
    if (key != remoteKey) await _set('remoteKey', remoteKey);
  }

  void updateAssistant(AiConfig c) {
    assistant.value = c;
    _set('assistant', c.toJson());
  }

  void _publishSites() {
    sites.value = [
      for (final s in defaultSites)
        _siteUrls.containsKey(s.id) ? s.withUrl(_siteUrls[s.id]!) : s,
      ..._customSites,
    ];
  }

  void _saveSites() {
    _publishSites();
    _set('sites', {
      'urls': _siteUrls,
      'custom': [for (final s in _customSites) s.toJson()],
    });
  }

  /// Sayt manzilini o‘zgartirish (masalan, iDub’ning manzilini kiritish).
  void setSiteUrl(String id, String url) {
    final i = _customSites.indexWhere((s) => s.id == id);
    if (i >= 0) {
      _customSites[i] = _customSites[i].withUrl(url);
    } else {
      _siteUrls = {..._siteUrls, id: url};
    }
    _saveSites();
  }

  Site addSite(String name, String url) {
    final palette = [
      [0xFF14B8A6, 0xFF134E4A],
      [0xFFEC4899, 0xFF831843],
      [0xFF84CC16, 0xFF365314],
      [0xFF6366F1, 0xFF1E1B4B],
    ][_customSites.length % 4];
    final site = Site(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: url,
      colors: [Color(palette[0]), Color(palette[1])],
      custom: true,
    );
    _customSites = [..._customSites, site];
    _saveSites();
    return site;
  }

  void resetSites() {
    _siteUrls = {};
    _customSites = [];
    _saveSites();
  }

  void removeSite(String id) {
    _customSites = _customSites.where((s) => s.id != id).toList();
    _saveSites();
  }

  void updateSettings(TvSettings s) {
    settings.value = s;
    _set('settings', s.toJson());
  }

  /// Bir xil kanalning zaxira manbalari (asosiy manba → boshqalari).
  Map<String, List<String>> alternates = const {};

  /// Tanlangan kanal to‘plamlari (O‘zbekiston, Kino, Bolalar…).
  Set<String> selectedPacks = {
    for (final p in channelPacks)
      if (p.byDefault) p.id,
  };

  /// Kanallar oxirgi marta yangilangan vaqt (ms).
  int channelsUpdated = 0;

  List<String> alternatesFor(String source) => alternates[source] ?? const [];

  int _applyChannels(List<MediaItem> raw) {
    final r = organizeChannels(raw);
    alternates = r.alternates;
    channels.value = r.channels;
    return r.channels.length;
  }

  /// Pleylistni saqlaydi va kanallar sonini qaytaradi.
  Future<int> setPlaylist(String text, {String? url}) async {
    final raw = parseM3u(text);
    if (raw.isEmpty) return 0;
    final n = _applyChannels(raw);
    await _set('playlist', text);
    if (url != null) updateSettings(settings.value.copyWith(playlistUrl: url));
    return n;
  }

  /// Tanlangan to‘plamlardagi barcha ochiq kanallarni yuklaydi (bir vaqtda).
  /// Ba’zi ro‘yxat ochilmasa ham qolganlari yuklanadi. [extraUrl] —
  /// foydalanuvchining o‘z pleylisti (bo‘lsa, boshida turadi).
  Future<int> loadPacks({
    Set<String>? ids,
    String? extraUrl,
    Future<String> Function(String url) fetch = fetchText,
  }) async {
    final chosen = ids ?? selectedPacks;
    final packs = channelPacks.where((p) => chosen.contains(p.id)).toList();
    final extra = extraUrl ?? settings.value.playlistUrl;
    final results = await Future.wait([
      if (extra.isNotEmpty)
        fetch(extra).then(parseM3u).catchError((Object _) => <MediaItem>[]),
      for (final p in packs)
        fetch(p.url)
            .then(
              (t) => [
                for (final c in parseM3u(t))
                  MediaItem(
                    title: c.title,
                    source: c.source,
                    kind: MediaKind.live,
                    logo: c.logo,
                    group: p.name,
                  ),
              ],
            )
            .catchError((Object _) => <MediaItem>[]),
    ]);
    final raw = [for (final r in results) ...r];
    if (raw.isEmpty) return 0;
    final n = _applyChannels(raw);
    selectedPacks = chosen;
    channelsUpdated = DateTime.now().millisecondsSinceEpoch;
    await _set('playlist', toM3u(raw));
    await _set('packs', chosen.toList());
    await _set('channelsUpdated', channelsUpdated);
    return n;
  }

  Future<int> loadPlaylistFromUrl(String url) async =>
      setPlaylist(await fetchText(url), url: url);

  /// Ko‘rilganlar tarixi: oxirgisi birinchi, ko‘pi bilan 20 ta.
  void remember(MediaItem item) {
    item.updatedAt = DateTime.now().millisecondsSinceEpoch;
    final list = [
      item,
      ...history.value.where((e) => e.source != item.source),
    ].take(20).toList();
    history.value = list;
    _set('history', list.map((e) => e.toJson()).toList());
  }

  bool isFavorite(String source) =>
      favorites.value.any((e) => e.source == source);

  void toggleFavorite(MediaItem item) {
    final list = isFavorite(item.source)
        ? favorites.value.where((e) => e.source != item.source).toList()
        : [...favorites.value, item];
    favorites.value = list;
    _set('favorites', list.map((e) => e.toJson()).toList());
  }

  /// Telefondan tanlangan fayllar (video, musiqa, rasm).
  void addToLibrary(List<MediaItem> items) {
    final sources = items.map((e) => e.source).toSet();
    final list = [
      ...items,
      ...library.value.where((e) => !sources.contains(e.source)),
    ].take(300).toList();
    library.value = list;
    _set('library', list.map((e) => e.toJson()).toList());
  }

  Future<void> clearAll() async {
    for (final k in [
      'settings',
      'history',
      'favorites',
      'library',
      'playlist',
      'packs',
      'channelsUpdated',
      'assistant',
      'sites',
    ]) {
      try {
        await _prefsOrNull()?.remove(k);
      } catch (_) {}
    }
    settings.value = const TvSettings();
    history.value = const [];
    favorites.value = const [];
    library.value = const [];
    channels.value = const [];
    alternates = const {};
    channelsUpdated = 0;
    assistant.value = const AiConfig();
    _siteUrls = {};
    _customSites = [];
    _publishSites();
  }
}
