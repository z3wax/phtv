import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:telefon_tv/phone/offline_stt.dart';

/// Haqiqiy model bilan tekshiruv (CI: build.yml → stt_check).
/// STT_MODEL_DIR — model papkasi, SHERPA_LIB_DIR — libsherpa-onnx-c-api.so,
/// STT_WAVS — `fayl.wav|kutilgan matn` qatorlari bo‘lgan ro‘yxat.
void main() {
  final env = Platform.environment;
  final dir = env['STT_MODEL_DIR'];
  final lib = env['SHERPA_LIB_DIR'];
  final list = env['STT_WAVS'];

  String words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ʻ‘’`ʼ]'), "'")
      .replaceAll(RegExp(r"[^a-z' ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  test(
    'o‘zbekcha nutq internetsiz taniladi',
    () {
      sherpa.initBindings(lib);
      final recognizer = createUzbekRecognizer(dir!);
      var total = 0, matched = 0;
      for (final line in File(list!).readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final [wav, expected] = line.split('|');
        final wave = sherpa.readWave(wav);
        expect(wave.sampleRate, UzbekSttModel.sampleRate);
        final sw = Stopwatch()..start();
        final text = recognizeUzbek(recognizer, wave.samples);
        final seconds = wave.samples.length / wave.sampleRate;
        // ignore: avoid_print
        print(
          'STT ${seconds.toStringAsFixed(1)} s audio, '
          '${sw.elapsedMilliseconds} ms: “$text” (kutilgan: “$expected”)',
        );
        final want = words(expected).split(' ');
        final got = words(text).split(' ').toSet();
        total += want.length;
        matched += want.where(got.contains).length;
      }
      recognizer.free();
      // ignore: avoid_print
      print('STT so‘zlar: $matched / $total');
      expect(total, greaterThan(0));
      expect(matched / total, greaterThan(0.7));
    },
    skip: dir == null || list == null
        ? 'STT_MODEL_DIR va STT_WAVS berilmagan (faqat CI tekshiruvida)'
        : false,
  );
}
