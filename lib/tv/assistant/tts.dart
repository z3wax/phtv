import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'cloud_speech.dart';

import 'intents.dart';
import '../store.dart';

/// Barcha qurilmalarda o‘zbekcha bulutli ovoz; internetsiz tizim ovozi.
/// Umumiy ovoz foizi va mute AI javobiga ham birdek qo‘llanadi.
class Speech {
  Speech._() {
    TvStore.instance.settings.addListener(_volumeChanged);
  }
  static final instance = Speech._();

  FlutterTts? _tts;
  Process? _proc;
  final cloud = CloudSpeechClient();
  final status = ValueNotifier<String>('');
  _CloudPlayback? _playback;
  int _generation = 0;
  DateTime? _retryCloudAt;
  final _available = <String, bool>{};

  /// Testlarda o‘chiriladi.
  bool enabled = true;

  bool get _usePlugin =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  void _volumeChanged() {
    final volume = TvStore.instance.settings.value.effectiveVolume;
    final playback = _playback;
    if (playback != null) {
      unawaited(
        playback.controller.setVolume(volume).catchError((Object _) {}),
      );
    }
    if (volume == 0) {
      unawaited(stop());
    } else if (_tts != null) {
      unawaited(_tts!.setVolume(volume).catchError((Object _) => null));
    }
  }

  Future<void> stop() async {
    _generation++;
    await _stopPlayback();
  }

  Future<void> _stopPlayback() async {
    cloud.cancel();
    final playback = _playback;
    _playback = null;
    _proc?.kill();
    _proc = null;
    try {
      await _tts?.stop();
    } catch (_) {}
    await playback?.dispose();
  }

  Future<void> speak(String text, {String? language}) async {
    if (!enabled) return;
    final generation = ++_generation;
    await _stopPlayback();
    if (generation != _generation) return;
    final lang = language ?? detectLang(text);
    final clean = spokenText(lang == 'uz' ? uzbekToLatin(text) : text);
    if (clean.isEmpty || TvStore.instance.settings.value.effectiveVolume == 0) {
      return;
    }
    final config = TvStore.instance.assistant.value;
    if (lang == 'uz' &&
        config.cloudVoice &&
        (_retryCloudAt == null || DateTime.now().isAfter(_retryCloudAt!))) {
      try {
        final bytes = await cloud.synthesize(clean, voice: config.uzbekVoice);
        if (generation != _generation) return;
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/telefon-tv-voice-${DateTime.now().microsecondsSinceEpoch}-$generation.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        if (generation != _generation) {
          await file.delete();
          return;
        }
        final playback = _CloudPlayback(file);
        _playback = playback;
        await playback.controller.initialize().timeout(
          const Duration(seconds: 10),
        );
        if (generation != _generation) {
          await playback.dispose();
          return;
        }
        await playback.controller.setVolume(
          TvStore.instance.settings.value.effectiveVolume,
        );
        playback.controller.addListener(() {
          if (playback.controller.value.isCompleted &&
              identical(_playback, playback)) {
            _playback = null;
            unawaited(playback.dispose());
          }
        });
        await playback.controller.play();
        if (generation == _generation) {
          status.value = '${config.uzbekVoice} · bulutli ovoz';
        }
        return;
      } on SpeechCancelled {
        return;
      } catch (_) {
        if (generation != _generation) return;
        final playback = _playback;
        _playback = null;
        await playback?.dispose();
        _retryCloudAt = DateTime.now().add(const Duration(seconds: 30));
        status.value = 'Bulutli ovozga ulanilmadi · qurilma ovozi';
      }
    } else {
      status.value = 'Qurilma ovozi';
    }
    if (generation != _generation ||
        TvStore.instance.settings.value.effectiveVolume == 0) {
      return;
    }
    try {
      if (_usePlugin) {
        await _speakPlugin(clean, lang, generation);
      } else if (Platform.isLinux) {
        await _speakLinux(clean, lang, generation);
      }
    } catch (_) {
      // Javob ekranda qoladi; ovoz xatosi ilovani yopmaydi.
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

  Future<void> _speakPlugin(String text, String lang, int generation) async {
    final tts = _tts ??= FlutterTts();
    await tts.awaitSpeakCompletion(false);
    await tts.setSpeechRate(Platform.isAndroid ? 0.5 : 0.52);
    await tts.setVolume(TvStore.instance.settings.value.effectiveVolume);
    String? locale;
    var say = text;
    if (lang == 'ru') {
      locale = 'ru-RU';
    } else if (lang == 'en') {
      locale = 'en-US';
    } else if (await _selectUzbekVoice(tts)) {
      if (generation == _generation) await tts.speak(text);
      return;
    } else if (await _has(tts, 'uz-UZ')) {
      locale = 'uz-UZ';
    } else if (await _has(tts, 'uz')) {
      locale = 'uz';
    } else if (await _has(tts, 'tr-TR')) {
      locale = 'tr-TR';
      say = uzbekForTurkishVoice(text);
    }
    if (locale == null || !await _has(tts, locale)) return;
    await tts.setLanguage(locale);
    if (generation == _generation) await tts.speak(say);
  }

  Future<bool> _selectUzbekVoice(FlutterTts tts) async {
    try {
      final voices = await tts.getVoices;
      if (voices is! List) return false;
      final voice = selectUzbekVoice(voices);
      if (voice == null) return false;
      await tts.setLanguage(voice['locale']!);
      await tts.setVoice(voice);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _speakLinux(String text, String lang, int generation) async {
    final voice = switch (lang) {
      'ru' => 'ru',
      'en' => 'en-us',
      _ => 'uz',
    };
    for (final (exe, args) in [
      (
        'espeak-ng',
        [
          '-v',
          voice,
          '-s',
          '155',
          '-a',
          '${(TvStore.instance.settings.value.effectiveVolume * 100).round()}',
          text,
        ],
      ),
      (
        'spd-say',
        [
          '-l',
          lang,
          '-i',
          '${(TvStore.instance.settings.value.effectiveVolume * 100 - 100).round()}',
          '-w',
          text,
        ],
      ),
      (
        'espeak',
        [
          '-v',
          voice,
          '-a',
          '${(TvStore.instance.settings.value.effectiveVolume * 100).round()}',
          text,
        ],
      ),
    ]) {
      try {
        if (generation != _generation) return;
        final proc = await Process.start(exe, args);
        if (generation != _generation) {
          proc.kill();
          return;
        }
        _proc = proc;
        unawaited(proc.exitCode.then((_) {}));
        return;
      } on ProcessException {
        continue;
      }
    }
  }
}

/// Haqiqiy o‘zbek ovozi turkcha talaffuzga moslashdan oldin tanlanadi.
Map<String, String>? selectUzbekVoice(List<dynamic> voices) {
  final candidates = voices.whereType<Map>().where((v) {
    final locale = '${v['locale'] ?? v['language'] ?? ''}'
        .replaceAll('_', '-')
        .toLowerCase();
    return (locale == 'uz' || locale.startsWith('uz-')) && v['name'] is String;
  }).toList();
  int quality(Map v) {
    final value = '${v['quality']}'.toLowerCase();
    return int.tryParse(value) ??
        (value.contains('premium')
            ? 1000
            : value.contains('enhanced')
            ? 500
            : 0);
  }

  candidates.sort((a, b) => quality(b).compareTo(quality(a)));
  if (candidates.isEmpty) return null;
  final voice = candidates.first;
  return {
    'name': voice['name'] as String,
    'locale': '${voice['locale'] ?? voice['language']}'.replaceAll('_', '-'),
  };
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

class _CloudPlayback {
  _CloudPlayback(this.file)
    : controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
  final File file;
  final VideoPlayerController controller;
  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    try {
      await controller.dispose();
    } catch (_) {}
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
