import 'dart:async';

import 'package:flutter/material.dart';

import '../input.dart';
import '../model.dart';
import '../screens/apps_screen.dart';
import '../screens/assistant_settings_screen.dart';
import '../screens/browser_screen.dart';
import '../screens/files_screen.dart';
import '../screens/live_screen.dart';
import '../screens/pair_screen.dart';
import '../screens/radio_screen.dart';
import '../screens/player_hub_screen.dart';
import '../screens/player_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sleep_screen.dart';
import '../services.dart';
import '../sites.dart';
import '../store.dart';
import '../weather.dart';
import 'ai.dart';
import 'intents.dart';
import 'tts.dart';

enum AssistPhase { idle, listening, thinking, answering, done, error }

@immutable
class AssistState {
  const AssistState(this.phase, {this.question = '', this.answer = ''});
  final AssistPhase phase;
  final String question;
  final String answer;

  bool get visible => phase != AssistPhase.idle;
}

/// Siri’ga o‘xshash yordamchi: pultdagi mikrofon → shu yerda.
///
/// 1. Oddiy buyruqlar (YouTube, kanal, ovoz, ob-havo, soat, saytlar…)
///    internetsiz, darhol bajariladi.
/// 2. Qolgan savollar — bepul AI (Gemini / Groq / kalitsiz), javob
///    oqim bo‘lib keladi, ekranda va ovozda.
/// 3. Suhbatni eslab qoladi (“uning yoshi nechada?”) va brauzerda ochiq
///    sahifa haqida savolga javob beradi.
class Assistant {
  Assistant._();
  static final instance = Assistant._();

  final state = ValueNotifier<AssistState>(const AssistState(AssistPhase.idle));
  AiClient client = AiClient();
  final history = <AiTurn>[];

  /// Brauzer ochiq bo‘lsa — sahifa nomi, manzili va matni.
  Future<String?> Function()? pageContext;

  Timer? _hide, _listenTimeout;
  int _seq = 0;
  DateTime _lastBroadcast = DateTime(0);
  bool _dispatchingCommand = false;

  /// Ovozli buyruq ochiq ekranga boradi, yordamchi paneliga emas.
  bool get dispatchingCommand => _dispatchingCommand;

  void _set(AssistState s, {bool force = true}) {
    state.value = s;
    _hide?.cancel();
    final now = DateTime.now();
    if (force || now.difference(_lastBroadcast).inMilliseconds > 250) {
      _lastBroadcast = now;
      TvServices.instance.server?.broadcast({
        't': 'assist',
        'phase': s.phase.name,
        'q': s.question,
        'a': s.answer,
      });
    }
    if (s.phase == AssistPhase.done || s.phase == AssistPhase.error) {
      final words = s.answer.split(' ').length;
      _hide = Timer(Duration(seconds: (5 + words ~/ 3).clamp(6, 25)), dismiss);
    }
  }

  void dismiss() {
    _seq++;
    _listenTimeout?.cancel();
    if (state.value.visible) _set(const AssistState(AssistPhase.idle));
  }

  /// Pult mikrofoni: `start` — tinglayapti, `partial` — eshitilgan so‘zlar,
  /// `cancel` — bekor.
  void listen(String phase, String text) {
    _listenTimeout?.cancel();
    switch (phase) {
      case 'start':
      case 'partial':
        _seq++;
        unawaited(Speech.instance.stop());
        _set(
          AssistState(AssistPhase.listening, question: text),
          force: phase == 'start',
        );
        _listenTimeout = Timer(const Duration(seconds: 20), dismiss);
      case 'cancel':
        dismiss();
      case 'error':
        _set(AssistState(AssistPhase.error, answer: text));
    }
  }

  /// Savol yoki buyruq (ovozdan yoki yozib).
  Future<void> ask(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _listenTimeout?.cancel();
    final seq = ++_seq;
    unawaited(Speech.instance.stop());
    _set(AssistState(AssistPhase.thinking, question: text));

    final store = TvStore.instance;
    final u = understand(
      text,
      channels: [for (final c in store.channels.value) c.title],
      sites: store.sites.value,
    );
    if (u != null) {
      final reply = await perform(u.action, u.lang);
      if (seq != _seq) return;
      _finish(text, reply);
      return;
    }
    await _askAi(text, seq);
  }

  List<AiConfig> _chain() {
    final cfg = TvStore.instance.assistant.value;
    final list = [cfg];
    // Asosiy xizmat ishlamasa — kaliti bor boshqa bepul xizmat, oxirida kalitsiz.
    for (final p in [AiProvider.gemini, AiProvider.groq, AiProvider.free]) {
      if (p == cfg.provider) continue;
      final alt = cfg.copyWith(provider: p);
      if (alt.ready) list.add(alt);
    }
    return list;
  }

  Future<void> _askAi(String text, int seq) async {
    String? context;
    try {
      context = await pageContext?.call();
    } catch (_) {}
    final userText = context == null || context.isEmpty
        ? text
        : '$text\n\n[Ekranda ochiq sahifa]\n$context';
    final turns = [
      ...history.length > 10 ? history.sublist(history.length - 10) : history,
      AiTurn(user: true, text: userText),
    ];
    final system = systemPrompt();
    final buf = StringBuffer();
    AiException? firstError;
    for (final cfg in _chain()) {
      try {
        await for (final piece in client.chat(
          cfg,
          system: system,
          turns: turns,
        )) {
          if (seq != _seq) return;
          buf.write(piece);
          _set(
            AssistState(
              AssistPhase.answering,
              question: text,
              answer: visibleAnswer(buf.toString()),
            ),
            force: false,
          );
        }
        if (buf.isNotEmpty) break;
      } on AiException catch (e) {
        if (buf.isNotEmpty) break; // yarmi kelgan bo‘lsa, borini ko‘rsatamiz
        firstError ??= e;
      } catch (_) {
        if (buf.isNotEmpty) break;
        firstError ??= AiException('AI bilan aloqa uzildi.');
      }
      if (seq != _seq) return;
    }
    if (seq != _seq) return;
    final full = buf.toString().trim();
    if (full.isEmpty) {
      _set(
        AssistState(
          AssistPhase.error,
          question: text,
          answer: (firstError ?? AiException('AI javob bermadi.')).message,
        ),
      );
      return;
    }
    final shown = visibleAnswer(full);
    history
      ..add(AiTurn(user: true, text: text))
      ..add(AiTurn(user: false, text: shown));
    while (history.length > 16) {
      history.removeAt(0);
    }
    final action = actionFromTag(full);
    if (action != null) await perform(action, detectLang(text));
    if (seq != _seq) return;
    _finish(text, shown.isEmpty ? '✓' : shown);
  }

  void _finish(String question, String answer) {
    _set(AssistState(AssistPhase.done, question: question, answer: answer));
    if (TvStore.instance.assistant.value.voice) {
      unawaited(Speech.instance.speak(answer));
    }
  }

  String systemPrompt() {
    final now = DateTime.now();
    final store = TvStore.instance;
    final city = cities[store.settings.value.city.clamp(0, cities.length - 1)];
    final w = WeatherService.instance.weather.value;
    final channels = store.channels.value
        .take(40)
        .map((c) => c.title)
        .join(', ');
    return [
      'Sen “Telefon TV” televizoridagi ovozli yordamchisan — Siri’dan aqlliroq, '
          'samimiy va aniq.',
      'Foydalanuvchi qaysi tilda yozsa (o‘zbek, rus yoki ingliz), o‘sha tilda javob ber. '
          'O‘zbekcha — lotin yozuvida.',
      'Javob televizor ekranida ko‘rsatiladi va ovoz chiqarib o‘qiladi: odatda 1–3 qisqa gap, '
          'markdown, ro‘yxat, jadval va emoji ishlatma. Foydalanuvchi batafsil so‘rasa — 6 gapgacha.',
      'Bugun: ${_date(now, 'uz')}, soat ${_two(now.hour)}:${_two(now.minute)}. '
          'Foydalanuvchi shahri: ${city.name}, O‘zbekiston.'
          '${w == null ? '' : ' Hozir u yerda ${_deg(w.temp)}, ${weatherText(w.code).toLowerCase()}.'}',
      if (channels.isNotEmpty) 'Jonli kanallar: $channels.',
      'Televizorda biror narsa ochish kerak bo‘lsa, javobning oxirida alohida qatorda '
          'faqat bitta buyruq yoz: [[youtube: so‘rov]] — YouTube’da qidirish, '
          '[[web: so‘rov]] — internetdan qidirish, [[open: https://…]] — saytni ochish, '
          '[[channel: kanal nomi]] — jonli kanalni qo‘yish. Kerak bo‘lmasa — buyruq yozma.',
      'Agar ekranda ochiq sahifa matni berilsa, savolga shu sahifa asosida javob ber.',
    ].join('\n');
  }

  NavigatorState? get _nav => TvInput.instance.navigatorKey.currentState;

  void _push(Widget screen) {
    final nav = _nav;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Buyruqni bajaradi va qisqa javob matnini qaytaradi.
  Future<String> perform(AssistAction action, String lang) async {
    final store = TvStore.instance;
    final services = TvServices.instance;
    switch (action) {
      case OpenPlace(:final place):
        final (Widget? screen, uz, ru, en) = switch (place) {
          TvPlace.home => (null, 'Bosh sahifa', 'Главный экран', 'Home screen'),
          TvPlace.live => (
            const LiveScreen(),
            'Jonli TV ochildi',
            'Открываю телеканалы',
            'Opening live TV',
          ),
          TvPlace.radio => (
            const RadioScreen(),
            'Radio ochildi',
            'Открываю радио',
            'Opening radio',
          ),
          TvPlace.favorites => (
            const LiveScreen(favoritesOnly: true),
            'Sevimli kanallar',
            'Избранные каналы',
            'Favorite channels',
          ),
          TvPlace.videos => (
            const FilesScreen(filter: MediaKind.video),
            'Videolaringiz',
            'Ваши видео',
            'Your videos',
          ),
          TvPlace.photos => (
            const FilesScreen(filter: MediaKind.image),
            'Rasmlaringiz',
            'Ваши фото',
            'Your photos',
          ),
          TvPlace.music => (
            const FilesScreen(filter: MediaKind.audio),
            'Musiqangiz',
            'Ваша музыка',
            'Your music',
          ),
          TvPlace.settings => (
            const SettingsScreen(),
            'Sozlamalar',
            'Настройки',
            'Settings',
          ),
          TvPlace.pair => (
            const PairScreen(),
            'Pult ulash: QR kodni skanerlang',
            'Сканируйте QR-код',
            'Scan the QR code',
          ),
          TvPlace.apps => (
            const AppsScreen(),
            'Ilovalar',
            'Приложения',
            'Apps',
          ),
          TvPlace.browser => (
            const BrowserScreen(),
            'Brauzer ochildi',
            'Открываю браузер',
            'Opening the browser',
          ),
          TvPlace.player => (
            const PlayerHubScreen(),
            'Video pleyer',
            'Видеоплеер',
            'Video player',
          ),
          TvPlace.assistantSettings => (
            const AssistantSettingsScreen(),
            'Yordamchi sozlamalari',
            'Настройки ассистента',
            'Assistant settings',
          ),
          TvPlace.sleep => (
            const SleepScreen(),
            'Xayrli tun',
            'Спокойной ночи',
            'Good night',
          ),
        };
        if (screen == null) {
          _nav?.popUntil((r) => r.isFirst);
        } else {
          _push(screen);
        }
        return say(lang, uz, ru, en);

      case OpenSite(:final site):
        if (site.url.isEmpty) {
          final ctx = TvInput.instance.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            unawaited(services.askSiteUrl(ctx, site));
          }
          return say(
            lang,
            '${site.name} manzilini pultda yozing — keyin doim shu tugmadan ochiladi',
            'Введите адрес ${site.name} на пульте',
            'Type the ${site.name} address on the remote',
          );
        }
        services.openSite(site.url, site.name);
        return say(
          lang,
          '${site.name} ochilmoqda',
          'Открываю ${site.name}',
          'Opening ${site.name}',
        );

      case WebSearch(:final query):
        services.openSite(searchUrl(query), query, search: true);
        return say(
          lang,
          '“$query” qidirilmoqda',
          'Ищу: «$query»',
          'Searching for “$query”',
        );

      case YoutubeSearch(:final query):
        services.openYoutube(query);
        return query.isEmpty
            ? say(
                lang,
                'YouTube ochilmoqda',
                'Открываю YouTube',
                'Opening YouTube',
              )
            : say(
                lang,
                'YouTube’da “$query”',
                'YouTube: «$query»',
                'YouTube: “$query”',
              );

      case PlayChannel(:final index, :final name):
        final list = store.channels.value;
        if (index < 0 || index >= list.length) {
          return say(
            lang,
            'Bunday kanal topilmadi',
            'Канал не найден',
            'Channel not found',
          );
        }
        final nav = _nav;
        if (nav != null) {
          nav.popUntil((r) => r.isFirst);
          unawaited(nav.push(PlayerScreen.route(list, index)));
        }
        return say(lang, '$name qo‘yildi', 'Включаю $name', 'Playing $name');

      case RemoteCmd(:final cmd, :final times):
        _dispatchingCommand = true;
        try {
          for (var i = 0; i < times; i++) {
            TvInput.instance.send(cmd);
          }
        } finally {
          _dispatchingCommand = false;
        }
        return switch (cmd) {
          Cmd.volUp => say(lang, 'Ovoz balandladi', 'Громче', 'Volume up'),
          Cmd.volDown => say(lang, 'Ovoz pasaydi', 'Тише', 'Volume down'),
          Cmd.mute => say(lang, 'Ovoz o‘chirildi', 'Звук выключен', 'Muted'),
          Cmd.playPause => say(lang, 'Bajarildi', 'Готово', 'Done'),
          Cmd.next => say(lang, 'Keyingisi', 'Следующий', 'Next'),
          Cmd.prev => say(lang, 'Oldingisi', 'Предыдущий', 'Previous'),
          Cmd.back => say(lang, 'Orqaga', 'Назад', 'Back'),
          _ => say(lang, 'Bajarildi', 'Готово', 'Done'),
        };

      case TellInfo(:final kind, :final city):
        final now = DateTime.now();
        switch (kind) {
          case InfoKind.time:
            final t = '${_two(now.hour)}:${_two(now.minute)}';
            return say(lang, 'Soat $t', 'Сейчас $t', 'It’s $t');
          case InfoKind.date:
            return say(
              lang,
              'Bugun ${_date(now, 'uz')}',
              'Сегодня ${_date(now, 'ru')}',
              'Today is ${_date(now, 'en')}',
            );
          case InfoKind.weather:
            final mine = store.settings.value.city.clamp(0, cities.length - 1);
            final c = city ?? mine;
            final w = c == mine && WeatherService.instance.weather.value != null
                ? WeatherService.instance.weather.value
                : await fetchWeather(cities[c]);
            if (w == null) {
              return say(
                lang,
                'Ob-havo ma’lumotini olib bo‘lmadi — internetni tekshiring',
                'Не удалось получить погоду',
                'Couldn’t get the weather',
              );
            }
            return say(
              lang,
              '${w.city}da hozir ${_deg(w.temp)}, ${weatherText(w.code).toLowerCase()}. '
                  'Bugun ${_deg(w.min)} dan ${_deg(w.max)} gacha.',
              '${w.city}: сейчас ${_deg(w.temp)}. Сегодня от ${_deg(w.min)} до ${_deg(w.max)}.',
              '${w.city}: now ${_deg(w.temp)}. Today from ${_deg(w.min)} to ${_deg(w.max)}.',
            );
        }
    }
  }
}

/// Ekranda ko‘rsatiladigan javob: [[buyruq]] va oqimda yarim kelgan “[[…”siz.
String visibleAnswer(String s) {
  var t = s.replaceAll(RegExp(r'\[\[[^\]]*\]\]'), '');
  final open = t.lastIndexOf('[[');
  if (open >= 0) t = t.substring(0, open);
  if (t.endsWith('[')) t = t.substring(0, t.length - 1);
  return t.replaceAll(RegExp(r'[*#`]'), '').trim();
}

/// AI javobi oxiridagi buyruq: [[youtube: …]], [[web: …]], [[open: …]], [[channel: …]].
AssistAction? actionFromTag(String s) {
  final m = RegExp(
    r'\[\[\s*(\w+)\s*:\s*([^\]]+?)\s*\]\]',
  ).allMatches(s).lastOrNull;
  if (m == null) return null;
  final kind = m.group(1)!.toLowerCase();
  final value = m.group(2)!.trim();
  if (value.isEmpty) return null;
  switch (kind) {
    case 'youtube':
      return YoutubeSearch(value);
    case 'web' || 'search':
      return WebSearch(value);
    case 'open':
      final url = normalizeUrl(value);
      if (url == null) return null;
      final host = Uri.parse(url).host.replaceFirst('www.', '');
      return OpenSite(Site(id: host, name: host, url: url, colors: const []));
    case 'channel':
      final names = [for (final c in TvStore.instance.channels.value) c.title];
      final u = understand('kanal $value', channels: names, sites: const []);
      return u?.action is PlayChannel ? u!.action : null;
  }
  return null;
}

String searchUrl(String q) =>
    'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}';

String _two(int n) => n.toString().padLeft(2, '0');

String _deg(double t) {
  final r = t.round();
  return '${r > 0 ? '+' : ''}$r°';
}

String _date(DateTime d, String lang) {
  const uzM = [
    'yanvar',
    'fevral',
    'mart',
    'aprel',
    'may',
    'iyun',
    'iyul',
    'avgust',
    'sentabr',
    'oktabr',
    'noyabr',
    'dekabr',
  ];
  const uzD = [
    'dushanba',
    'seshanba',
    'chorshanba',
    'payshanba',
    'juma',
    'shanba',
    'yakshanba',
  ];
  const ruM = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  const ruD = [
    'понедельник',
    'вторник',
    'среда',
    'четверг',
    'пятница',
    'суббота',
    'воскресенье',
  ];
  const enM = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const enD = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final m = d.month - 1, w = d.weekday - 1;
  return switch (lang) {
    'ru' => '${d.day} ${ruM[m]}, ${ruD[w]}',
    'en' => '${enD[w]}, ${enM[m]} ${d.day}',
    _ => '${d.day}-${uzM[m]}, ${uzD[w]}',
  };
}
