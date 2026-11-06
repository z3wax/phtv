import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'intents.dart';

/// Javobni televizor karnayidan ovoz chiqarib aytish.
///
/// * Android / iPhone / Mac — tizim ovozlari (flutter_tts).
/// * Ubuntu — `espeak-ng` yoki `spd-say` (o‘zbek tili ham bor).
/// * O‘zbekcha ovoz bo‘lmasa — turkcha ovoz o‘zbekcha o‘qiydi
///   (sh → ş, ch → ç: talaffuz juda yaqin).
class Speech {
  Speech._();
  static final instance = Speech._();

  FlutterTts? _tts;
  Process? _proc;
  final _available = <String, bool>{};

  /// Testlarda o‘chiriladi.
  bool enabled = true;

  bool get _usePlugin =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<void> stop() async {
    _proc?.kill();
    _proc = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    final clean = spokenText(text);
    if (clean.isEmpty) return;
    await stop();
    final lang = detectLang(clean);
    try {
      if (_usePlugin) {
        await _speakPlugin(clean, lang);
      } else if (Platform.isLinux) {
        await _speakLinux(clean, lang);
      }
    } catch (_) {
      // Ovoz chiqmasa ham javob ekranda turadi.
    }
  }

  Future<bool> _has(FlutterTts tts, String locale) async {
    final cached = _available[locale];
    if (cached != null) return cached;
    var ok = false;
    try {
      final r = await tts.isLanguageAvailable(locale);
      ok = r == true || r == 1;
    } catch (_) {}
    return _available[locale] = ok;
  }

  Future<void> _speakPlugin(String text, String lang) async {
    final tts = _tts ??= FlutterTts();
    await tts.awaitSpeakCompletion(false);
    await tts.setSpeechRate(Platform.isAndroid ? 0.5 : 0.52);
    String? locale;
    var say = text;
    if (lang == 'ru') {
      locale = 'ru-RU';
    } else if (lang == 'en') {
      locale = 'en-US';
    } else if (await _has(tts, 'uz-UZ')) {
      locale = 'uz-UZ';
    } else if (await _has(tts, 'tr-TR')) {
      locale = 'tr-TR';
      say = uzbekForTurkishVoice(text);
    }
    if (locale == null || !await _has(tts, locale)) return;
    await tts.setLanguage(locale);
    await tts.speak(say);
  }

  Future<void> _speakLinux(String text, String lang) async {
    final voice = switch (lang) {
      'ru' => 'ru',
      'en' => 'en-us',
      _ => 'uz',
    };
    for (final (exe, args) in [
      ('espeak-ng', ['-v', voice, '-s', '160', text]),
      ('spd-say', ['-l', lang, '-w', text]),
      ('espeak', ['-v', voice, text]),
    ]) {
      try {
        _proc = await Process.start(exe, args);
        unawaited(_proc!.exitCode.then((_) {}));
        return;
      } on ProcessException {
        continue;
      }
    }
  }
}

/// Ekrandagi matndan ovozga keraksiz belgilarni olib tashlaydi.
String spokenText(String s) => s
    .replaceAll(RegExp(r'\[\[.*?\]\]'), '')
    .replaceAll(RegExp(r'https?://\S+'), '')
    .replaceAll(RegExp(r'[*_#`>|]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// O‘zbekcha lotin matnini turkcha ovoz to‘g‘ri o‘qishi uchun yozadi.
String uzbekForTurkishVoice(String s) {
  var t = s.replaceAll(RegExp('[‘’ʻʼ`´]'), "'");
  const pairs = [
    ('Sh', 'Ş'),
    ('SH', 'Ş'),
    ('sh', 'ş'),
    ('Ch', 'Ç'),
    ('CH', 'Ç'),
    ('ch', 'ç'),
    ("O'", 'O'),
    ("o'", 'o'),
    ("G'", 'Ğ'),
    ("g'", 'ğ'),
    ('J', 'C'),
    ('j', 'c'),
    ('X', 'H'),
    ('x', 'h'),
    ('Q', 'K'),
    ('q', 'k'),
    ("'", ''),
  ];
  for (final (a, b) in pairs) {
    t = t.replaceAll(a, b);
  }
  return t;
}
