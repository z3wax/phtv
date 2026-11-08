import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/phone/offline_stt.dart';

Float32List _tone(double seconds, double amp, {int rate = 16000}) {
  final out = Float32List((seconds * rate).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = amp * math.sin(2 * math.pi * 220 * i / rate);
  }
  return out;
}

Float32List _noise(double seconds, double amp, {int rate = 16000}) {
  final r = math.Random(7);
  final out = Float32List((seconds * rate).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = amp * (r.nextDouble() * 2 - 1);
  }
  return out;
}

/// Parchalab beradi (mikrofon 100 ms dan yuboradi).
bool? _feed(SpeechGate gate, Float32List audio) {
  for (var o = 0; o < audio.length; o += 1600) {
    final r = gate.add(
      Float32List.sublistView(audio, o, math.min(o + 1600, audio.length)),
    );
    if (r != null) return r;
  }
  return null;
}

void main() {
  group('jimlikni aniqlash', () {
    test('gapdan keyin ~1 soniya jimlik — tugadi', () {
      final gate = SpeechGate();
      expect(_feed(gate, _noise(0.5, 0.002)), isNull);
      expect(_feed(gate, _tone(1.5, 0.2)), isNull);
      expect(gate.heardSpeech, isTrue);
      expect(_feed(gate, _noise(0.6, 0.002)), isNull);
      expect(_feed(gate, _noise(0.8, 0.002)), isTrue);
    });

    test('faqat shovqin — hech narsa aytilmadi', () {
      final gate = SpeechGate();
      expect(_feed(gate, _noise(8, 0.004)), isFalse);
      expect(gate.heardSpeech, isFalse);
    });

    test('qisqa taqillash gap hisoblanmaydi', () {
      final gate = SpeechGate();
      _feed(gate, _noise(0.5, 0.002));
      _feed(gate, _tone(0.06, 0.3));
      _feed(gate, _noise(0.5, 0.002));
      expect(gate.heardSpeech, isFalse);
    });

    test('uzun gap 15 soniyada to‘xtaydi', () {
      final gate = SpeechGate();
      _feed(gate, _noise(0.4, 0.002));
      expect(_feed(gate, _tone(16, 0.2)), isTrue);
    });
  });

  test('16-bit PCM: toq bayt keyingi parchaga o‘tadi', () {
    final d = Pcm16Decoder();
    // 0x4000 = 16384 → 0.5, 0xC000 = -16384 → -0.5
    final a = d.convert(Uint8List.fromList([0x00, 0x40, 0x00]));
    expect(a, [0.5]);
    final b = d.convert(Uint8List.fromList([0xC0, 0xFF, 0x7F]));
    expect(b, [-0.5, 32767 / 32768]);
  });

  group('model yuklash va tanlash', () {
    late HttpServer server;
    late Directory tmp;
    final served = <String, List<int>>{};
    final ranges = <String?>[];
    late SttModelSpec ctc, zip;
    late List<SttModelSpec> previousModels;

    SttModelSpec spec(String id, List<String> names, SttKind kind) =>
        SttModelSpec(
          id: id,
          name: id,
          megabytes: '1 MB',
          about: '',
          credit: '',
          repo: 'test/$id',
          revision: 'main',
          files: [
            for (final n in names) (n, served[n.split('/').last]!.length),
          ],
          kind: kind,
        );

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('stt');
      served
        ..clear()
        ..['model.int8.onnx'] = List.generate(5000, (i) => i % 251)
        ..['tokens.txt'] = 'a 0\nb 1\n<blk> 2\n'.codeUnits
        ..['encoder.onnx'] = List.generate(3000, (i) => i % 7)
        ..['decoder.onnx'] = List.generate(200, (i) => i % 5)
        ..['joiner.onnx'] = List.generate(100, (i) => i % 3);
      ranges.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final name = req.uri.pathSegments.last;
        // Hugging Face kabi: avval CDN manziliga yo‘naltiradi.
        if (req.uri.pathSegments.first == 'resolve') {
          req.response
            ..statusCode = 302
            ..headers.set('location', '/cdn/$name');
          await req.response.close();
          return;
        }
        final data = served[name];
        if (data == null) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final range = req.headers.value('range');
        ranges.add(range);
        var start = 0;
        if (range != null) {
          start = int.parse(
            RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
          );
          req.response.statusCode = 206;
        }
        req.response.contentLength = data.length - start;
        req.response.add(data.sublist(start));
        await req.response.close();
      });
      ctc = spec('ctc', ['model.int8.onnx', 'tokens.txt'], SttKind.nemoCtc);
      // Vosk kabi: fayllar repozitoriyda papkalarda.
      zip = spec('zip', [
        'am-onnx/encoder.onnx',
        'am-onnx/decoder.onnx',
        'am-onnx/joiner.onnx',
        'lang/tokens.txt',
      ], SttKind.streamingTransducer);
      final stt = OfflineStt.instance;
      previousModels = stt.models;
      stt.models = [ctc, zip];
      stt.baseDir = () async => tmp;
      stt.urlFor = (m, f) =>
          Uri.parse('http://127.0.0.1:${server.port}/resolve/${m.id}/$f');
      await stt.select(ctc);
    });

    tearDown(() async {
      final stt = OfflineStt.instance;
      await stt.remove(ctc);
      await stt.remove(zip);
      stt.models = previousModels;
      await stt.select(UzbekSttModel.accurate);
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    test('yo‘naltirish orqali yuklanadi va o‘rnatilgan deb topiladi', () async {
      final stt = OfflineStt.instance;
      expect(await stt.refresh(ctc), isFalse);
      expect(stt.statusOf(ctc).value.phase, SttModelPhase.missing);
      await stt.download(ctc);
      expect(stt.statusOf(ctc).value.phase, SttModelPhase.ready);
      expect(await stt.refresh(ctc), isTrue);
      final dir = await stt.modelDir(ctc);
      expect(
        await File('${dir.path}/model.int8.onnx').readAsBytes(),
        served['model.int8.onnx'],
      );
      expect(ranges, [null, null]);
    });

    test('papkalardagi fayllar (Vosk) bitta papkaga yuklanadi', () async {
      final stt = OfflineStt.instance;
      await stt.download(zip);
      expect(stt.statusOf(zip).value.phase, SttModelPhase.ready);
      final dir = await stt.modelDir(zip);
      for (final name in [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]) {
        expect(await File('${dir.path}/$name').readAsBytes(), served[name]);
      }
      // Yuklangan model tanlanadi.
      expect(stt.selected.value.id, 'zip');
      expect((await stt.active())?.id, 'zip');
    });

    test('tanlangani yo‘q bo‘lsa — o‘rnatilgan boshqasi ishlaydi', () async {
      final stt = OfflineStt.instance;
      expect(await stt.active(), isNull);
      await stt.download(ctc);
      await stt.download(zip);
      expect((await stt.active())?.id, 'zip');
      await stt.select(ctc);
      expect((await stt.active())?.id, 'ctc');
      // Tanlangani o‘chirilsa — boshqasi tanlanadi.
      await stt.remove(ctc);
      expect(stt.selected.value.id, 'zip');
      expect((await stt.active())?.id, 'zip');
      await stt.remove(zip);
      expect(await stt.active(), isNull);
    });

    test('uzilgan yuklash qolgan joyidan davom etadi', () async {
      final stt = OfflineStt.instance;
      final dir = await stt.modelDir(ctc);
      await dir.create(recursive: true);
      // Oldingi urinishda 1200 bayt yuklangan.
      await File(
        '${dir.path}/model.int8.onnx.part',
      ).writeAsBytes(served['model.int8.onnx']!.sublist(0, 1200));
      await stt.download(ctc);
      expect(stt.statusOf(ctc).value.phase, SttModelPhase.ready);
      expect(ranges.first, 'bytes=1200-');
      expect(
        await File('${dir.path}/model.int8.onnx').readAsBytes(),
        served['model.int8.onnx'],
      );
      expect(await File('${dir.path}/model.int8.onnx.part').exists(), isFalse);
    });

    test('server xato bersa — tushunarli xabar', () async {
      final stt = OfflineStt.instance;
      stt.urlFor = (m, f) =>
          Uri.parse('http://127.0.0.1:${server.port}/cdn/yoq-$f');
      await stt.download(ctc);
      expect(stt.statusOf(ctc).value.phase, SttModelPhase.failed);
      expect(stt.statusOf(ctc).value.error, isNotEmpty);
      expect(await stt.active(), isNull);
    });

    test('hajmi mos kelmasa — o‘rnatilmagan', () async {
      final stt = OfflineStt.instance;
      await stt.download(ctc);
      final dir = await stt.modelDir(ctc);
      await File('${dir.path}/tokens.txt').writeAsString('buzilgan');
      expect(await stt.refresh(ctc), isFalse);
      expect(stt.statusOf(ctc).value.phase, SttModelPhase.missing);
      await stt.remove(ctc);
      expect(await dir.exists(), isFalse);
    });
  });

  test('ikki model: hajmlar va manzillar', () {
    expect(UzbekSttModel.accurate.bytes, 173888181 + 9759);
    expect(UzbekSttModel.light.bytes, 90994145 + 2093080 + 1026462 + 3957);
    expect(UzbekSttModel.light.megabytes, '94 MB');
    expect(
      UzbekSttModel.light.url('am-onnx/encoder.onnx').toString(),
      'https://huggingface.co/alphacep/vosk-model-small-streaming-uz/resolve/'
      '${UzbekSttModel.light.revision}/am-onnx/encoder.onnx',
    );
    expect(UzbekSttModel.byId('uz-vosk-zipformer'), UzbekSttModel.light);
    expect(UzbekSttModel.byId('yoq'), UzbekSttModel.accurate);
  });
}
