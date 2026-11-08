import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/external.dart';
import 'package:telefon_tv/tv/sites.dart';
import 'package:telefon_tv/tv/web_nav.dart';

void main() {
  test('YouTube manzillari televizor ko‘rinishiga o‘tadi', () {
    expect(youtubeTvFor('https://www.youtube.com/'), youtubeTvUrl);
    expect(youtubeTvFor('https://m.youtube.com/feed'), youtubeTvUrl);
    expect(
      youtubeTvFor('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10'),
      'https://www.youtube.com/tv#/watch?v=dQw4w9WgXcQ',
    );
    expect(
      youtubeTvFor('https://youtu.be/dQw4w9WgXcQ'),
      'https://www.youtube.com/tv#/watch?v=dQw4w9WgXcQ',
    );
    expect(
      youtubeTvFor('https://www.youtube.com/shorts/abcDEF12345'),
      'https://www.youtube.com/tv#/watch?v=abcDEF12345',
    );
    expect(
      youtubeTvFor('https://www.youtube.com/results?search_query=multfilm'),
      youtubeTvSearchUrl('multfilm'),
    );
    expect(
      youtubeTvFor('https://www.youtube.com/tv#/browse'),
      'https://www.youtube.com/tv#/browse',
    );
    expect(youtubeTvFor('https://idub.tv/'), isNull);
    expect(youtubeTvFor('https://notyoutube.com/watch?v=dQw4w9WgXcQ'), isNull);
    final search = Uri.parse(youtubeTvSearchUrl(' o‘zbek qo‘shiqlari '));
    expect(search.path, '/tv');
    expect(
      Uri.parse(search.fragment).queryParameters['q'],
      'o‘zbek qo‘shiqlari',
    );
  });

  test('YouTube TV video cheklovi: H.264, 1080p gacha', () {
    // Haqiqiy brauzerda ham tekshirilgan: AV1/VP9/4K — yo‘q, H.264 1080p — ha.
    expect(youtubeVideoLimitScript, contains('MediaSource.isTypeSupported'));
    expect(youtubeVideoLimitScript, contains('canPlayType'));
    expect(youtubeVideoLimitScript, contains('decodingInfo'));
    expect(youtubeVideoLimitScript, contains('av01'));
    expect(youtubeVideoLimitScript, contains('vp9'));
    expect(youtubeVideoLimitScript, contains('MAXH=1080'));
    expect(youtubeVideoLimitScript, isNot(contains('avc1')));
  });

  test('iDub — asl sayt manzili bilan', () {
    final idub = defaultSites.firstWhere((s) => s.id == 'idub');
    expect(idub.url, 'https://idub.tv/');
  });

  test('pult tugmalari sahifaga to‘g‘ri klaviatura kodi bilan boradi', () {
    expect(webKeyScript('down'), contains("key:'ArrowDown'"));
    expect(webKeyScript('down'), contains('return 40'));
    expect(webKeyScript('escape'), contains('return 27'));
    expect(webKeyScript('enter'), contains('return 13'));
    expect(webKeyScript('volume'), isEmpty);
    expect(webNavMove('left'), endsWith("window.__z3nav.move('left')"));
    expect(webNavOk(native: true), endsWith('window.__z3nav.ok(true)'));
  });
}
