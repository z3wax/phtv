import 'dart:convert';
import 'dart:io';

import 'model.dart';

/// O‘zbekistonning ochiq (bepul, qonuniy) kanallari ro‘yxati.
const uzbekPlaylistUrl = 'https://iptv-org.github.io/iptv/countries/uz.m3u';

/// M3U / M3U8 pleylistdan kanallar ro‘yxatini oladi.
List<MediaItem> parseM3u(String text) {
  final out = <MediaItem>[];
  String? name, logo, group;
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final attrs = {
        for (final m in attr.allMatches(line)) m.group(1)!: m.group(2)!,
      };
      // Nom — oxirgi qo‘shtirnoqdan keyingi verguldan so‘ng.
      final lastQuote = line.lastIndexOf('"');
      final comma = line.indexOf(',', lastQuote < 0 ? 0 : lastQuote);
      name = comma >= 0 ? line.substring(comma + 1).trim() : null;
      if (name == null || name.isEmpty) name = attrs['tvg-name'];
      logo = attrs['tvg-logo'];
      group = attrs['group-title'];
      continue;
    }
    if (line.startsWith('#')) continue;
    final uri = Uri.tryParse(line);
    if (uri == null ||
        !const {'http', 'https', 'rtmp', 'rtsp'}.contains(uri.scheme)) {
      name = logo = group = null;
      continue;
    }
    final fallback = uri.pathSegments.isEmpty
        ? uri.host
        : uri.pathSegments.last;
    out.add(
      MediaItem(
        title: (name == null || name.isEmpty) ? fallback : name,
        source: line,
        kind: MediaKind.live,
        logo: (logo == null || logo.isEmpty) ? null : logo,
        group: _cleanGroup(group),
      ),
    );
    name = logo = group = null;
  }
  return out;
}

String _cleanGroup(String? g) {
  if (g == null || g.trim().isEmpty) return 'Boshqa';
  // iptv-org guruhlari “News;General” ko‘rinishida bo‘ladi.
  final first = g.split(';').first.trim();
  return _groupNames[first] ?? first;
}

const _groupNames = {
  'Undefined': 'Boshqa',
  'General': 'Umumiy',
  'News': 'Yangiliklar',
  'Sports': 'Sport',
  'Music': 'Musiqa',
  'Movies': 'Kino',
  'Kids': 'Bolalar',
  'Animation': 'Multfilm',
  'Entertainment': 'Ko‘ngilochar',
  'Education': 'Ta’lim',
  'Religious': 'Diniy',
  'Documentary': 'Hujjatli',
  'Culture': 'Madaniyat',
  'Series': 'Serial',
};

/// Pleylistni internetdan yuklaydi.
Future<String> fetchText(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, 'TelefonTV/1.0');
    final res = await req.close().timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    return await res.transform(const Utf8Decoder(allowMalformed: true)).join();
  } finally {
    client.close(force: true);
  }
}
