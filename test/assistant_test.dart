import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/assistant/ai.dart';
import 'package:telefon_tv/tv/assistant/assistant.dart';
import 'package:telefon_tv/tv/assistant/intents.dart';
import 'package:telefon_tv/tv/assistant/tts.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/m3u.dart';
import 'package:telefon_tv/tv/model.dart';
import 'package:telefon_tv/tv/radio.dart';
import 'package:telefon_tv/tv/screens/browser_screen.dart';
import 'package:telefon_tv/tv/server.dart';
import 'package:telefon_tv/tv/sites.dart';
import 'package:telefon_tv/tv/store.dart';

/// Soxta AI server: so‘rovlarni yozib oladi va tayyor javob qaytaradi.
class FakeAi {
  late HttpServer server;
  final requests =
      <(String path, Map<String, Object?> body, HttpHeaders headers)>[];
  Future<void> Function(HttpRequest req, Map<String, Object?> body)? handler;

  String get base => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final text = await utf8.decoder.bind(req).join();
      final body = text.isEmpty
          ? <String, Object?>{}
          : jsonDecode(text) as Map<String, Object?>;
      requests.add((req.uri.path, body, req.headers));
      await handler!(req, body);
    });
  }

  static Future<void> sse(HttpRequest req, List<Object> events) async {
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events) {
      req.response.write('data: ${e is String ? e : jsonEncode(e)}\n\n');
      await req.response.flush();
    }
    await req.response.close();
  }

  static Map<String, Object?> gemini(String text) => {
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            {'text': text},
          ],
        },
      },
    ],
  };

  static Map<String, Object?> openAi(String text) => {
    'choices': [
      {
        'delta': {'content': text},
      },
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Soxta serverlarga haqiqiy HTTP so‘rov yuborilsin.
  HttpOverrides.global = null;

  test('o‘zbekcha kirill va shevadagi ovoz buyruqlari', () {
    expect(detectLang('Овозни пасайтир'), 'uz');
    expect(detectLang('Нима учун осмон кўк?'), 'uz');
    expect(detectLang('Сделай тише'), 'ru');
    expect(
      (understand('Овозни пасайтир')!.action as RemoteCmd).cmd,
      Cmd.volDown,
    );
    expect(
      (understand('ovozini paslat')!.action as RemoteCmd).cmd,
      Cmd.volDown,
    );
    expect(
      (understand('Севимли ТВни қўй', channels: ['Sevimli TV'])!.action
              as PlayChannel)
          .index,
      0,
    );
    expect(
      uzbekToLatin('Ўзбекистон, Қўқон, Шаҳрисабз'),
      'O‘zbekiston, Qo‘qon, Shahrisabz',
    );
  });

  test('javob tili o‘zbekcha, avtomatik rejim alohida tanlanadi', () async {
    final store = TvStore.instance;
    await store.load();
    final original = store.assistant.value;
    Speech.instance.enabled = false;
    await store.updateAssistant(const AiConfig(voice: false));
    await Assistant.instance.ask('который час');
    expect(Assistant.instance.state.value.answer, startsWith('Soat '));
    expect(
      Assistant.instance.systemPrompt(),
      contains('Asosiy til — o‘zbekcha'),
    );
    await store.updateAssistant(const AiConfig(voice: false, language: 'auto'));
    await Assistant.instance.ask('который час');
    expect(Assistant.instance.state.value.answer, startsWith('Сейчас '));
    expect(AiConfig.fromJson({}).language, 'uz');
    expect(
      AiConfig.fromJson(const AiConfig(language: 'en').toJson()).language,
      'en',
    );
    await store.updateAssistant(original);
    Assistant.instance.dismiss();
    Speech.instance.enabled = true;
  });

  test(
    'talaffuz uchun haqiqiy o‘zbek ovozining yuqori sifatlisi tanlanadi',
    () {
      final voice = selectUzbekVoice([
        {'name': 'Turkish', 'locale': 'tr-TR', 'quality': '500'},
        {'name': 'Uzbek standard', 'locale': 'uz-UZ', 'quality': '300'},
        {'name': 'Uzbek high', 'locale': 'uz-UZ', 'quality': '500'},
      ]);
      expect(voice!['name'], 'Uzbek high');
      expect(
        selectUzbekVoice([
          {'name': 'Turkish', 'locale': 'tr-TR'},
        ]),
        isNull,
      );
    },
  );

  group('buyruqlarni internetsiz tushunadi', () {
    T action<T>(String text, {List<String> channels = const []}) {
      final u = understand(text, channels: channels);
      expect(u, isNotNull, reason: text);
      expect(u!.action, isA<T>(), reason: text);
      return u.action as T;
    }

    test('YouTube', () {
      expect(action<YoutubeSearch>('YouTube’ni och').query, '');
      expect(
        action<YoutubeSearch>('youtubeda multfilm qo‘y').query,
        contains('multfilm'),
      );
      expect(action<YoutubeSearch>('найди на ютубе новости').query, 'новости');
      expect(action<YoutubeSearch>('play cats on youtube').query, 'cats');
    });

    test('ovoz, pauza, kanal almashtirish', () {
      expect(action<RemoteCmd>('ovozni ko‘tar').cmd, Cmd.volUp);
      expect(action<RemoteCmd>('ovozni pasaytir').cmd, Cmd.volDown);
      expect(action<RemoteCmd>('сделай громче').cmd, Cmd.volUp);
      expect(action<RemoteCmd>('ovozsiz').cmd, Cmd.mute);
      expect(action<RemoteCmd>('pauza').cmd, Cmd.playPause);
      expect(action<RemoteCmd>('keyingi kanal').cmd, Cmd.next);
      expect(action<RemoteCmd>('ovozni ancha ko‘tar').times, 4);
    });

    test('telefondagi internetsiz model yozgan matn (ʻ, nuqta)', () {
      // NVIDIA FastConformer natijasi: katta harf, U+02BB va tinish belgisi.
      expect(action<RemoteCmd>('Ovozni biroz pasaytir.').cmd, Cmd.volDown);
      expect(action<RemoteCmd>('Ovozni koʻtar.').cmd, Cmd.volUp);
      expect(
        action<YoutubeSearch>('Youtubeda oʻzbekcha qoʻshiq qoʻy.').query,
        contains('qo'),
      );
    });

    test('kanal nomi bilan', () {
      final c = action<PlayChannel>(
        'Sevimli TV ni qo‘y',
        channels: ['Zo‘r TV', 'Sevimli TV', 'Milliy TV'],
      );
      expect(c.name, 'Sevimli TV');
      expect(c.index, 1);
      expect(
        action<PlayChannel>(
          'включи канал Milliy',
          channels: ['Zo‘r TV', 'Milliy TV'],
        ).name,
        'Milliy TV',
      );
    });

    test('saytlar, qidiruv, ekranlar, vaqt, ob-havo', () {
      expect(action<OpenSite>('ivi ni och').site.id, 'ivi');
      expect(action<OpenSite>('открой кинопоиск').site.id, 'kinopoisk');
      expect(action<OpenSite>('uzmovi').site.id, 'uzmovi');
      expect(
        action<WebSearch>('internetdan Toshkent metro xaritasini qidir').query,
        contains('Toshkent'),
      );
      expect(action<OpenPlace>('jonli tv').place, TvPlace.live);
      expect(action<OpenPlace>('radio qo‘y').place, TvPlace.radio);
      expect(action<OpenPlace>('sozlamalarni och').place, TvPlace.settings);
      expect(action<TellInfo>('soat necha').kind, InfoKind.time);
      expect(action<TellInfo>('какое сегодня число').kind, InfoKind.date);
      final w = action<TellInfo>('Samarqandda ob-havo qanday');
      expect(w.kind, InfoKind.weather);
      expect(w.city, 1);
    });

    test('savollar AI’ga ketadi', () {
      expect(understand('Messi necha yoshda?'), isNull);
      expect(understand('Kim birinchi bo‘lib Oyga chiqqan?'), isNull);
      expect(understand('расскажи анекдот'), isNull);
      expect(understand('ertaga ob-havo qanday bo‘ladi'), isNull);
    });

    test('til aniqlanadi', () {
      expect(detectLang('ovozni ko‘tar'), 'uz');
      expect(detectLang('сделай громче'), 'ru');
      expect(detectLang('what time is it'), 'en');
    });
  });

  test('AI javobidagi buyruq ajratiladi va ekranda ko‘rinmaydi', () {
    const reply = 'Mana, topdim!\n[[youtube: Shahzoda qo‘shiqlari]]';
    expect(visibleAnswer(reply), 'Mana, topdim!');
    expect(visibleAnswer('Bir lahza [[you'), 'Bir lahza');
    expect(
      (actionFromTag(reply) as YoutubeSearch).query,
      'Shahzoda qo‘shiqlari',
    );
    expect(
      (actionFromTag('[[web: dollar kursi]]') as WebSearch).query,
      'dollar kursi',
    );
    expect(
      (actionFromTag('[[open: kun.uz]]') as OpenSite).site.url,
      'https://kun.uz',
    );
    expect(actionFromTag('oddiy javob'), isNull);
  });

  test('turkcha ovoz o‘zbekcha o‘qishi uchun yozuv', () {
    expect(
      uzbekForTurkishVoice('Shahar chiroyli, qo‘shiq'),
      'Şahar çiroyli, koşik',
    );
    expect(spokenText('Salom [[web: x]] https://a.uz *ok*'), 'Salom ok');
  });

  group('bepul AI xizmatlari', () {
    late FakeAi fake;
    setUp(() async {
      fake = FakeAi();
      await fake.start();
    });
    tearDown(() => fake.server.close(force: true));

    test('Gemini: kalit sarlavhada, javob oqim bo‘lib keladi', () async {
      fake.handler = (req, body) => FakeAi.sse(req, [
        FakeAi.gemini('Salom, '),
        FakeAi.gemini('men yordamchiman.'),
      ]);
      final client = AiClient(geminiBase: fake.base);
      final cfg = const AiConfig(
        provider: AiProvider.gemini,
      ).copyWith(key: 'kalit123');
      final parts = await client
          .chat(
            cfg,
            system: 'tizim',
            turns: const [AiTurn(user: true, text: 'salom')],
          )
          .toList();
      expect(parts.join(), 'Salom, men yordamchiman.');
      final (path, body, headers) = fake.requests.single;
      expect(path, '/models/gemini-flash-latest:streamGenerateContent');
      expect(headers.value('x-goog-api-key'), 'kalit123');
      expect((body['systemInstruction'] as Map)['parts'], [
        {'text': 'tizim'},
      ]);
      expect(body['tools'], isNotNull, reason: 'Google qidiruvi yoniq');
    });

    test('Gemini: bepul limit tugasa — keyingi model', () async {
      fake.handler = (req, body) async {
        if (req.uri.path.contains('gemini-flash-latest')) {
          req.response.statusCode = 429;
          req.response.write(
            jsonEncode({
              'error': {'message': 'quota'},
            }),
          );
          await req.response.close();
          return;
        }
        await FakeAi.sse(req, [FakeAi.gemini('lite javob')]);
      };
      final client = AiClient(geminiBase: fake.base);
      final cfg = const AiConfig(
        provider: AiProvider.gemini,
        webSearch: false,
      ).copyWith(key: 'k');
      final text =
          (await client
                  .chat(
                    cfg,
                    system: 's',
                    turns: const [AiTurn(user: true, text: 'q')],
                  )
                  .toList())
              .join();
      expect(text, 'lite javob');
      expect(fake.requests.last.$1, contains('gemini-flash-lite-latest'));
    });

    test('Gemini: kalit noto‘g‘ri — boshqa modelga urinmaydi', () async {
      fake.handler = (req, body) async {
        req.response.statusCode = 400;
        req.response.write(
          jsonEncode({
            'error': {
              'message': 'API key not valid. Please pass a valid API key.',
            },
          }),
        );
        await req.response.close();
      };
      final client = AiClient(geminiBase: fake.base);
      final cfg = const AiConfig(
        provider: AiProvider.gemini,
        webSearch: false,
      ).copyWith(key: 'bad');
      await expectLater(
        client
            .chat(
              cfg,
              system: 's',
              turns: const [AiTurn(user: true, text: 'q')],
            )
            .toList(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('kaliti'),
          ),
        ),
      );
      expect(fake.requests, hasLength(1));
    });

    test('kalitsiz (OpenAI-mos) oqim', () async {
      fake.handler = (req, body) => FakeAi.sse(req, [
        FakeAi.openAi('Bepul '),
        FakeAi.openAi('javob'),
        '[DONE]',
      ]);
      final client = AiClient(freeEndpoint: '${fake.base}/openai');
      final text =
          (await client
                  .chat(
                    const AiConfig(),
                    system: 's',
                    turns: const [AiTurn(user: true, text: 'q')],
                  )
                  .toList())
              .join();
      expect(text, 'Bepul javob');
      final body = fake.requests.single.$2;
      expect(body['stream'], true);
      expect((body['messages'] as List).first, {
        'role': 'system',
        'content': 's',
      });
      expect(fake.requests.single.$3.value('authorization'), isNull);
    });

    test('kalit kiritilmagan — tushunarli xabar', () async {
      await expectLater(
        AiClient()
            .chat(
              const AiConfig(provider: AiProvider.groq),
              system: 's',
              turns: const [AiTurn(user: true, text: 'q')],
            )
            .toList(),
        throwsA(isA<AiException>()),
      );
    });

    test('yordamchi: AI javobi va undagi buyruq', () async {
      Speech.instance.enabled = false;
      fake.handler = (req, body) => FakeAi.sse(req, [
        FakeAi.gemini('Hozir topib beraman.\n[[web: Toshkent ob-havo]]'),
      ]);
      TvStore.instance.updateAssistant(
        const AiConfig(
          provider: AiProvider.gemini,
          webSearch: false,
          voice: false,
        ).copyWith(key: 'k'),
      );
      final a = Assistant.instance..client = AiClient(geminiBase: fake.base);
      a.history.clear();
      await a.ask('Toshkentning eng baland binosi qaysi?');
      expect(a.state.value.phase, AssistPhase.done);
      expect(a.state.value.answer, 'Hozir topib beraman.');
      expect(a.history.last.text, 'Hozir topib beraman.');
      final system =
          (fake.requests.single.$2['systemInstruction'] as Map)['parts']
              as List;
      expect((system.first as Map)['text'], contains('z3wax TV'));
      a.dismiss();
    });

    test('yordamchi: oddiy buyruq AI’siz, darhol', () async {
      Speech.instance.enabled = false;
      fake.handler = (req, body) async => fail('AI chaqirilmasligi kerak');
      final a = Assistant.instance..client = AiClient(geminiBase: fake.base);
      await a.ask(
        'Salom, sen menga televizorda nimalar qilishga yordam bera olasan?',
      );
      expect(a.state.value.answer, contains('Kanal qo‘yish'));
      expect(fake.requests, isEmpty);
      await a.ask('soat necha');
      expect(a.state.value.phase, AssistPhase.done);
      expect(a.state.value.answer, startsWith('Soat '));
      expect(fake.requests, isEmpty);
      a.dismiss();
    });
  });

  test('kanallar: sifat, bir xil kanal manbalari, geo-blok', () {
    final raw = parseM3u('''
#EXTM3U
#EXTINF:-1 group-title="O‘zbekiston",Sevimli TV (576p)
http://a/sevimli.m3u8
#EXTINF:-1 group-title="O‘zbekiston",Sevimli TV (1080p)
http://b/sevimli.m3u8
#EXTINF:-1 group-title="O‘zbekiston",Zo‘r TV (720p) [Not 24/7]
http://a/zor.m3u8
#EXTINF:-1 group-title="Kino",Kino 4K (2160p)
http://a/kino.m3u8
#EXTINF:-1 group-title="Kino",Blocked (1080p) [Geo-blocked]
http://a/blocked.m3u8
''');
    final r = organizeChannels(raw);
    expect(r.channels.map((c) => c.title), [
      'Sevimli TV',
      'Zo‘r TV',
      'Kino 4K',
    ]);
    final sevimli = r.channels.first;
    expect(sevimli.source, 'http://b/sevimli.m3u8');
    expect(sevimli.quality, 1080);
    expect(sevimli.qualityLabel, 'FHD');
    expect(r.alternates['http://b/sevimli.m3u8'], ['http://a/sevimli.m3u8']);
    expect(r.channels.last.qualityLabel, '4K');
    // Saqlangan matndan qayta o‘qilganda ham xuddi shunday.
    expect(organizeChannels(parseM3u(toM3u(raw))).channels.length, 3);
  });

  test('to‘plamlar: bittasi ochilmasa ham qolganlari yuklanadi', () async {
    final store = TvStore.instance;
    final n = await store.loadPacks(
      ids: {'uz', 'movies'},
      extraUrl: '',
      fetch: (url) async {
        if (url.contains('movies')) throw const SocketException('yo‘q');
        return '#EXTM3U\n#EXTINF:-1,Milliy TV (1080p)\nhttp://x/milliy.m3u8\n';
      },
    );
    expect(n, 1);
    expect(store.channels.value.single.group, 'O‘zbekiston');
    expect(store.channels.value.single.title, 'Milliy TV');
  });

  test(
    'radio: Radio Browser javobi, ishlamagan server o‘tkazib yuboriladi',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        expect(req.uri.queryParameters['countrycode'], 'UZ');
        expect(req.uri.queryParameters['hidebroken'], 'true');
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode([
            {
              'name': 'Oriat FM',
              'url_resolved': 'https://radio.example/oriat.mp3',
              'favicon': 'https://radio.example/logo.png',
              'country': 'Uzbekistan',
              'bitrate': 128,
              'codec': 'MP3',
            },
            {'name': 'Oriat FM', 'url_resolved': 'https://dup.example/x.mp3'},
            {'name': 'Buzilgan', 'url_resolved': ''},
          ]),
        );
        await req.response.close();
      });
      final dir = RadioDirectory(
        servers: ['http://127.0.0.1:1', 'http://127.0.0.1:${server.port}'],
      );
      final list = await dir.section(RadioDirectory.sections.first.$2);
      expect(list, hasLength(1));
      expect(list.single.title, 'Oriat FM');
      expect(list.single.kind, MediaKind.audio);
      expect(list.single.logo, 'https://radio.example/logo.png');
      expect(list.single.group, contains('128 kbit/s'));
      await server.close(force: true);
    },
  );

  test('pult serveri: savol, mikrofon holati; sichqoncha yo‘q', () async {
    final asks = <String>[];
    final listens = <String>[];
    final commands = <Cmd>[];
    final server = RemoteServer(
      port: 0,
      keyProvider: () => '1234',
      onCommand: commands.add,
      onText: (_) {},
      onMedia: (_) {},
      onAsk: asks.add,
      onListen: (p, t) => listens.add('$p:$t'),
    );
    await server.start();
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${server.boundPort}/ws?k=1234',
    );
    ws
      ..add(jsonEncode({'t': 'listen', 'phase': 'start'}))
      ..add(jsonEncode({'t': 'listen', 'phase': 'partial', 'v': 'ob-ha'}))
      ..add(jsonEncode({'t': 'ask', 'v': '  ob-havo qanday '}))
      ..add(jsonEncode({'t': 'ask', 'v': '   '}))
      // Eski pult ilovasining sichqoncha xabari e’tiborsiz qoladi.
      ..add(jsonEncode({'t': 'move', 'dx': 12, 'dy': -5000}))
      ..add(jsonEncode({'t': 'cmd', 'c': 'down'}));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(listens, ['start:', 'partial:ob-ha']);
    expect(asks, ['ob-havo qanday']);
    expect(commands, [Cmd.down]);
    await ws.close();
    await server.stop();
  });

  test('AI brauzer o‘qish rejimi: matn va havolalar', () {
    final blocks = readerTextsForTest(
      'https://html.duckduckgo.com/html/?q=x',
      '''
<html><head><title>Natijalar</title><script>alert(1)</script></head><body>
<nav><a href="/menu">Menyu</a></nav>
<h2>Toshkent</h2>
<p>Toshkent — O‘zbekistonning poytaxti va eng katta shahri.</p>
<div class="result"><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fuz.wikipedia.org%2Fwiki%2FToshkent">Toshkent — Vikipediya</a></div>
</body></html>''',
    );
    expect(blocks, [
      'Toshkent',
      'Toshkent — O‘zbekistonning poytaxti va eng katta shahri.',
      'Toshkent — Vikipediya -> https://uz.wikipedia.org/wiki/Toshkent',
    ]);
  });

  test('sayt manzili to‘g‘rilanadi', () {
    expect(normalizeUrl('idub.tv'), 'https://idub.tv');
    expect(normalizeUrl(' https://ivi.tv/uz '), 'https://ivi.tv/uz');
    expect(normalizeUrl('salom dunyo'), isNull);
    expect(normalizeUrl(''), isNull);
  });
}
