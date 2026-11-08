import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Yandex Browser gallery, Lakes collection. Public image URLs are also a
/// fallback when gallery metadata is unavailable; full images stay on Yandex.
const scenicImages = <String>[
  'https://yastatic.net/s3/bro-bg-store/d8d7129e-bdfe-4a71-9373-bbaae95dc6c1.jpg',
  'https://yastatic.net/s3/bro-bg-store/0a14fe27-f75c-4a91-b2e1-d42b102fce87.jpg',
  'https://yastatic.net/s3/bro-bg-store/982089ca-727a-4b57-821d-732d2363d2cd.jpg',
  'https://yastatic.net/s3/bro-bg-store/2a8d4b95-4a0e-4b98-9e12-79958abfb1c8.jpg',
  'https://yastatic.net/s3/bro-bg-store/8c698b79-68ea-4d64-95f9-c4e97fedb64e.jpg',
  'https://yastatic.net/s3/bro-bg-store/dcf38ed0-f79f-485e-b9f8-30bd5bacc44c.jpg',
];

class WallpaperRepository {
  WallpaperRepository({this.endpoint, this.cacheDirectory});
  static final instance = WallpaperRepository();
  static bool enabled = true;
  final Uri? endpoint;
  final Directory? cacheDirectory;
  Future<List<String>>? _loading;
  List<String>? _images;
  Directory? _directory;
  int _index = DateTime.now().day % scenicImages.length;
  bool _slot = false;
  Future<File?>? _nextJob;

  Future<Directory> _cache() async {
    if (_directory != null) return _directory!;
    final base = cacheDirectory ?? await getTemporaryDirectory();
    return _directory = await Directory(
      '${base.path}/telefon-tv-backgrounds',
    ).create(recursive: true);
  }

  Future<List<String>> images() => _loading ??= _load();

  Future<List<String>> _load() async {
    var images = scenicImages;
    final dir = await _cache();
    final manifest = File('${dir.path}/gallery.json');
    try {
      if (await manifest.exists()) {
        final cached = jsonDecode(await manifest.readAsString()) as Map;
        final urls = (cached['images'] as List)
            .whereType<String>()
            .where(isYandexImage)
            .take(16)
            .toList();
        if (urls.isNotEmpty) images = urls;
        final fetched = DateTime.tryParse('${cached['date']}');
        if (fetched != null &&
            DateTime.now().difference(fetched) < const Duration(hours: 24)) {
          return _images = images;
        }
      }
    } catch (_) {}
    try {
      final data = await _download(
        endpoint ??
            Uri.parse(
              'https://browser.yandex.com/wallpapers/api/desktop/collection/350?lang=en',
            ),
        2 * 1024 * 1024,
      );
      final urls = parseYandexWallpapers(jsonDecode(utf8.decode(data)));
      if (urls.isNotEmpty) {
        images = urls;
        await manifest.writeAsString(
          jsonEncode({
            'date': DateTime.now().toIso8601String(),
            'images': images,
          }),
        );
      }
    } catch (_) {
      /* Use cached metadata, then known gallery images. */
    }
    return _images = images;
  }

  Future<File?> next() =>
      _nextJob ??= _next().whenComplete(() => _nextJob = null);

  Future<File?> _next() async {
    final dir = await _cache();
    final images = _images ?? await this.images();
    final url = images[_index++ % images.length];
    final destination = File('${dir.path}/background-${_slot ? 1 : 0}.jpg');
    _slot = !_slot;
    try {
      final bytes = await _download(Uri.parse(url), 6 * 1024 * 1024);
      final temporary = File('${destination.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      // Always keep one complete previous image for offline launch.
      await temporary.rename(destination.path);
      return destination;
    } catch (_) {
      for (final name in ['background-0.jpg', 'background-1.jpg']) {
        final cached = File('${dir.path}/$name');
        if (await cached.exists()) return cached;
      }
      return null;
    }
  }
}

bool isYandexImage(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'yastatic.net' ||
          uri.host == 'bro-bg-store.s3.yandex.net') &&
      (uri.path.endsWith('.jpg') || uri.path.endsWith('.webp'));
}

List<String> parseYandexWallpapers(Object? data) {
  if (data is! Map || data['backgrounds'] is! List) return [];
  final urls = <String>{};
  for (final item in data['backgrounds'] as List) {
    if (item is! Map) continue;
    final thumbs = item['thumbnails'];
    if (thumbs is! Map) continue;
    final full =
        thumbs['desktop2560'] ?? thumbs['desktop1680'] ?? thumbs['desktop'];
    final url = full is Map ? (full['jpeg'] ?? full['webp']) : null;
    if (url is String && isYandexImage(url)) urls.add(url);
    if (urls.length >= 16) break;
  }
  return urls.toList();
}

Future<List<int>> _download(Uri uri, int limit) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..findProxy = HttpClient.findProxyFromEnvironment;
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Background HTTP ${response.statusCode}');
      }
      if (response.contentLength > limit) {
        throw const FormatException('Background too large');
      }
      final bytes = <int>[];
      await for (final part in response) {
        if (bytes.length + part.length > limit) {
          throw const FormatException('Background too large');
        }
        bytes.addAll(part);
      }
      if (bytes.isEmpty) throw const FormatException('Empty background');
      return bytes;
    })().timeout(const Duration(seconds: 10));
  } finally {
    client.close(force: true);
  }
}
