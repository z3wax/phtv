import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:telefon_tv/phone/offline_stt.dart';

/// Haqiqiy modellar bilan tekshiruv (CI: build.yml → stt_check): ikkala
/// model ilovaning o‘z yuklash kodi bilan Hugging Face’dan olinadi va bir xil
/// o‘zbekcha jumlalarda solishtiriladi.
/// SHERPA_LIB_DIR — libsherpa-onnx-c-api.so, STT_WAVS — `fayl.wav|matn`
/// qatorlari, STT_DIR — modellar saqlanadigan papka.
void main() {
  final env = Platform.environment;
  final lib = env['SHERPA_LIB_DIR'];
  final list = env['STT_WAVS'];

  String words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ʻ‘’`ʼ]'), "'")
      .replaceAll(RegExp(r"[^a-z' ]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> revisionInfo(SttModelSpec m) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse(
          'https://huggingface.co/api/models/${m.repo}/revision/${m.revision}',
        ),
      );
      final body = await (await req.close()).transform(utf8.decoder).join();
      final sha = (jsonDecode(body) as Map)['sha'];
      // ignore: avoid_print
      print('STT ${m.name}: ${m.repo} revision=${m.revision} sha=$sha');
    } catch (e) {
      // ignore: avoid_print
      print('STT ${m.name}: sha olinmadi ($e)');
    } finally {
      client.close(force: true);
    }
  }

  for (final model in UzbekSttModel.all) {
    test(
      '${model.name} (${model.megabytes}): o‘zbekcha nutq internetsiz taniladi',
      () async {
        sherpa.initBindings(lib);
        final stt = OfflineStt.instance;
        final base = Directory(env['STT_DIR'] ?? Directory.systemTemp.path);
        stt.baseDir = () async => base;
        await revisionInfo(model);
        await stt.download(model);
        expect(
          stt.statusOf(model).value.phase,
          SttModelPhase.ready,
          reason: stt.statusOf(model).value.error,
        );
        final dir = (await stt.modelDir(model)).path;
        final load = Stopwatch()..start();
        final recognizer = UzbekRecognizer(dir, model.kind);
        // ignore: avoid_print
        print(
          'STT ${model.name}: ${recognizer.mode} rejim, '
          'yuklash ${load.elapsedMilliseconds} ms',
        );
        var total = 0, matched = 0, audioMs = 0, spentMs = 0;
        for (final line in File(list!).readAsLinesSync()) {
          if (line.trim().isEmpty) continue;
          final [wav, expected] = line.split('|');
          final wave = sherpa.readWave(wav);
          expect(wave.sampleRate, UzbekSttModel.sampleRate);
          final sw = Stopwatch()..start();
          final text = recognizer.recognize(wave.samples);
          spentMs += sw.elapsedMilliseconds;
          audioMs += wave.samples.length * 1000 ~/ wave.sampleRate;
          // ignore: avoid_print
          print('STT ${model.name}: “$text” (kutilgan: “$expected”)');
          final want = words(expected).split(' ');
          final got = words(text).split(' ').toSet();
          total += want.length;
          matched += want.where(got.contains).length;
        }
        recognizer.free();
        // ignore: avoid_print
        print(
          'STT ${model.name} NATIJA: $matched / $total so‘z to‘g‘ri '
          '(${(100 * matched / total).toStringAsFixed(0)}%), '
          '${(audioMs / 1000).toStringAsFixed(1)} s ovoz $spentMs ms da',
        );
        expect(total, greaterThan(0));
        expect(matched / total, greaterThan(0.6));
      },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: list == null
          ? 'STT_WAVS berilmagan (faqat CI tekshiruvida)'
          : false,
    );
  }
}
