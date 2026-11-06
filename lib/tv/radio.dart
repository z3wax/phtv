import 'dart:convert';
import 'dart:io';

import 'model.dart';

/// Internet radio: Radio Browser — bepul, kalitsiz, 50 000+ stansiya.
class RadioDirectory {
  RadioDirectory({List<String>? servers})
    : servers =
          servers ??
          const [
            'https://de1.api.radio-browser.info',
            'https://de2.api.radio-browser.info',
            'https://nl1.api.radio-browser.info',
            'https://at1.api.radio-browser.info',
            'https://fi1.api.radio-browser.info',
          ];

  final List<String> servers;
  int _good = 0;

  /// Bo‘limlar: nomi va so‘rovi.
  static const sections = <(String, Map<String, String>)>[
    ('O‘zbekiston', {'countrycode': 'UZ'}),
    ('Rus tilida', {'language': 'russian'}),
    ('Turkcha', {'countrycode': 'TR'}),
    ('Qozog‘iston', {'countrycode': 'KZ'}),
    ('Musiqa', {'tag': 'pop'}),
    ('Klassika', {'tag': 'classical'}),
    ('Dunyo TOP', {}),
  ];

  Future<List<MediaItem>> section(
    Map<String, String> query, {
    int limit = 120,
  }) => _search({...query, 'limit': '$limit'});

  Future<List<MediaItem>> search(String name) =>
      _search({'name': name, 'limit': '80'});

  Future<List<MediaItem>> _search(Map<String, String> query) async {
    final params = {
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      ...query,
    };
    Object? lastError;
    for (var i = 0; i < servers.length; i++) {
      final server = servers[(_good + i) % servers.length];
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final uri = Uri.parse(
          '$server/json/stations/search',
        ).replace(queryParameters: params);
        final req = await client.getUrl(uri);
        req.headers.set(HttpHeaders.userAgentHeader, 'TelefonTV/1.0');
        final res = await req.close().timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}');
        }
        final body = await res.transform(utf8.decoder).join();
        _good = (_good + i) % servers.length;
        return parseStations(body);
      } catch (e) {
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }
    throw lastError ?? const HttpException('Radio ro‘yxati ochilmadi');
  }

  /// Radio Browser JSON → radio stansiyalar (bir xil nomlilar bir marta).
  static List<MediaItem> parseStations(String body) {
    final data = jsonDecode(body);
    if (data is! List) return const [];
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final e in data) {
      if (e is! Map) continue;
      final name = '${e['name'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
      final url = '${e['url_resolved'] ?? e['url'] ?? ''}'.trim();
      if (name.isEmpty || !url.startsWith('http')) continue;
      if (!seen.add(name.toLowerCase())) continue;
      final favicon = '${e['favicon'] ?? ''}'.trim();
      final bitrate = (e['bitrate'] as num?)?.toInt() ?? 0;
      final codec = '${e['codec'] ?? ''}'.trim();
      final country = '${e['country'] ?? ''}'.trim();
      out.add(
        MediaItem(
          title: name,
          source: url,
          kind: MediaKind.audio,
          logo: favicon.startsWith('http') ? favicon : null,
          group: [
            'Radio',
            if (country.isNotEmpty) country,
            if (bitrate > 0) '$bitrate kbit/s${codec.isEmpty ? '' : ' $codec'}',
          ].join(' · '),
        ),
      );
    }
    return out;
  }
}
