import 'package:flutter/foundation.dart';

import '../input.dart';
import '../sites.dart';
import '../weather.dart';

/// Televizordagi joylar (ovoz bilan ochiladi).
enum TvPlace {
  home,
  live,
  radio,
  favorites,
  videos,
  photos,
  music,
  settings,
  pair,
  apps,
  browser,
  player,
  assistantSettings,
  sleep,
}

enum InfoKind { time, date, weather }

sealed class AssistAction {
  const AssistAction();
}

class OpenPlace extends AssistAction {
  const OpenPlace(this.place);
  final TvPlace place;
}

class OpenSite extends AssistAction {
  const OpenSite(this.site);
  final Site site;
}

class WebSearch extends AssistAction {
  const WebSearch(this.query);
  final String query;
}

/// Bo‘sh so‘rov — YouTube’ning o‘zi ochiladi.
class YoutubeSearch extends AssistAction {
  const YoutubeSearch(this.query);
  final String query;
}

class PlayChannel extends AssistAction {
  const PlayChannel(this.index, this.name);
  final int index;
  final String name;
}

class RemoteCmd extends AssistAction {
  const RemoteCmd(this.cmd, [this.times = 1]);
  final Cmd cmd;
  final int times;
}

class TellInfo extends AssistAction {
  const TellInfo(this.kind, {this.city});
  final InfoKind kind;

  /// [cities] ro‘yxatidagi shahar; null — sozlamalardagi shahar.
  final int? city;
}

/// Internetsiz, darhol tushunilgan buyruq.
@immutable
class Understood {
  const Understood(this.action, this.lang);
  final AssistAction action;

  /// Javob tili: uz / ru / en.
  final String lang;
}

/// Matn tili: kirillcha — rus, inglizcha so‘zlar — en, aks holda o‘zbek.
String detectLang(String text) {
  final t = text.toLowerCase();
  if (RegExp('[ўқғҳ]').hasMatch(t)) return 'uz';
  if (RegExp('[а-яё]').hasMatch(t)) return 'ru';
  final uz = RegExp(
    r"\b(va|bu|uchun|nima|qanday|qayer|qachon|kim|och|qo'y|menga|bilan|emas|ham|ni|da|qil)\b|o'|g'|[ʻ‘’]",
  ).hasMatch(t);
  if (uz) return 'uz';
  final en = RegExp(
    r"\b(the|what|who|how|when|where|open|play|show|turn|is|are|please|search|weather|time)\b",
  ).hasMatch(t);
  return en ? 'en' : 'uz';
}

String say(String lang, String uz, String ru, String en) =>
    lang == 'ru' ? ru : (lang == 'en' ? en : uz);

/// Kichik harf, bitta xil apostrof, tinish belgilarsiz.
String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[‘’ʻʼ`´]'), "'")
    .replaceAll(RegExp(r'''[.,!?;:«»"“”()\-–—]'''), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Apostrofsiz shakl: “ko‘tar” → “kotar” (nutqni tanish ba’zan tushirib qoldiradi).
String flatten(String s) => normalize(s).replaceAll("'", '');

const _fillers = [
  'iltimos', 'пожалуйста', 'please', 'menga', 'мне', 'hey', 'salom', //
  'siri', 'telefon tv', 'yordamchi', 'привет', 'эй',
];

const _openVerbs = [
  'och',
  'ochib ber',
  'ochib',
  'oching',
  'qoy',
  'qoying',
  'yoq',
  'yoqib ber',
  'korsat',
  'korsating',
  'kirit',
  'kir',
  'otkaz',
  'ber',
  'открой',
  'открыть',
  'включи',
  'включить',
  'покажи',
  'запусти',
  'поставь',
  'open',
  'play',
  'show',
  'start',
  'launch',
  'put on',
  'turn on',
  'go to',
  'watch',
  'korish',
  'tomosha',
  'qil',
];

const _searchVerbs = [
  'qidir',
  'qidiring',
  'qidirib ber',
  'izla',
  'izlab ber',
  'top',
  'topib ber',
  'найди',
  'поищи',
  'загугли',
  'ищи',
  'search for',
  'search',
  'look up',
  'find',
  'google',
];

bool _anyIn(String padded, List<String> keys) =>
    keys.any((k) => padded.contains(k));

bool _wordIn(String padded, List<String> words) =>
    words.any((w) => padded.contains(' $w '));

/// So‘rovdan fe’l, to‘ldiruvchi va kalit so‘zlarni olib, qolganini qaytaradi.
String _rest(String text, List<String> remove) {
  var f = ' ${flatten(text)} ';
  final sorted = [...remove]..sort((a, b) => b.length.compareTo(a.length));
  for (final w in sorted) {
    f = f.replaceAll(' $w ', ' ');
  }
  // Kelishik qo‘shimchalari yopishgan qolgan bo‘laklar.
  return f.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Matndagi asl so‘zlar (katta-kichik harf va apostrof saqlanadi) —
/// qidiruv uchun chiroyliroq. [drop] — apostrofsiz kichik harfdagi so‘zlar.
String _restOriginal(String text, Set<String> drop) {
  final words = text
      .replaceAll(RegExp('[‘’ʻʼ`´]'), "'")
      .replaceAll(RegExp(r'''[.,!?;:«»"“”()]'''), ' ')
      .split(RegExp(r'\s+'));
  final kept = <String>[];
  for (final w in words) {
    if (w.isEmpty) continue;
    final f = w.toLowerCase().replaceAll("'", '');
    if (drop.contains(f)) continue;
    kept.add(w);
  }
  return kept.join(' ').trim();
}

const _youtube = ['youtube', 'yutub', 'youtub', 'ютуб', 'ютюб', 'you tube'];

const _cityRu = {
  'ташкент': 0,
  'самарканд': 1,
  'бухар': 2,
  'андижан': 3,
  'фергана': 4,
  'наманган': 5,
  'карши': 6,
  'нукус': 7,
  'термез': 8,
  'ургенч': 9,
  'навои': 10,
  'джизак': 11,
  'гулистан': 12,
};

int? _city(String f) {
  for (var i = 0; i < cities.length; i++) {
    final name = flatten(cities[i].name);
    final stem = name.length > 5 ? name.substring(0, name.length - 1) : name;
    if (f.contains(stem)) return i;
  }
  for (final e in _cityRu.entries) {
    if (f.contains(e.key)) return e.value;
  }
  return null;
}

/// Oddiy buyruqlarni internetsiz, darhol tushunadi. Tushunilmasa — null
/// (savol AI’ga yuboriladi).
Understood? understand(
  String raw, {
  List<String> channels = const [],
  List<Site> sites = defaultSites,
}) {
  final lang = detectLang(raw);
  var f = flatten(raw);
  for (final w in _fillers) {
    f = ' $f '.replaceAll(' $w ', ' ').trim();
  }
  if (f.isEmpty) return null;
  final p = ' $f ';
  Understood ok(AssistAction a) => Understood(a, lang);
  final words = f.split(' ').length;
  final strong = _anyIn(p, const [
    'ancha',
    'juda',
    'сильно',
    'намного',
    'much',
    'a lot',
  ]);

  // Savol bo‘lsa (nima, qachon, kim…) va boshqarish fe’li bo‘lmasa — AI javob beradi.
  final question = _wordIn(p, const [
    'nima',
    'nimalar',
    'qachon',
    'kim',
    'nega',
    'nechta',
    'qaysi',
    'qanaqa',
    'что',
    'когда',
    'кто',
    'почему',
    'зачем',
    'сколько',
    'какой',
    'какая',
    'what',
    'when',
    'who',
    'why',
    'how',
    'which',
  ]);

  // ---- Ovoz ----
  if (_anyIn(p, const [
    'ovozsiz',
    'ovozni ochir',
    'ovozini ochir',
    'jim bol',
    'выключи звук',
    'без звука',
    'отключи звук',
    'убери звук',
    ' mute',
    'sound off',
  ])) {
    return ok(const RemoteCmd(Cmd.mute));
  }
  final volUp =
      (p.contains('ovoz') &&
          _anyIn(p, const [
            'kotar',
            'balandla',
            'oshir',
            'baland',
            'kuchaytir',
            'qoshib',
          ])) ||
      _anyIn(p, const [
        'громче',
        'прибавь',
        'увеличь звук',
        'volume up',
        'louder',
        'turn it up',
        'turn up',
      ]);
  if (volUp) return ok(RemoteCmd(Cmd.volUp, strong ? 4 : 2));
  final volDown =
      (p.contains('ovoz') &&
          _anyIn(p, const ['pasay', 'kamay', 'past', 'sekin', 'tushir'])) ||
      _anyIn(p, const [
        'тише',
        'убавь',
        'уменьши звук',
        'volume down',
        'quieter',
        'turn it down',
        'turn down',
      ]);
  if (volDown) return ok(RemoteCmd(Cmd.volDown, strong ? 4 : 2));

  // ---- Vaqt, sana, ob-havo ----
  if (_anyIn(p, const [
    'soat necha',
    'soat nechchi',
    'hozir soat',
    'vaqt necha',
    'который час',
    'сколько времени',
    'what time',
    'the time',
  ])) {
    return ok(const TellInfo(InfoKind.time));
  }
  if (_anyIn(p, const [
    'bugun necha',
    'bugun nechanchi',
    'nechanchi sana',
    'qaysi kun',
    'bugun qanday kun',
    ' sana ',
    'какое сегодня число',
    'какой сегодня день',
    'какое число',
    'what day',
    'the date',
    "what's today",
    'whats today',
  ])) {
    return ok(const TellInfo(InfoKind.date));
  }
  if (_anyIn(p, const [
    'ob havo',
    'obhavo',
    'havo qanday',
    'harorat',
    'погода',
    'погоду',
    'температура',
    'weather',
    'temperature',
  ])) {
    // Ertangi ob-havo — AI (Google qidiruvi) aniqroq aytadi.
    if (!_anyIn(p, const [
      'ertaga',
      'hafta',
      'завтра',
      'недел',
      'tomorrow',
      'week',
    ])) {
      return ok(TellInfo(InfoKind.weather, city: _city(f)));
    }
  }

  // ---- Ijro ----
  if (_anyIn(p, const [
    ' pauza',
    'toxtat',
    'pauzaga',
    'пауза',
    'останови',
    'стоп',
    ' pause',
    ' stop ',
  ])) {
    return ok(const RemoteCmd(Cmd.playPause));
  }
  if (_anyIn(p, const [
    'davom et',
    'davom ettir',
    'продолжи',
    'resume',
    'continue playing',
  ])) {
    return ok(const RemoteCmd(Cmd.playPause));
  }
  if (_anyIn(p, const ['keyingi', 'следующ', 'дальше', ' next '])) {
    return ok(const RemoteCmd(Cmd.next));
  }
  if (_anyIn(p, const ['oldingi', 'предыдущ', ' previous', ' prev '])) {
    return ok(const RemoteCmd(Cmd.prev));
  }
  if (const [
    'orqaga',
    'orqaga qayt',
    'назад',
    'вернись',
    'go back',
    'back',
  ].contains(f)) {
    return ok(const RemoteCmd(Cmd.back));
  }
  if (_anyIn(p, const [
        'bosh sahifa',
        'bosh ekran',
        'asosiy sahifa',
        'asosiy ekran',
        'домой',
        'на главную',
        'главный экран',
        'home screen',
        'go home',
      ]) ||
      f == 'home') {
    return ok(const OpenPlace(TvPlace.home));
  }

  // ---- YouTube ----
  if (_anyIn(p, _youtube)) {
    final drop = <String>{
      ..._openVerbs.where((v) => !v.contains(' ')),
      ..._searchVerbs.where((v) => !v.contains(' ')),
      'da',
      'dan',
      'ga',
      'ni',
      'на',
      'в',
      'с',
      'for',
      'on',
      'in',
      'me',
      'video',
      'videoni',
      'видео',
      'ролик',
    };
    final text = normalize(raw)
        .split(' ')
        .where((w) {
          final x = w.replaceAll("'", '');
          return !_youtube.any(x.startsWith);
        })
        .join(' ');
    final q = _restOriginal(text, drop);
    return ok(YoutubeSearch(q));
  }

  // ---- Kino saytlari ----
  for (final s in sites) {
    final keys = {s.name.toLowerCase(), ...s.aliases};
    if (keys.any(
      (k) => k.length >= 3 && (p.contains(' $k ') || p.contains(' $k')),
    )) {
      if (!question || _anyIn(p, _openVerbs.map((v) => ' $v').toList())) {
        return ok(OpenSite(s));
      }
    }
  }

  // ---- Internetdan qidirish ----
  if (_anyIn(p, _searchVerbs.map((v) => ' $v').toList())) {
    final q = _rest(f, const [
      ..._searchVerbs,
      'internetdan',
      'internetda',
      'internet',
      'googleda',
      'googledan',
      'gugl',
      'гугл',
      'гугле',
      'в',
      'интернете',
      'интернет',
      'on',
      'the',
      'internet',
      'web',
      'brauzerda',
      'браузере',
    ]);
    if (q.isEmpty) return ok(const OpenPlace(TvPlace.browser));
    return ok(
      WebSearch(
        _restOriginal(raw, {
          ..._searchVerbs.where((v) => !v.contains(' ')),
          'internetdan',
          'internetda',
          'googleda',
          'googledan',
          'gugl',
          'гугл',
          'в',
          'интернете',
          'on',
          'the',
          'internet',
          'web',
          ..._fillers,
        }),
      ),
    );
  }

  // ---- Jonli kanallar ----
  final verb =
      _anyIn(p, _openVerbs.map((v) => ' $v').toList()) ||
      _anyIn(p, const ['kanal', 'канал', 'channel']);
  var best = -1;
  var bestLen = 0;
  for (var i = 0; i < channels.length; i++) {
    final name = flatten(channels[i]);
    final short = name.replaceAll(RegExp(r'\s*(tv|тв|hd|uz)$'), '').trim();
    for (final n in {name, short}) {
      if (n.length < 3) continue;
      if (p.contains(' $n ') || (p.contains(' $n') && n.length >= 5)) {
        if (n.length > bestLen) {
          best = i;
          bestLen = n.length;
        }
      }
    }
  }
  if (best >= 0 && (verb || words <= bestLen ~/ 3 + 2) && !question) {
    return ok(PlayChannel(best, channels[best]));
  }
  if (_anyIn(p, const [
    'sevimli kanal',
    'избранные каналы',
    'favorite channels',
  ])) {
    return ok(const OpenPlace(TvPlace.favorites));
  }
  if (_anyIn(p, const [
    'jonli tv',
    'jonli efir',
    'telekanal',
    'kanallar',
    'tv kanal',
    'телеканал',
    'каналы',
    'прямой эфир',
    'live tv',
    'tv channels',
  ])) {
    return ok(const OpenPlace(TvPlace.live));
  }

  // ---- Fayllar: “musiqa” — o‘zimizdagi; “Shahzoda qo‘shiqlari” — YouTube ----
  for (final (place, keys) in const [
    (
      TvPlace.videos,
      [
        'filmlar',
        'videolar',
        'kinolar',
        'фильмы',
        'мои видео',
        'my videos',
        'movies',
      ],
    ),
    (
      TvPlace.photos,
      [
        'rasmlar',
        'suratlar',
        'fotolar',
        'фото',
        'фотографии',
        'photos',
        'pictures',
      ],
    ),
    (TvPlace.music, ['musiqa', 'qoshiq', 'музык', 'песн', 'music', 'songs']),
  ]) {
    if (!_anyIn(p, keys)) continue;
    final rest = _rest(f, [
      ..._openVerbs,
      ...keys,
      'mening',
      'meni',
      'мои',
      'my',
      'larni',
      'ni',
      'lar',
    ]);
    final leftover = rest
        .split(' ')
        .where((w) => !keys.any((k) => w.startsWith(k.trim())))
        .join(' ')
        .trim();
    if (leftover.isEmpty) return ok(OpenPlace(place));
    if (place == TvPlace.music || place == TvPlace.videos) {
      return ok(
        YoutubeSearch(
          _restOriginal(raw, {
            ..._openVerbs.where((v) => !v.contains(' ')),
            ..._fillers,
          }),
        ),
      );
    }
  }

  // ---- Ekranlar ----
  for (final (place, keys) in const [
    (
      TvPlace.assistantSettings,
      [
        'yordamchi sozlama',
        'ai sozlama',
        'настройки ассистента',
        'assistant settings',
      ],
    ),
    (TvPlace.radio, ['radio', 'радио']),
    (TvPlace.settings, ['sozlamalar', 'sozlama', 'настройк', 'settings']),
    (
      TvPlace.browser,
      ['brauzer', 'браузер', 'browser', 'internetni och', 'internetga kir'],
    ),
    (
      TvPlace.pair,
      [
        'pult ulash',
        'pultni ulash',
        'qr kod',
        'подключить пульт',
        'pair remote',
      ],
    ),
    (TvPlace.apps, ['ilovalar', 'приложени', ' apps']),
    (
      TvPlace.player,
      ['video pleyer', 'videopleyer', 'pleyer', 'плеер', 'video player'],
    ),
    (
      TvPlace.sleep,
      [
        'ekranni ochir',
        'uxla',
        'uxlash rejim',
        'выключи экран',
        'спящий',
        'sleep',
        'screen off',
      ],
    ),
  ]) {
    if (_anyIn(p, keys) && !question) return ok(OpenPlace(place));
  }
  return null;
}
