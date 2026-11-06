import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'm3u.dart';
import 'model.dart';

@immutable
class TvSettings {
  const TvSettings({this.city = 0, this.overscan = 0, this.playlistUrl = ''});

  /// Ob-havo uchun shahar (weather.dart dagi ro‘yxatdan).
  final int city;

  /// Televizor chetlarni kesib qo‘ysa — ekran chetidan foiz hisobida bo‘sh joy.
  final int overscan;
  final String playlistUrl;

  TvSettings copyWith({int? city, int? overscan, String? playlistUrl}) =>
      TvSettings(
        city: city ?? this.city,
        overscan: overscan ?? this.overscan,
        playlistUrl: playlistUrl ?? this.playlistUrl,
      );

  Map<String, Object?> toJson() => {
    'city': city,
    'overscan': overscan,
    'playlistUrl': playlistUrl,
  };

  static TvSettings fromJson(Object? j) {
    if (j is! Map) return const TvSettings();
    return TvSettings(
      city: (j['city'] as num?)?.toInt() ?? 0,
      overscan: (j['overscan'] as num?)?.toInt() ?? 0,
      playlistUrl: (j['playlistUrl'] as String?) ?? '',
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
      channels.value = parseM3u(playlist);
    }
    final key = await _getJson('remoteKey');
    remoteKey = key is String && key.length == 4
        ? key
        : (Random.secure().nextInt(9000) + 1000).toString();
    if (key != remoteKey) await _set('remoteKey', remoteKey);
  }

  void updateSettings(TvSettings s) {
    settings.value = s;
    _set('settings', s.toJson());
  }

  /// Pleylistni saqlaydi va kanallar sonini qaytaradi.
  Future<int> setPlaylist(String text, {String? url}) async {
    final list = parseM3u(text);
    if (list.isEmpty) return 0;
    channels.value = list;
    await _set('playlist', text);
    if (url != null) updateSettings(settings.value.copyWith(playlistUrl: url));
    return list.length;
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
  }
}
