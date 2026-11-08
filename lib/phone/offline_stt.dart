import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Telefonda, internetsiz o‘zbekcha nutqni tanish modeli.
///
/// NVIDIA FastConformer-Hybrid Large (uz, 115M parametr, CC BY 4.0) —
/// o‘zbekcha uchun ochiq modellar orasida eng aniqlaridan biri (FLEURS ~11%,
/// Common Voice ~7% WER) va hajmi bo‘yicha eng kichigi: int8, 174 MB.
/// sherpa-onnx uchun tayyorlangan nusxasi Hugging Face’dan bir marta
/// yuklab olinadi.
class UzbekSttModel {
  static const title = 'Internetsiz o‘zbekcha nutq';
  static const credit = 'NVIDIA FastConformer (uz), CC BY 4.0';
  static const repo = 'algorithco/stt_uz_fastconformer_hybrid_large_pc';
  static const revision = 'main';
  static const files = <(String, int)>[
    ('model.int8.onnx', 173888181),
    ('tokens.txt', 9759),
  ];
  static const folder = 'stt/uz-fastconformer';
  static const sampleRate = 16000;

  static int get bytes => files.fold(0, (a, f) => a + f.$2);

  /// Foydalanuvchiga ko‘rsatiladigan hajm ([bytes] bilan mos).
  static const megabytes = '174 MB';

  static Uri url(String file) =>
      Uri.parse('https://huggingface.co/$repo/resolve/$revision/$file');
}

enum SttModelPhase { missing, downloading, ready, failed }

@immutable
class SttModelStatus {
  const SttModelStatus(
    this.phase, {
    this.received = 0,
    this.total = 0,
    this.error = '',
  });
  final SttModelPhase phase;
  final int received;

  /// Jami hajm (0 — modelning odatiy hajmi).
  final int total;
  final String error;

  int get _total => total > 0 ? total : UzbekSttModel.bytes;
  double get progress => (received / _total).clamp(0.0, 1.0);
  int get percent => (progress * 100).floor();
}

/// Mikrofon jimligini kuzatadi: gap boshlanganini va tugaganini (1 soniya
/// jimlik) aniqlaydi. Shovqin darajasiga o‘zi moslashadi.
class SpeechGate {
  SpeechGate({
    this.sampleRate = UzbekSttModel.sampleRate,
    this.silenceAfterSpeech = const Duration(milliseconds: 1100),
    this.noSpeechTimeout = const Duration(seconds: 7),
    this.maxLength = const Duration(seconds: 15),
  });

  final int sampleRate;
  final Duration silenceAfterSpeech;
  final Duration noSpeechTimeout;
  final Duration maxLength;

  int get _frame => sampleRate * 30 ~/ 1000; // 30 ms
  int _ms(Duration d) => d.inMilliseconds ~/ 30;

  final _pending = <double>[];
  int _frames = 0;
  int _voiced = 0;
  int _silent = 0;
  double _floor = 0;
  bool _started = false;

  /// Gap boshlandimi (kamida ~0,2 soniya ovoz).
  bool get heardSpeech => _started;

  /// Yangi parcha: `null` — tinglash davom etadi, `true` — gap tugadi,
  /// `false` — hech narsa aytilmadi.
  bool? add(Float32List samples) {
    _pending.addAll(samples);
    final frame = _frame;
    var offset = 0;
    while (_pending.length - offset >= frame) {
      var sum = 0.0;
      for (var i = offset; i < offset + frame; i++) {
        sum += _pending[i] * _pending[i];
      }
      offset += frame;
      final rms = math.sqrt(sum / frame);
      _frames++;
      // Boshidagi 0,3 soniya — shovqin darajasini o‘lchash.
      if (_frames <= 10) {
        _floor = _frames == 1 ? rms : _floor * 0.8 + rms * 0.2;
        continue;
      }
      final voiced = rms > math.max(_floor * 3.0, 0.006);
      if (voiced) {
        _voiced++;
        _silent = 0;
        if (_voiced >= 6) _started = true;
      } else {
        _silent++;
        if (!_started) _voiced = 0;
        // Shovqin pasaysa — darhol, ko‘tarilsa — sekin moslashadi.
        _floor = rms < _floor
            ? _floor * 0.9 + rms * 0.1
            : _floor * 0.995 + rms * 0.005;
      }
      if (_frames >= _ms(maxLength)) {
        _pending.clear();
        return _started;
      }
      if (_started && _silent >= _ms(silenceAfterSpeech)) {
        _pending.clear();
        return true;
      }
      if (!_started && _frames >= _ms(noSpeechTimeout)) {
        _pending.clear();
        return false;
      }
    }
    _pending.removeRange(0, offset);
    return null;
  }
}

/// 16-bit PCM (little-endian) baytlari → [-1, 1] oralig‘idagi namunalar.
/// Toq bayt keyingi parchaga qoladi.
class Pcm16Decoder {
  int? _carry;

  Float32List convert(Uint8List bytes) {
    final data = _carry == null
        ? bytes
        : (Uint8List(bytes.length + 1)
            ..[0] = _carry!
            ..setRange(1, bytes.length + 1, bytes));
    final n = data.length ~/ 2;
    _carry = data.length.isOdd ? data[data.length - 1] : null;
    final view = ByteData.sublistView(data);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}

/// Internetsiz nutqni tanish: model yuklash, mikrofon va tanish.
/// Natijalar `partial` / `final` / `error` hodisalari bilan qaytadi —
/// telefon tizimining ovozni tanishi bilan bir xil.
class OfflineStt {
  OfflineStt._();
  static final instance = OfflineStt._();

  final status = ValueNotifier<SttModelStatus>(
    const SttModelStatus(SttModelPhase.missing),
  );

  /// Testlar uchun almashtiriladi.
  @visibleForTesting
  Future<Directory> Function() baseDir = getApplicationSupportDirectory;
  @visibleForTesting
  Uri Function(String file) urlFor = UzbekSttModel.url;
  @visibleForTesting
  List<(String, int)> files = UzbekSttModel.files;

  int get _total => files.fold(0, (a, f) => a + f.$2);

  Future<Directory> modelDir() async =>
      Directory('${(await baseDir()).path}/${UzbekSttModel.folder}');

  /* ---------------- Model ---------------- */

  /// Model to‘liq o‘rnatilganmi (fayllar to‘liq hajmda).
  Future<bool> refresh() async {
    if (status.value.phase == SttModelPhase.downloading) return false;
    final ready = await _installed();
    if (ready) {
      status.value = const SttModelStatus(SttModelPhase.ready);
    } else if (status.value.phase == SttModelPhase.ready) {
      status.value = const SttModelStatus(SttModelPhase.missing);
    }
    return ready;
  }

  Future<bool> _installed() async {
    try {
      final dir = await modelDir();
      for (final (name, size) in files) {
        final f = File('${dir.path}/$name');
        if (!await f.exists() || await f.length() != size) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _stopDownload = false;

  /// Yuklab olish. Uzilib qolsa, keyingi safar qolgan joyidan davom etadi.
  Future<void> download() async {
    if (status.value.phase == SttModelPhase.downloading) return;
    if (await _installed()) {
      status.value = const SttModelStatus(SttModelPhase.ready);
      return;
    }
    _stopDownload = false;
    status.value = const SttModelStatus(SttModelPhase.downloading);
    try {
      final dir = await modelDir();
      await dir.create(recursive: true);
      var done = 0;
      for (final (name, size) in files) {
        final file = File('${dir.path}/$name');
        if (await file.exists() && await file.length() == size) {
          done += size;
          continue;
        }
        final part = File('${file.path}.part');
        final before = done;
        var shown = DateTime(0);
        await _fetch(urlFor(name), part, size, (got) {
          final now = DateTime.now();
          if (now.difference(shown).inMilliseconds < 250) return;
          shown = now;
          status.value = SttModelStatus(
            SttModelPhase.downloading,
            received: before + got,
            total: _total,
          );
        });
        await part.rename(file.path);
        done += size;
      }
      status.value = const SttModelStatus(SttModelPhase.ready);
    } on _Cancelled {
      status.value = const SttModelStatus(SttModelPhase.missing);
    } on SocketException {
      _failed('Internet yo‘q — ulanib, qayta urinib ko‘ring');
    } on TimeoutException {
      _failed(
        'Internet sekin — qayta urinib ko‘ring (qolgan joyidan davom etadi)',
      );
    } on FileSystemException catch (e) {
      _failed(
        e.osError?.errorCode == 28
            ? 'Telefonda joy yetmadi (${UzbekSttModel.megabytes} kerak)'
            : 'Faylni saqlab bo‘lmadi',
      );
    } catch (_) {
      _failed('Yuklab bo‘lmadi — qayta urinib ko‘ring');
    }
  }

  void _failed(String message) => status.value = SttModelStatus(
    SttModelPhase.failed,
    received: status.value.received,
    total: _total,
    error: message,
  );

  /// Yuklashni to‘xtatish (yuklangan qismi saqlanadi).
  void cancelDownload() => _stopDownload = true;

  Future<void> _fetch(
    Uri url,
    File part,
    int expected,
    void Function(int got) onBytes,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..userAgent = 'z3waxTV/1.0';
    try {
      var uri = url;
      for (var hop = 0; hop < 8; hop++) {
        final have = await part.exists() ? await part.length() : 0;
        if (have == expected) return;
        if (have > expected) await part.delete();
        final req = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 30));
        req.followRedirects = false;
        if (have > 0 && have < expected) {
          req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
        }
        final res = await req.close().timeout(const Duration(seconds: 30));
        final code = res.statusCode;
        if (code >= 300 && code < 400) {
          final location = res.headers.value(HttpHeaders.locationHeader);
          await res.drain<void>();
          if (location == null) throw HttpException('redirect', uri: uri);
          // Hugging Face fayllari CDN’ga yo‘naltiriladi; Range qayta yuboriladi.
          uri = uri.resolve(location);
          continue;
        }
        if (code == 416) {
          await res.drain<void>();
          await part.delete();
          continue;
        }
        final append = code == 206 && have > 0;
        if (code != 200 && !append) {
          await res.drain<void>();
          throw HttpException('HTTP $code', uri: uri);
        }
        final sink = part.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        var got = append ? have : 0;
        try {
          await for (final chunk in res.timeout(const Duration(seconds: 30))) {
            if (_stopDownload) throw _Cancelled();
            sink.add(chunk);
            got += chunk.length;
            onBytes(got);
          }
        } finally {
          await sink.close();
        }
        if (got != expected) {
          throw HttpException('Fayl to‘liq yuklanmadi', uri: uri);
        }
        return;
      }
      throw HttpException('Juda ko‘p yo‘naltirish', uri: url);
    } finally {
      client.close(force: true);
    }
  }

  /// Modelni o‘chirish (joyni bo‘shatish).
  Future<void> remove() async {
    await cancel();
    _worker?.dispose();
    _worker = null;
    try {
      final dir = await modelDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    status.value = const SttModelStatus(SttModelPhase.missing);
  }

  /* ---------------- Tanish ---------------- */

  _Worker? _worker;
  Future<_Worker?>? _loading;
  Timer? _idle;
  _Session? _session;

  bool get listening => _session != null;

  /// Modelni oldindan yuklab qo‘yish (birinchi bosishda kutmaslik uchun).
  Future<bool> warmUp() async => await _ensureWorker() != null;

  Future<_Worker?> _ensureWorker() {
    _idle?.cancel();
    if (_worker != null) return Future.value(_worker);
    return _loading ??= () async {
      try {
        if (!await _installed()) return null;
        final w = await _Worker.spawn((await modelDir()).path);
        _worker = w;
        return w;
      } catch (_) {
        status.value = const SttModelStatus(
          SttModelPhase.failed,
          error: 'Model ishga tushmadi — o‘chirib, qayta yuklab ko‘ring',
        );
        return null;
      } finally {
        _loading = null;
      }
    }();
  }

  /// 5 daqiqa ishlatilmasa — xotirani bo‘shatamiz.
  void _scheduleIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(minutes: 5), () {
      if (_session != null) return;
      _worker?.dispose();
      _worker = null;
    });
  }

  /// Tinglashni boshlaydi. Model yo‘q yoki mikrofon ochilmasa — false
  /// (telefon tizimining ovozni tanishi ishlatiladi).
  Future<bool> start(void Function(String type, String text) emit) async {
    if (_session != null || !await refresh()) return false;
    final worker = _ensureWorker();
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        await recorder.dispose();
        // Hodisa start() natijasidan keyin yetib borsin.
        Timer.run(() => emit('error', 'permission'));
        return true;
      }
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: UzbekSttModel.sampleRate,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
        ),
      );
      final session = _Session(recorder, worker, emit, this);
      _session = session;
      session.listen(stream);
      return true;
    } catch (_) {
      try {
        await recorder.dispose();
      } catch (_) {}
      return false;
    }
  }

  /// Gapirib bo‘ldim — natija `final` bilan keladi.
  Future<void> stop() async => _session?.finish();

  Future<void> cancel() async => _session?.close(emitResult: false);

  void _ended(_Session s) {
    if (_session == s) _session = null;
    _scheduleIdle();
  }
}

class _Cancelled implements Exception {}

/// Bitta tinglash: mikrofon → namunalar → oraliq va yakuniy matn.
class _Session {
  _Session(this.recorder, this.worker, this.emit, this.owner);

  final AudioRecorder recorder;
  final Future<_Worker?> worker;
  final void Function(String type, String text) emit;
  final OfflineStt owner;

  final _pcm = Pcm16Decoder();
  final _gate = SpeechGate();
  final _chunks = <Float32List>[];
  int _length = 0;
  StreamSubscription<Uint8List>? _sub;
  Timer? _partials;
  bool _busy = false;
  bool _closed = false;
  String _lastPartial = '';

  void listen(Stream<Uint8List> stream) {
    _sub = stream.listen(
      _onAudio,
      onError: (_) => close(emitResult: true),
      onDone: () => close(emitResult: true),
    );
    _partials = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _partial(),
    );
  }

  void _onAudio(Uint8List bytes) {
    if (_closed) return;
    final samples = _pcm.convert(bytes);
    if (samples.isEmpty) return;
    _chunks.add(samples);
    _length += samples.length;
    final done = _gate.add(samples);
    if (done != null) unawaited(close(emitResult: true));
  }

  Float32List _audio() {
    final all = Float32List(_length);
    var o = 0;
    for (final c in _chunks) {
      all.setRange(o, o + c.length, c);
      o += c.length;
    }
    return all;
  }

  Future<void> _partial() async {
    if (_closed || _busy || !_gate.heardSpeech) return;
    if (_length > UzbekSttModel.sampleRate * 12) return;
    final w = await worker;
    if (w == null || _closed) return;
    _busy = true;
    try {
      final text = await w.decode(_audio());
      if (!_closed && text != null && text.isNotEmpty && text != _lastPartial) {
        _lastPartial = text;
        emit('partial', text);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> finish() => close(emitResult: true);

  Future<void> close({required bool emitResult}) async {
    if (_closed) return;
    _closed = true;
    _partials?.cancel();
    await _sub?.cancel();
    try {
      await recorder.stop();
    } catch (_) {}
    try {
      await recorder.dispose();
    } catch (_) {}
    if (!emitResult) {
      owner._ended(this);
      return;
    }
    if (!_gate.heardSpeech || _length < UzbekSttModel.sampleRate ~/ 4) {
      owner._ended(this);
      emit('error', 'nomatch');
      return;
    }
    final w = await worker;
    if (w == null) {
      owner._ended(this);
      emit('error', 'model');
      return;
    }
    final text = (await w.decode(_audio()))?.trim() ?? '';
    owner._ended(this);
    if (text.isEmpty) {
      emit('error', 'nomatch');
    } else {
      emit('final', text);
    }
  }
}

/// Model alohida isolate’da: tanish paytida pult tugmalari qotmaydi.
class _Worker {
  _Worker._(this._isolate, this._inbox, this._send);

  final Isolate _isolate;
  final ReceivePort _inbox;
  final SendPort _send;
  final _pending = <int, Completer<String?>>{};
  int _next = 0;

  static Future<_Worker> spawn(String dir) async {
    final inbox = ReceivePort();
    final first = Completer<Object?>();
    final isolate = await Isolate.spawn(_workerMain, [
      inbox.sendPort,
      dir,
    ], debugName: 'uzbek-stt');
    late final _Worker worker;
    inbox.listen((msg) {
      if (!first.isCompleted) {
        first.complete(msg);
        return;
      }
      if (msg is List && msg.length == 2 && msg[0] is int) {
        worker._pending.remove(msg[0])?.complete(msg[1] as String?);
      }
    });
    final reply = await first.future.timeout(const Duration(seconds: 60));
    if (reply is! SendPort) {
      inbox.close();
      isolate.kill(priority: Isolate.immediate);
      throw StateError('$reply');
    }
    return worker = _Worker._(isolate, inbox, reply);
  }

  Future<String?> decode(Float32List samples) {
    final id = _next++;
    final c = _pending[id] = Completer<String?>();
    _send.send([
      id,
      TransferableTypedData.fromList([samples.buffer.asUint8List()]),
    ]);
    return c.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        return null;
      },
    );
  }

  void dispose() {
    _send.send(null);
    for (final c in _pending.values) {
      c.complete(null);
    }
    _pending.clear();
    _inbox.close();
    Timer(const Duration(seconds: 2), () => _isolate.kill());
  }
}

/// Model papkasidan sherpa-onnx tanuvchisi (NeMo CTC, 16 kHz, 80 mel).
/// Avval `sherpa.initBindings()` chaqirilgan bo‘lishi kerak.
sherpa.OfflineRecognizer createUzbekRecognizer(String dir) =>
    sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        feat: const sherpa.FeatureConfig(
          sampleRate: UzbekSttModel.sampleRate,
          featureDim: 80,
        ),
        model: sherpa.OfflineModelConfig(
          nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
            model: '$dir/model.int8.onnx',
          ),
          tokens: '$dir/tokens.txt',
          numThreads: math.max(
            1,
            math.min(4, Platform.numberOfProcessors ~/ 2),
          ),
          debug: false,
          modelType: 'nemo_ctc',
        ),
      ),
    );

/// Bitta yozuvni matnga aylantiradi.
String recognizeUzbek(
  sherpa.OfflineRecognizer recognizer,
  Float32List samples,
) {
  final stream = recognizer.createStream();
  try {
    stream.acceptWaveform(
      samples: samples,
      sampleRate: UzbekSttModel.sampleRate,
    );
    recognizer.decode(stream);
    return recognizer.getResult(stream).text.trim();
  } finally {
    stream.free();
  }
}

@pragma('vm:entry-point')
void _workerMain(List<Object?> args) {
  final reply = args[0]! as SendPort;
  final dir = args[1]! as String;
  final inbox = ReceivePort();
  final sherpa.OfflineRecognizer recognizer;
  try {
    sherpa.initBindings();
    recognizer = createUzbekRecognizer(dir);
  } catch (e) {
    reply.send('error: $e');
    return;
  }
  reply.send(inbox.sendPort);
  inbox.listen((msg) {
    if (msg is! List) {
      recognizer.free();
      inbox.close();
      return;
    }
    final id = msg[0] as int;
    final samples = (msg[1] as TransferableTypedData)
        .materialize()
        .asFloat32List();
    try {
      reply.send([id, recognizeUzbek(recognizer, samples)]);
    } catch (_) {
      reply.send([id, null]);
    }
  });
}
