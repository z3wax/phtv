import 'dart:convert';
import 'dart:io';

import 'model.dart';

/// O‘zbekistonning ochiq (bepul, qonuniy) kanallari ro‘yxati.
const uzbekPlaylistUrl = 'https://iptv-org.github.io/iptv/countries/uz.m3u';

const _iptv = 'https://iptv-org.github.io/iptv';

/// Ochiq (bepul efir) kanallar to‘plami — iptv-org ro‘yxatlari.
class ChannelPack {
  const ChannelPack(this.id, this.name, this.url, {this.byDefault = true});
  final String id;

  /// Jonli TV’dagi guruh nomi.
  final String name;
  final String url;
  final bool byDefault;
}

const channelPacks = <ChannelPack>[
  ChannelPack('uz', 'O‘zbekiston', '$_iptv/countries/uz.m3u'),
  ChannelPack('uzb', 'O‘zbekiston', '$_iptv/languages/uzb.m3u'),
  ChannelPack('movies', 'Kino', '$_iptv/categories/movies.m3u'),
  ChannelPack('series', 'Seriallar', '$_iptv/categories/series.m3u'),
  ChannelPack('kids', 'Bolalar', '$_iptv/categories/kids.m3u'),
  ChannelPack('animation', 'Multfilmlar', '$_iptv/categories/animation.m3u'),
  ChannelPack('music', 'Musiqa', '$_iptv/categories/music.m3u'),
  ChannelPack('sports', 'Sport', '$_iptv/categories/sports.m3u'),
  ChannelPack('documentary', 'Hujjatli', '$_iptv/categories/documentary.m3u'),
  ChannelPack('rus', 'Rus tilida', '$_iptv/languages/rus.m3u'),
  ChannelPack('kz', 'Qozog‘iston', '$_iptv/countries/kz.m3u'),
  ChannelPack('tur', 'Turk tilida', '$_iptv/languages/tur.m3u'),
  ChannelPack(
    'news',
    'Yangiliklar',
    '$_iptv/categories/news.m3u',
    byDefault: false,
  ),
  ChannelPack(
    'eng',
    'Ingliz tilida',
    '$_iptv/languages/eng.m3u',
    byDefault: false,
  ),
];

/// Kanal nomidan sifat: “Sevimli TV (1080p)” → 1080, “… 4K” → 2160.
int qualityOf(String title) {
  final m = RegExp(r'\((\d{3,4})[pi]\)').firstMatch(title);
  if (m != null) return int.parse(m.group(1)!);
  if (RegExp(r'\b(4K|UHD|2160p)\b', caseSensitive: false).hasMatch(title)) {
    return 2160;
  }
  if (RegExp(r'\b(FHD|Full HD)\b', caseSensitive: false).hasMatch(title)) {
    return 1080;
  }
  if (RegExp(r'\bHD\b').hasMatch(title)) return 720;
  return 0;
}

/// “Sevimli TV (1080p) [Not 24/7]” → “Sevimli TV”.
String cleanTitle(String title) {
  final t = title
      .replaceAll(RegExp(r'\s*\(\d{3,4}[pi]\)'), '')
      .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.isEmpty ? title.trim() : t;
}

String _key(String title) => cleanTitle(title)
    .toLowerCase()
    .replaceAll(RegExp(r'\b(hd|fhd|uhd|4k|tv|тв)\b'), '')
    .replaceAll(RegExp(r'[^a-z0-9а-яёўқғҳ]'), '');

/// Kanallar ro‘yxatini tartiblaydi: geo-bloklanganlar tashlanadi, bir xil
/// kanalning bir nechta manbasi bittaga yig‘iladi (eng sifatlisi asosiy,
/// qolganlari — zaxira), har guruhda sifatlilari tepada.
({List<MediaItem> channels, Map<String, List<String>> alternates})
organizeChannels(List<MediaItem> raw) {
  final byKey = <String, List<MediaItem>>{};
  final order = <String>[];
  for (final c in raw) {
    if (c.title.contains('[Geo-blocked]')) continue;
    final k = _key(c.title);
    final list = byKey.putIfAbsent(k.isEmpty ? c.source : k, () {
      order.add(k.isEmpty ? c.source : k);
      return [];
    });
    if (!list.any((e) => e.source == c.source)) list.add(c);
  }
  final groups = <String, List<MediaItem>>{};
  final alternates = <String, List<String>>{};
  for (final k in order) {
    final list = byKey[k]!;
    final first = list.first;
    final sorted = [...list]
      ..sort((a, b) => qualityOf(b.title).compareTo(qualityOf(a.title)));
    final best = sorted.first;
    final item = MediaItem(
      title: cleanTitle(best.title),
      source: best.source,
      kind: MediaKind.live,
      logo: best.logo ?? first.logo,
      group: first.group,
      quality: qualityOf(best.title),
    );
    if (sorted.length > 1) {
      alternates[best.source] = [for (final e in sorted.skip(1)) e.source];
    }
    groups.putIfAbsent(first.group, () => []).add(item);
  }
  final out = <MediaItem>[];
  for (final list in groups.values) {
    // Barqaror tartib: sifat, keyin asl tartib.
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final q = b.$2.quality.compareTo(a.$2.quality);
        return q != 0 ? q : a.$1.compareTo(b.$1);
      });
    out.addAll(indexed.map((e) => e.$2));
  }
  return (channels: out, alternates: alternates);
}

/// Kanallarni M3U matniga yozadi (saqlash uchun).
String toM3u(List<MediaItem> items) {
  final b = StringBuffer('#EXTM3U\n');
  for (final c in items) {
    final logo = c.logo == null ? '' : ' tvg-logo="${c.logo}"';
    b
      ..write('#EXTINF:-1$logo group-title="${c.group.replaceAll('"', '')}",')
      ..writeln(c.title)
      ..writeln(c.source);
  }
  return b.toString();
}

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
