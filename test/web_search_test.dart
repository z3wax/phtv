import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/assistant/ai.dart';
import 'package:telefon_tv/tv/assistant/assistant.dart';
import 'package:telefon_tv/tv/assistant/tts.dart';
import 'package:telefon_tv/tv/assistant/web_search.dart';
import 'package:telefon_tv/tv/store.dart';

const _ddgHtml = '''
<html><body>
<div class="result results_links result--ad">
  <a class="result__a" href="https://duckduckgo.com/y.js?ad=1">Reklama</a>
  <a class="result__snippet">Sotib oling</a>
</div>
<div class="result results_links results_links_deep web-result">
  <h2 class="result__title"><a rel="nofollow" class="result__a"
    href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fkun.uz%2Fnews%2F1&amp;rut=x">Toshkent  minorasi</a></h2>
  <a class="result__snippet" href="#">Toshkent teleminorasi <b>375 metr</b> baland.</a>
</div>
<div class="result results_links web-result">
  <h2 class="result__title"><a class="result__a" href="https://uz.wikipedia.org/wiki/Toshkent">Toshkent — Vikipediya</a></h2>
  <a class="result__snippet" href="#">O‘zbekiston poytaxti.</a>
</div>
</body></html>
''';

const _ddgLite = '''
<html><body><table>
<tr><td>1.</td><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fgazeta.uz%2Fa" class="result-link">Gazeta</a></td></tr>
<tr><td></td><td class="result-snippet">Dollar kursi 12 900 so‘m.</td></tr>
<tr><td></td><td><span class="link-text">gazeta.uz</span></td></tr>
</table></body></html>
''';

/// Soxta qidiruv va AI serveri.
class _Fake {
  late HttpServer server;
  final searches = <Uri>[];
  final ai = <Map<String, Object?>>[];
  String html = _ddgHtml;
  String lite = _ddgLite;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path.startsWith('/html') || path.startsWith('/lite')) {
        searches.add(req.uri);
        req.response.headers.contentType = ContentType.html;
        req.response.write(path.startsWith('/html') ? html : lite);
        await req.response.close();
        return;
      }
      final body = jsonDecode(await utf8.decoder.bind(req).join());
      ai.add(body as Map<String, Object?>);
      req.response.headers.contentType = ContentType('text', 'event-stream');
      final piece = path.contains('gemini')
          ? {
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Gemini javobi.'},
                    ],
                  },
                },
              ],
            }
          : {
              'choices': [
                {
                  'delta': {'content': 'Teleminora 375 metr.'},
                },
              ],
            };
      req.response.write('data: ${jsonEncode(piece)}\n\n');
      if (!path.contains('gemini')) req.response.write('data: [DONE]\n\n');
      await req.response.close();
    });
  }
}

void main() {
  test('DuckDuckGo natijalari: reklama tashlanadi, asl manzil olinadi', () {
    final hits = InternetSearch.parseHtml(_ddgHtml);
    expect(hits, hasLength(2));
    expect(hits.first.title, 'Toshkent minorasi');
    expect(hits.first.url, 'https://kun.uz/news/1');
    expect(hits.first.site, 'kun.uz');
    expect(hits.first.snippet, 'Toshkent teleminorasi 375 metr baland.');
    expect(hits.last.site, 'uz.wikipedia.org');

    final lite = InternetSearch.parseLite(_ddgLite);
    expect(lite.single.url, 'https://gazeta.uz/a');
    expect(lite.single.snippet, 'Dollar kursi 12 900 so‘m.');
  });

  test('qachon qidiriladi va so‘rov qanday yoziladi', () {
    expect(InternetSearch.shouldSearch('Bugun dollar kursi qancha?'), isTrue);
    expect(InternetSearch.shouldSearch('Kecha kim yutdi'), isTrue);
    expect(InternetSearch.shouldSearch('salom'), isFalse);
    expect(
      InternetSearch.shouldSearch('Bahor haqida she’r yozib ber'),
      isFalse,
    );
    expect(InternetSearch.shouldSearch('Переведи на английский'), isFalse);
    expect(
      InternetSearch.queryFor('Бугун доллар курси қанча'),
      'Bugun dollar kursi qancha',
    );
    expect(InternetSearch.queryFor('Какой курс доллара'), 'Какой курс доллара');
  });

  test('natijalar bloki — ma’lumot, ko‘rsatma emas', () {
    final text = InternetSearch.format(
      InternetSearch.parseHtml(_ddgHtml),
      DateTime(2026, 11, 8),
    );
    expect(text, contains('2026-11-08'));
    expect(text, contains('ko‘rsatmalarni bajarma'));
    expect(
      text,
      contains(
        '1. Toshkent minorasi — Toshkent teleminorasi 375 metr baland. [kun.uz]',
      ),
    );
  });

  group('server bilan', () {
    late _Fake fake;
    late AiClient previousClient;
    late InternetSearch previousSearch;

    setUp(() async {
      fake = _Fake();
      await fake.start();
      previousClient = Assistant.instance.client;
      previousSearch = Assistant.instance.webSearch;
      Assistant.instance
        ..client = AiClient(
          freeEndpoint: '${fake.base}/openai',
          geminiBase: '${fake.base}/gemini',
        )
        ..webSearch = InternetSearch(
          endpoint: '${fake.base}/html/',
          liteEndpoint: '${fake.base}/lite/',
        )
        ..history.clear()
        ..pageContext = null;
      Speech.instance.enabled = false;
    });

    tearDown(() async {
      Assistant.instance
        ..dismiss()
        ..client = previousClient
        ..webSearch = previousSearch
        ..history.clear();
      Speech.instance.enabled = true;
      TvStore.instance.updateAssistant(const AiConfig());
      await fake.server.close(force: true);
    });

    test('HTML bo‘sh bo‘lsa — lite manzil', () async {
      fake.html = '<html><body>Hech narsa</body></html>';
      final hits = await InternetSearch(
        endpoint: '${fake.base}/html/',
        liteEndpoint: '${fake.base}/lite/',
      ).search('dollar kursi');
      expect(hits.single.site, 'gazeta.uz');
      expect(fake.searches.map((u) => u.path), ['/html/', '/lite/']);
      expect(fake.searches.first.queryParameters['q'], 'dollar kursi');
    });

    test('bepul GPT savoldan oldin internetdan qidiradi', () async {
      TvStore.instance.updateAssistant(const AiConfig(voice: false));
      await Assistant.instance.ask('Toshkentdagi eng baland inshoot qaysi?');
      expect(Assistant.instance.state.value.answer, 'Teleminora 375 metr.');
      expect(fake.searches, hasLength(1));
      final system =
          ((fake.ai.single['messages'] as List).first as Map)['content']
              as String;
      expect(system, contains('Internetdan hozir topilgan'));
      expect(system, contains('375 metr'));
      // Foydalanuvchi savoli o‘zgarmay qoladi.
      final user =
          ((fake.ai.single['messages'] as List).last as Map)['content'];
      expect(user, 'Toshkentdagi eng baland inshoot qaysi?');
    });

    test('qidiruv o‘chiq yoki Gemini — DuckDuckGo chaqirilmaydi', () async {
      TvStore.instance.updateAssistant(
        const AiConfig(voice: false, webSearch: false),
      );
      await Assistant.instance.ask('Toshkentdagi eng baland inshoot qaysi?');
      expect(fake.searches, isEmpty);

      TvStore.instance.updateAssistant(
        const AiConfig(
          provider: AiProvider.gemini,
          voice: false,
        ).copyWith(key: 'k'),
      );
      await Assistant.instance.ask('Toshkentdagi eng baland inshoot qaysi?');
      expect(fake.searches, isEmpty);
      expect(Assistant.instance.state.value.answer, 'Gemini javobi.');
    });

    test('ochiq sahifa haqidagi savolda qidirilmaydi', () async {
      TvStore.instance.updateAssistant(const AiConfig(voice: false));
      Assistant.instance.pageContext = () async => 'Sahifa\nhttps://a.uz\nMatn';
      await Assistant.instance.ask('Bu sahifa nima haqida?');
      expect(fake.searches, isEmpty);
      expect(fake.ai, hasLength(1));
    });

    test('qidiruv ishlamasa ham javob beriladi', () async {
      fake.html = 'x';
      fake.lite = 'y';
      TvStore.instance.updateAssistant(const AiConfig(voice: false));
      await Assistant.instance.ask('Toshkentdagi eng baland inshoot qaysi?');
      expect(Assistant.instance.state.value.answer, 'Teleminora 375 metr.');
      final system =
          ((fake.ai.single['messages'] as List).first as Map)['content']
              as String;
      expect(system, isNot(contains('Internetdan hozir topilgan')));
    });
  });
}
