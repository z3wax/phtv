import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/wallpapers.dart';

void main() {
  test('gallery selects large photos and excludes unrelated image hosts', () {
    expect(
      parseYandexWallpapers({
        'backgrounds': [
          {
            'thumbnails': {
              'desktop2560': {'jpeg': scenicImages[0]},
              'desktop': {'jpeg': scenicImages[1]},
            },
          },
          {
            'thumbnails': {
              'desktop': {'jpeg': 'https://unrelated.invalid/image.jpg'},
            },
          },
          {
            'thumbnails': {
              'desktop': {'jpeg': scenicImages[2]},
            },
          },
        ],
      }),
      [scenicImages[0], scenicImages[2]],
    );
  });
  test('cached gallery is usable without another network request', () async {
    final directory = await Directory.systemTemp.createTemp(
      'phtv-wallpaper-test',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((r) async {
      requests++;
      r.response.write(
        jsonEncode({
          'backgrounds': [
            {
              'thumbnails': {
                'desktop2560': {'jpeg': scenicImages[1]},
              },
            },
          ],
        }),
      );
      await r.response.close();
    });
    final uri = Uri.parse('http://127.0.0.1:${server.port}/gallery');
    try {
      expect(
        await WallpaperRepository(
          endpoint: uri,
          cacheDirectory: directory,
        ).images(),
        [scenicImages[1]],
      );
      expect(
        await WallpaperRepository(
          endpoint: uri,
          cacheDirectory: directory,
        ).images(),
        [scenicImages[1]],
      );
      expect(requests, 1);
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
