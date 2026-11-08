import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:shared_preferences/shared_preferences.dart';

/// Model turi (sherpa-onnx).
enum SttKind {
  /// NeMo CTC: bitta `model.onnx` + `tokens.txt`.
  nemoCtc,

  /// Oqimli (streaming) Zipformer transducer: encoder + decoder + joiner +
  /// `tokens.txt`. Oqimsiz (offline) tanuvchi bilan ochilmaydi — sherpa-onnx
  /// jarayonni to‘xtatadi, shuning uchun turi aniq ko‘rsatiladi.
  streamingTransducer,
}

/// Telefonda, internetsiz o‘zbekcha nutqni tanish modeli.
@immutable
class SttModelSpec {
  const SttModelSpec({
    required this.id,
    required this.name,
    required this.megabytes,
    required this.about,
    required this.credit,
    required this.repo,
    required this.revision,
    required this.files,
    required this.kind,
  });

  /// Saqlash uchun nom (papka va tanlov).
  final String id;

  /// Menyudagi nom: “Aniq”, “Yengil”.
  final String name;

  /// Foydalanuvchiga ko‘rsatiladigan hajm ([bytes] bilan mos).
  final String megabytes;
  final String about;
  final String credit;
  final String repo;
  final String revision;

  /// Repozitoriydagi yo‘l va aniq hajm. Telefonda papkasiz saqlanadi.
  final List<(String, int)> files;
  final SttKind kind;

  int get bytes => files.fold(0, (a, f) => a + f.$2);
  String get folder => 'stt/$id';
  Uri url(String file) =>
      Uri.parse('https://huggingface.co/$repo/resolve/$revision/$file');
  static String local(String file) => file.split('/').last;
}

/// Telefonga yuklanadigan o‘zbekcha modellar.
class UzbekSttModel {
  static const title = 'Internetsiz o‘zbekcha nutq';
  static const sampleRate = 16000;

  /// NVIDIA FastConformer-Hybrid Large (uz, 115M, CC BY 4.0): eng aniq —
  /// FLEURS ~11%, Common Voice ~7% so‘z xatosi. int8, 174 MB.
  static const accurate = SttModelSpec(
    id: 'uz-fastconformer',
    name: 'Aniq',
    megabytes: '174 MB',
    about: 'Eng kam xato. O‘rtacha va kuchli telefonlar uchun.',
    credit: 'NVIDIA FastConformer (uz), CC BY 4.0',
    repo: 'algorithco/stt_uz_fastconformer_hybrid_large_pc',
    // Hugging Face commit (o‘zgarmas): model.int8.onnx sha256
    // c93339f50c1296f51c9dffaa7ce4ec4468ff331a617c58b6ac5b6fa305a8cb8c.
    revision: '1786554e0cdfacb8bf9076b4d9739cb81d2fbb2d',
    files: [('model.int8.onnx', 173888181), ('tokens.txt', 9759)],
    kind: SttKind.nemoCtc,
  );

  /// Vosk (Alpha Cephei) Zipformer2, o‘zbekcha (Apache 2.0): ~2 baravar
  /// yengil, xatosi biroz ko‘p (FLEURS 17,7%).
  static const light = SttModelSpec(
    id: 'uz-vosk-zipformer',
    name: 'Yengil',
    megabytes: '94 MB',
    about: 'Kamroq joy va xotira. Kuchsiz telefonlar uchun.',
    credit: 'Vosk Zipformer2 (uz, Alpha Cephei), Apache 2.0',
    repo: 'alphacep/vosk-model-small-streaming-uz',
    // Hugging Face commit (o‘zgarmas).
    revision: 'e0417cabfbbac4efdc34e7aba367501d126ae79c',
    files: [
      ('am-onnx/encoder.onnx', 90994145),
      ('am-onnx/decoder.onnx', 2093080),
      ('am-onnx/joiner.onnx', 1026462),
      ('lang/tokens.txt', 3957),
    ],
    kind: SttKind.streamingTransducer,
  );

  static const all = [accurate, light];

  static SttModelSpec byId(String? id) =>
      all.where((m) => m.id == id).firstOrNull ?? accurate;
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
  final int total;
  final String error;

  double get progress => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
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

/// Internetsiz nutqni tanish: modellarni yuklash, tanlash, mikrofon va
/// tanish. Natijalar `partial` / `final` / `error` hodisalari bilan qaytadi —
/// telefon tizimining ovozni tanishi bilan bir xil.
class OfflineStt {
  OfflineStt._();
  static final instance = OfflineStt._();

  /// Har bir modelning holati.
  final _status = <String, ValueNotifier<SttModelStatus>>{};

  ValueNotifier<SttModelStatus> statusOf(SttModelSpec m) => _status.putIfAbsent(
    m.id,
    () => ValueNotifier(const SttModelStatus(SttModelPhase.missing)),
  );

  /// Foydalanuvchi tanlagan model (o‘rnatilgan bo‘lsa — shu ishlatiladi).
  final selected = ValueNotifier<SttModelSpec>(UzbekSttModel.accurate);

  /// Har qanday holat o‘zgarishi (menyu va yuklanish yozuvi uchun).
  late final Listenable changes = Listenable.merge([
    selected,
    for (final m in models) statusOf(m),
  ]);

  /// Hozir yuklanayotgan model (bo‘lmasa — null).
  (SttModelSpec, SttModelStatus)? get downloading {
    for (final m in models) {
      final s = statusOf(m).value;
      if (s.phase == SttModelPhase.downloading) return (m, s);
    }
    return null;
  }

  /// Testlar uchun almashtiriladi.
  @visibleForTesting
  List<SttModelSpec> models = UzbekSttModel.all;
  @visibleForTesting
  Future<Directory> Function() baseDir = getApplicationSupportDirectory;
  @visibleForTesting
  Uri Function(SttModelSpec model, String file) urlFor = _url;
  static Uri _url(SttModelSpec m, String file) => m.url(file);

  Future<Directory> modelDir(SttModelSpec m) async =>
      Directory('${(await baseDir()).path}/${m.folder}');

  /* ---------------- Tanlov ---------------- */

  bool _loaded = false;

  Future<void> _loadSelection() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final id = await SharedPreferencesAsync().getString('sttModel');
      if (id != null) selected.value = UzbekSttModel.byId(id);
    } catch (_) {}
  }

  Future<void> select(SttModelSpec m) async {
    _loaded = true;
    if (selected.value.id != m.id) {
      selected.value = m;
      _dropWorker();
    }
    try {
      await SharedPreferencesAsync().setString('sttModel', m.id);
    } catch (_) {}
  }

  /// Tanishda ishlatiladigan model: tanlangani, u bo‘lmasa — o‘rnatilgan
  /// boshqasi; hech biri bo‘lmasa — null (telefon tizimi ishlatiladi).
  Future<SttModelSpec?> active() async {
    await _loadSelection();
    final first = selected.value;
    for (final m in [first, ...models.where((x) => x.id != first.id)]) {
      if (await refresh(m)) return m;
    }
    return null;
  }

  /* ---------------- Model fayllari ---------------- */

  /// Model to‘liq o‘rnatilganmi (fayllar to‘liq hajmda).
  Future<bool> refresh(SttModelSpec m) async {
    final status = statusOf(m);
    if (status.value.phase == SttModelPhase.downloading) return false;
    final ready = await installed(m);
    if (ready) {
      status.value = const SttModelStatus(SttModelPhase.ready);
    } else if (status.value.phase == SttModelPhase.ready) {
      status.value = const SttModelStatus(SttModelPhase.missing);
    }
    return ready;
  }

  Future<bool> installed(SttModelSpec m) async {
    try {
      final dir = await modelDir(m);
      for (final (name, size) in m.files) {
        final f = File('${dir.path}/${SttModelSpec.local(name)}');
        if (!await f.exists() || await f.length() != size) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hammasini tekshirib, menyudagi holatlarni yangilaydi.
  Future<void> refreshAll() async {
    await _loadSelection();
    for (final m in models) {
      await refresh(m);
    }
  }

  final _stop = <String>{};

  /// Yuklab olish va tanlash. Uzilib qolsa, keyingi safar qolgan joyidan
  /// davom etadi.
  Future<void> download(SttModelSpec m) async {
    final status = statusOf(m);
    if (status.value.phase == SttModelPhase.downloading) return;
    if (await installed(m)) {
      status.value = const SttModelStatus(SttModelPhase.ready);
      await select(m);
      return;
    }
    _stop.remove(m.id);
    status.value = SttModelStatus(SttModelPhase.downloading, total: m.bytes);
    void failed(String message) => status.value = SttModelStatus(
      SttModelPhase.failed,
      received: status.value.received,
      total: m.bytes,
      error: message,
    );
    try {
      final dir = await modelDir(m);
      await dir.create(recursive: true);
      var done = 0;
      for (final (name, size) in m.files) {
        final file = File('${dir.path}/${SttModelSpec.local(name)}');
        if (await file.exists() && await file.length() == size) {
          done += size;
          continue;
        }
        final part = File('${file.path}.part');
        final before = done;
        var shown = DateTime(0);
        await _fetch(urlFor(m, name), part, size, m.id, (got) {
          final now = DateTime.now();
          if (now.difference(shown).inMilliseconds < 250) return;
          shown = now;
          status.value = SttModelStatus(
            SttModelPhase.downloading,
            received: before + got,
            total: m.bytes,
          );
        });
        await part.rename(file.path);
        done += size;
      }
      status.value = const SttModelStatus(SttModelPhase.ready);
      await select(m);
    } on _Cancelled {
      status.value = const SttModelStatus(SttModelPhase.missing);
    } on SocketException {
      failed('Internet yo‘q — ulanib, qayta urinib ko‘ring');
    } on TimeoutException {
      failed(
        'Internet sekin — qayta urinib ko‘ring (qolgan joyidan davom etadi)',
      );
    } on FileSystemException catch (e) {
      failed(
        e.osError?.errorCode == 28
            ? 'Telefonda joy yetmadi (${m.megabytes} kerak)'
            : 'Faylni saqlab bo‘lmadi',
      );
    } catch (_) {
      failed('Yuklab bo‘lmadi — qayta urinib ko‘ring');
    }
  }

  /// Yuklashni to‘xtatish (yuklangan qismi saqlanadi).
  void cancelDownload(SttModelSpec m) => _stop.add(m.id);

  Future<void> _fetch(
    Uri url,
    File part,
    int expected,
    String id,
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
            if (_stop.contains(id)) throw _Cancelled();
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
  Future<void> remove(SttModelSpec m) async {
    if (_workerModel?.id == m.id) {
      await cancel();
      _dropWorker();
    }
    try {
      final dir = await modelDir(m);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    statusOf(m).value = const SttModelStatus(SttModelPhase.missing);
    // Boshqasi o‘rnatilgan bo‘lsa — o‘sha tanlanadi.
    if (selected.value.id == m.id) {
      for (final other in models) {
        if (other.id != m.id && await installed(other)) {
          await select(other);
          break;
        }
      }
    }
  }

  /* ---------------- Tanish ---------------- */

  _Worker? _worker;
  SttModelSpec? _workerModel;
  Future<_Worker?>? _loading;
  Timer? _idle;
  _Session? _session;

  bool get listening => _session != null;

  void _dropWorker() {
    _worker?.dispose();
    _worker = null;
    _workerModel = null;
  }

  /// Modelni oldindan yuklab qo‘yish (birinchi bosishda kutmaslik uchun).
  Future<bool> warmUp() async {
    final m = await active();
    return m != null && await _ensureWorker(m) != null;
  }

  Future<_Worker?> _ensureWorker(SttModelSpec m) {
    _idle?.cancel();
    if (_worker != null && _workerModel?.id == m.id) {
      return Future.value(_worker);
    }
    if (_workerModel?.id != m.id) _dropWorker();
    return _loading ??= () async {
      try {
        if (!await installed(m)) return null;
        final w = await _Worker.spawn((await modelDir(m)).path, m.kind);
        _worker = w;
        _workerModel = m;
        return w;
      } catch (_) {
        statusOf(m).value = const SttModelStatus(
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
      if (_session == null) _dropWorker();
    });
  }

  /// Tinglashni boshlaydi. Model yo‘q yoki mikrofon ochilmasa — false
  /// (telefon tizimining ovozni tanishi ishlatiladi).
  Future<bool> start(void Function(String type, String text) emit) async {
    if (_session != null) return false;
    final model = await active();
    if (model == null) return false;
    final worker = _ensureWorker(model);
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

  static Future<_Worker> spawn(String dir, SttKind kind) async {
    final inbox = ReceivePort();
    final first = Completer<Object?>();
    final isolate = await Isolate.spawn(_workerMain, [
      inbox.sendPort,
      dir,
      kind.index,
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

int get _threads => math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

/// Model papkasidagi tanuvchi (16 kHz, 80 mel). Avval
/// `sherpa.initBindings()` chaqirilgan bo‘lishi kerak.
abstract class UzbekRecognizer {
  factory UzbekRecognizer(String dir, SttKind kind) => switch (kind) {
    SttKind.nemoCtc => _OfflineUzbek(
      sherpa.OfflineModelConfig(
        nemoCtc: sherpa.OfflineNemoEncDecCtcModelConfig(
          model: '$dir/model.int8.onnx',
        ),
        tokens: '$dir/tokens.txt',
        numThreads: _threads,
        debug: false,
        modelType: 'nemo_ctc',
      ),
    ),
    SttKind.streamingTransducer => _OnlineUzbek(dir),
  };

  /// Bitta yozuvni matnga aylantiradi.
  String recognize(Float32List samples);

  /// Qaysi rejimda ishlayapti (tekshiruv uchun).
  String get mode;

  void free();
}

class _OfflineUzbek implements UzbekRecognizer {
  _OfflineUzbek(sherpa.OfflineModelConfig model)
    : _r = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          feat: const sherpa.FeatureConfig(
            sampleRate: UzbekSttModel.sampleRate,
            featureDim: 80,
          ),
          model: model,
        ),
      );

  final sherpa.OfflineRecognizer _r;

  @override
  String get mode => 'offline';

  @override
  String recognize(Float32List samples) {
    final stream = _r.createStream();
    try {
      stream.acceptWaveform(
        samples: samples,
        sampleRate: UzbekSttModel.sampleRate,
      );
      _r.decode(stream);
      return _r.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  @override
  void free() => _r.free();
}

class _OnlineUzbek implements UzbekRecognizer {
  _OnlineUzbek(String dir)
    : _r = sherpa.OnlineRecognizer(
        sherpa.OnlineRecognizerConfig(
          feat: const sherpa.FeatureConfig(
            sampleRate: UzbekSttModel.sampleRate,
            featureDim: 80,
          ),
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: '$dir/encoder.onnx',
              decoder: '$dir/decoder.onnx',
              joiner: '$dir/joiner.onnx',
            ),
            tokens: '$dir/tokens.txt',
            numThreads: _threads,
            debug: false,
          ),
          enableEndpoint: false,
        ),
      );

  final sherpa.OnlineRecognizer _r;

  @override
  String get mode => 'online';

  @override
  String recognize(Float32List samples) {
    final stream = _r.createStream();
    try {
      stream.acceptWaveform(
        samples: samples,
        sampleRate: UzbekSttModel.sampleRate,
      );
      // Oxirida biroz jimlik — so‘nggi so‘z ham chiqsin.
      stream.acceptWaveform(
        samples: Float32List(UzbekSttModel.sampleRate ~/ 2),
        sampleRate: UzbekSttModel.sampleRate,
      );
      stream.inputFinished();
      while (_r.isReady(stream)) {
        _r.decode(stream);
      }
      return _r.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  @override
  void free() => _r.free();
}

@pragma('vm:entry-point')
void _workerMain(List<Object?> args) {
  final reply = args[0]! as SendPort;
  final dir = args[1]! as String;
  final kind = SttKind.values[args[2]! as int];
  final inbox = ReceivePort();
  final UzbekRecognizer recognizer;
  try {
    sherpa.initBindings();
    recognizer = UzbekRecognizer(dir, kind);
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
      reply.send([id, recognizer.recognize(samples)]);
    } catch (_) {
      reply.send([id, null]);
    }
  });
}
