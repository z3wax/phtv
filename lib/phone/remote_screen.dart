import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../media_picker.dart';
import '../latin_input.dart';
import '../uzbek_text.dart';
import '../tv/input.dart';
import '../tv/model.dart';
import '../tv/server.dart';
import 'usb_screen.dart';
import 'voice_input.dart';

/// Telefon ekranidagi pult — Apple TV pulti uslubida, to‘liq qora.
///
/// Televizor shu telefonda bo‘lsa — 127.0.0.1, boshqa qurilmadagi
/// televizor (kompyuter, Mac, telefon) bo‘lsa — uning manzili va PIN.
/// Mikrofon tugmasi — AI yordamchi: gapiring, televizor bajaradi va javob beradi.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    super.key,
    required this.host,
    this.pin = '',
    this.port = RemoteServer.defaultPort,
    this.local = false,
    this.onExit,
  });

  final String host;
  final String pin;
  final int port;

  /// Televizor shu telefonning o‘zida (fayl yuborish shu holatda ishlaydi).
  final bool local;
  final VoidCallback? onExit;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  WebSocket? _ws;
  bool _connected = false;
  bool _everConnected = false;
  bool _failed = false; // hali bir marta ham ulanmadi va urinish yiqildi
  bool _disposed = false;
  String _title = '';
  Timer? _retry;

  // Fayl yuborish.
  double? _upProgress;
  String _upStatus = '';
  bool _uploading = false;
  Timer? _upClear;

  // Matn: televizor so‘rasa, klaviatura oynasi ochiladi.
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  String _hint = 'Matn yozish (qidiruv, manzil…)';
  bool _sheetOpen = false;
  bool _latinText = false;
  StateSetter? _sheetState;
  bool _dictating = false;
  bool _startingVoice = false;
  int _voiceSession = 0;
  TextEditingValue _dictationBase = TextEditingValue.empty;

  // AI yordamchi.
  String _lang = 'uz-UZ';
  bool _listening = false;
  String _partial = '';
  DateTime _lastPartial = DateTime(0);
  String _assistPhase = 'idle';
  String _assistQ = '';
  String _assistA = '';
  StreamSubscription<VoiceEvent>? _voice;

  @override
  void initState() {
    super.initState();
    _connect();
    VoiceInput.loadLanguage().then((l) {
      if (mounted) setState(() => _lang = l);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _voiceSession++;
    _retry?.cancel();
    _upClear?.cancel();
    _voice?.cancel();
    if (_listening) VoiceInput.instance.cancel();
    _ws?.close();
    _text.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  /* ---------------- Aloqa ---------------- */

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final uri =
          'ws://${widget.host}:${widget.port}/ws?k=${Uri.encodeQueryComponent(widget.pin)}';
      final ws = await WebSocket.connect(
        uri,
      ).timeout(const Duration(seconds: 6));
      if (_disposed) {
        ws.close();
        return;
      }
      _ws = ws;
      setState(() {
        _connected = true;
        _everConnected = true;
      });
      ws.listen(
        _onMessage,
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
    } catch (_) {
      _lost();
    }
  }

  void _lost() {
    _ws = null;
    if (_disposed) return;
    if (_connected || (!_everConnected && !_failed)) {
      setState(() {
        _connected = false;
        _failed = !_everConnected;
      });
    }
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 1500), _connect);
  }

  void _send(Map<String, Object?> msg) => _ws?.add(jsonEncode(msg));

  void _cmd(Cmd c) {
    HapticFeedback.selectionClick();
    _send({'t': 'cmd', 'c': c.name});
  }

  Future<void> _onMessage(Object? data) async {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map || !mounted) return;
    final Map<Object?, Object?> m = decoded;
    switch (m['t']) {
      case 'state':
        setState(() {
          _title = (m['title'] as String?) ?? '';
        });
      case 'textFocus':
        // Televizor matn so‘radi — klaviatura oynasini ochamiz.
        _latinText = m['latin'] == true;
        final value = m['value'] as String? ?? '';
        _text.text = _latinText ? uzbekToLatin(value) : value;
        _sheetState?.call(() {});
        _hint = m['hint'] as String? ?? 'Matn';
        if (!_sheetOpen) _openKeyboard();
      case 'assist':
        setState(() {
          _assistPhase = m['phase'] as String? ?? 'idle';
          _assistQ = m['q'] as String? ?? '';
          _assistA = m['a'] as String? ?? '';
        });
        if (_assistPhase == 'done') HapticFeedback.lightImpact();
      case 'pick':
        if (widget.local) await _sendFiles(gallery: m['gallery'] == true);
      case 'usb':
        if (widget.local) _openUsb();
    }
  }

  void _openUsb() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => UsbScreen(onExit: () => Navigator.of(ctx).pop()),
    ),
  );

  /* ---------------- AI yordamchi (mikrofon) ---------------- */

  void _refreshVoice() {
    if (!mounted) return;
    setState(() {});
    _sheetState?.call(() {});
  }

  void _writeDictation(String words) {
    final value = _dictationBase;
    final start = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final end = value.selection.isValid
        ? value.selection.end
        : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, words),
      selection: TextSelection.collapsed(offset: start + words.length),
    );
  }

  Future<void> _mic({bool dictation = false}) async {
    if (_startingVoice) return;
    if (_listening) {
      HapticFeedback.lightImpact();
      await VoiceInput.instance.stop();
      return;
    }
    HapticFeedback.mediumImpact();
    _dictating = dictation;
    if (dictation) _dictationBase = _text.value;
    _startingVoice = true;
    final session = ++_voiceSession;
    _voice ??= VoiceInput.instance.events.listen(_onVoice);
    final ok = await VoiceInput.instance.start(_lang);
    if (session != _voiceSession || !mounted) {
      await VoiceInput.instance.cancel();
      return;
    }
    _startingVoice = false;
    if (!ok) {
      // Ovozni tanish yo‘q — savolni yozib yuborish.
      if (dictation) {
        _textFocus.requestFocus();
        _snack('Klaviaturadagi 🎤 orqali gapiring yoki matn yozing');
        return;
      }
      _hint = 'Savol yoki buyruq (klaviaturadagi 🎤 ham ishlaydi)';
      _text.clear();
      _openKeyboard(ask: true);
      return;
    }
    setState(() {
      _listening = true;
      _partial = '';
    });
    _refreshVoice();
    if (!dictation) _send({'t': 'listen', 'phase': 'start'});
  }

  void _onVoice(VoiceEvent e) {
    if (!mounted) return;
    if (!_listening && !_startingVoice) return;
    final words = (_lang == 'uz-UZ' || (_dictating && _latinText))
        ? uzbekToLatin(e.text)
        : e.text;
    switch (e.type) {
      case 'partial':
        setState(() => _partial = words);
        if (_dictating) {
          _writeDictation(words);
          return;
        }
        final now = DateTime.now();
        if (now.difference(_lastPartial).inMilliseconds > 200) {
          _lastPartial = now;
          _send({'t': 'listen', 'phase': 'partial', 'v': words});
        }
      case 'final':
        setState(() {
          _listening = false;
          _partial = words;
        });
        _refreshVoice();
        if (_dictating) {
          _dictating = false;
          _writeDictation(words);
          _textFocus.requestFocus();
          return;
        }
        if (words.trim().isEmpty) {
          _send({'t': 'listen', 'phase': 'cancel'});
        } else {
          HapticFeedback.mediumImpact();
          _send({'t': 'ask', 'v': words.trim()});
        }
      case 'error':
        setState(() => _listening = false);
        final msg = switch (e.text) {
          'permission' => 'Mikrofonga ruxsat bering: Sozlamalar → z3wax TV',
          'language' =>
            'Telefon bu tilni tanimaydi — mikrofonni bosib turib boshqa tilni tanlang',
          'network' => 'Ovozni tanish uchun internet kerak',
          'busy' => 'Mikrofon band, birozdan so‘ng urinib ko‘ring',
          _ => 'Eshitilmadi — qayta gapiring',
        };
        if (!_dictating) _send({'t': 'listen', 'phase': 'error', 'v': msg});
        _dictating = false;
        _refreshVoice();
        _snack(msg);
    }
  }

  Future<void> _chooseLanguage() async {
    HapticFeedback.mediumImpact();
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111113),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Qaysi tilda gapirasiz?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            for (final e in VoiceInput.languages.entries)
              ListTile(
                leading: Icon(
                  e.key == _lang
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(e.value),
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _lang = v);
    await VoiceInput.saveLanguage(v);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1C1C1E),
        ),
      );
  }

  /* ---------------- Klaviatura ---------------- */

  Future<void> _openKeyboard({bool ask = false}) async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111113),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          _sheetState = update;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _text,
                    inputFormatters: _latinText
                        ? [const UzbekLatinFormatter()]
                        : null,
                    focusNode: _textFocus,
                    autofocus: true,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      Navigator.pop(ctx);
                      ask ? _askTyped() : _sendText();
                    },
                    style: const TextStyle(fontSize: 17),
                    decoration: InputDecoration(
                      hintText: ask ? 'Savol yoki buyruq' : _hint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: _listening
                            ? 'Tinglashni tugatish'
                            : 'Ovoz bilan yozish',
                        icon: Icon(
                          _listening && _dictating
                              ? Icons.stop_circle_rounded
                              : Icons.mic_rounded,
                        ),
                        onPressed: () => _mic(dictation: true),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1C1C1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: _SheetButton(
                      label: 'Bo‘sh joy (Space)',
                      icon: Icons.space_bar_rounded,
                      onTap: _insertSpace,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SheetButton(
                          label: 'AI’dan so‘rash',
                          icon: Icons.auto_awesome_rounded,
                          primary: ask,
                          onTap: () {
                            Navigator.pop(ctx);
                            _askTyped();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SheetButton(
                          label: 'Yuborish',
                          icon: Icons.send_rounded,
                          primary: !ask,
                          onTap: () {
                            Navigator.pop(ctx);
                            _sendText();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    _sheetState = null;
    _sheetOpen = false;
    if (_dictating) {
      _voiceSession++;
      _startingVoice = false;
      _listening = false;
      _dictating = false;
      await VoiceInput.instance.cancel();
      _refreshVoice();
    }
  }

  void _insertSpace() {
    final value = _text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _text.value = value.copyWith(
      text: value.text.replaceRange(start, end, ' '),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
    _textFocus.requestFocus();
  }

  void _sendText() {
    _send({
      't': 'text',
      'v': _latinText ? uzbekToLatin(_text.text) : _text.text,
    });
    HapticFeedback.lightImpact();
  }

  void _askTyped() {
    final q = _text.text.trim();
    if (q.isEmpty) return;
    _send({'t': 'ask', 'v': q});
    _text.clear();
    HapticFeedback.lightImpact();
  }

  /* ---------------- Fayl yuborish ---------------- */

  Future<void> _chooseFiles() async {
    final gallery = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF111113),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Telefondan video / rasm / musiqa yuborish',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Galereya — video va rasmlar'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Fayllar — musiqa va boshqalar'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (gallery != null) await _sendFiles(gallery: gallery);
  }

  void _status(String s, {double? progress}) {
    if (!mounted) return;
    _upClear?.cancel();
    setState(() {
      _upStatus = s;
      _upProgress = progress;
    });
    if (progress == null) {
      _upClear = Timer(const Duration(seconds: 5), () {
        if (mounted && !_uploading) setState(() => _upStatus = '');
      });
    }
  }

  Future<void> _sendFiles({required bool gallery}) async {
    try {
      final items = await pickMedia(gallery: gallery);
      if (items.isEmpty) return;
      if (widget.local) {
        // Televizor shu telefonning o‘zida — fayl yo‘lini yuborish kifoya.
        _send({
          't': 'media',
          'items': [for (final i in items) i.toJson()],
        });
        _status('✓ ${items.length} ta fayl televizorda');
      } else {
        await _upload(items);
      }
    } catch (_) {
      _status('✗ Fayllarni ochib bo‘lmadi');
    }
  }

  /// Fayllarni boshqa qurilmadagi televizorga (kompyuter, Mac, telefon)
  /// Wi-Fi yoki USB kabel orqali yuklaydi — foiz bilan.
  Future<void> _upload(List<MediaItem> items) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final client = HttpClient();
    try {
      for (var i = 0; i < items.length; i++) {
        final file = File(items[i].source);
        final name = file.uri.pathSegments.last;
        final total = await file.length();
        var sent = 0;
        final prefix = items.length > 1 ? '${i + 1}/${items.length}: ' : '';
        void show() {
          final p = total > 0 ? sent / total : 0.0;
          _status('$prefix$name — ${(p * 100).round()}%', progress: p);
        }

        show();
        final uri = Uri(
          scheme: 'http',
          host: widget.host,
          port: widget.port,
          path: '/upload',
          queryParameters: {
            'k': widget.pin,
            'name': name,
            'index': '$i',
            'count': '${items.length}',
          },
        );
        final req = await client.postUrl(uri);
        req.contentLength = total;
        var lastShown = 0;
        await req.addStream(
          file.openRead().map((chunk) {
            sent += chunk.length;
            if (sent - lastShown > total ~/ 100 || sent == total) {
              lastShown = sent;
              show();
            }
            return chunk;
          }),
        );
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        if (!mounted) return;
        String? error;
        if (res.statusCode != 200) {
          try {
            error = (jsonDecode(body) as Map)['error'] as String?;
          } catch (_) {}
          error ??= 'xato ${res.statusCode}';
        }
        _status(error == null ? '✓ $name yuborildi' : '✗ $error');
      }
    } catch (_) {
      _status('✗ Aloqa uzildi');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _uploading = false);
    }
  }

  /* ---------------- Ko‘rinish ---------------- */

  @override
  Widget build(BuildContext context) {
    final assistVisible =
        _listening ||
        (_assistPhase != 'idle' &&
            (_assistQ.isNotEmpty || _assistA.isNotEmpty));
    return Focus(
      autofocus: true,
      // Telefonga ulangan Bluetooth pult / klaviatura ham televizorni boshqaradi.
      onKeyEvent: (_, e) {
        // Telefonning ovoz tugmalari — televizor ovozi.
        if (e is! KeyUpEvent) {
          final vol = switch (e.logicalKey) {
            LogicalKeyboardKey.audioVolumeUp => Cmd.volUp,
            LogicalKeyboardKey.audioVolumeDown => Cmd.volDown,
            _ => null,
          };
          if (vol != null) {
            _cmd(vol);
            return KeyEventResult.handled;
          }
        } else if (e.logicalKey == LogicalKeyboardKey.audioVolumeUp ||
            e.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
          return KeyEventResult.handled;
        }
        final c = TvInput.commandForKey(e);
        if (c == null) return KeyEventResult.ignored;
        _cmd(c);
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  SizedBox(
                    height: 22,
                    child: Text(
                      _title.isNotEmpty
                          ? 'Ekranda: $_title'
                          : widget.local
                          ? 'Televizorga qarang — bu yerda boshqaring'
                          : '${widget.host}:${widget.port}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: FittedBox(
                        child: _RemoteBody(
                          listening: _listening,
                          onCmd: _cmd,
                          onMic: _mic,
                          onMicLong: _chooseLanguage,
                          onUpload: _uploading ? null : _chooseFiles,
                          onKeyboard: () {
                            _hint = 'Matn yozish (qidiruv, manzil…)';
                            _openKeyboard();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 14,
                right: 14,
                top: 58,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: assistVisible
                      ? _AssistBubble(
                          key: const ValueKey('assist'),
                          listening: _listening,
                          question: _listening ? _partial : _assistQ,
                          answer: _listening ? '' : _assistA,
                          phase: _assistPhase,
                          onClose: () => setState(() {
                            _assistPhase = 'idle';
                            _assistQ = _assistA = '';
                          }),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              if (_upStatus.isNotEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 12,
                  child: _UploadPill(status: _upStatus, progress: _upProgress),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 0),
      child: Row(
        children: [
          if (widget.onExit != null)
            IconButton(
              onPressed: widget.onExit,
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            )
          else
            const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'z3wax TV',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _chooseLanguage,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Text(
                _lang.substring(0, 2).toUpperCase(),
                style: const TextStyle(fontSize: 12, color: Color(0xFFAEAEB2)),
              ),
            ),
          ),
          if (widget.local)
            IconButton(
              tooltip: 'USB fleshka',
              onPressed: _openUsb,
              icon: const Icon(Icons.usb_rounded, color: Colors.white70),
            ),
          Flexible(
            flex: 3,
            child: _Status(
              connected: _connected,
              failed: _failed && !_everConnected,
            ),
          ),
        ],
      ),
    );
  }
}

/* ======================= Pult tanasi ======================= */

const _ink = Color(0xFFF2F2F7);

/// Apple TV pulti shaklidagi qora tana: sensorli panel, tugmalar,
/// Siri’ga o‘xshash mikrofon tugmasi.
class _RemoteBody extends StatelessWidget {
  const _RemoteBody({
    required this.listening,
    required this.onCmd,
    required this.onMic,
    required this.onMicLong,
    required this.onUpload,
    required this.onKeyboard,
  });

  final bool listening;
  final ValueChanged<Cmd> onCmd;
  final VoidCallback onMic;
  final VoidCallback onMicLong;
  final VoidCallback? onUpload;
  final VoidCallback onKeyboard;

  static const width = 250.0;
  static const keySize = 70.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(56),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1C1C1F), Color(0xFF0D0D0F), Color(0xFF060607)],
          stops: [0, 0.45, 1],
        ),
        border: Border.all(color: const Color(0xFF2A2A2E), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14FFFFFF),
            blurRadius: 1,
            offset: Offset(0, -1),
          ),
          BoxShadow(color: Colors.black, blurRadius: 40, offset: Offset(0, 24)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Mikrofon teshigi: tinglayotganda yonadi.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 18,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: listening
                        ? const Color(0xFF5AC8FA)
                        : const Color(0xFF2C2C2E),
                    boxShadow: listening
                        ? const [
                            BoxShadow(color: Color(0xAA5AC8FA), blurRadius: 10),
                          ]
                        : null,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _RoundKey(
                    label: 'Yoqish / o‘chirish',
                    size: 34,
                    icon: Icons.power_settings_new_rounded,
                    iconSize: 18,
                    outlined: true,
                    onTap: () => onCmd(Cmd.power),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ClickPad(size: 206, onCmd: onCmd),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _RoundKey(
                    label: 'Orqaga',
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 24,
                    onTap: () => onCmd(Cmd.back),
                  ),
                  const SizedBox(height: 14),
                  _RoundKey(
                    label: 'Pauza',
                    icon: Icons.play_arrow_rounded,
                    icon2: Icons.pause_rounded,
                    onTap: () => onCmd(Cmd.playPause),
                  ),
                  const SizedBox(height: 14),
                  _RoundKey(
                    label: 'Ovozsiz',
                    icon: Icons.volume_off_rounded,
                    onTap: () => onCmd(Cmd.mute),
                  ),
                ],
              ),
              const SizedBox(width: 26),
              Column(
                children: [
                  _RoundKey(
                    label: 'Bosh ekran',
                    icon: Icons.tv_rounded,
                    onTap: () => onCmd(Cmd.home),
                  ),
                  const SizedBox(height: 14),
                  _VolumeRocker(
                    width: keySize,
                    height: keySize * 2 + 14,
                    onUp: () => onCmd(Cmd.volUp),
                    onDown: () => onCmd(Cmd.volDown),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SiriButton(
            listening: listening,
            onTap: onMic,
            onLongPress: onMicLong,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 206,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundKey(
                  label: 'Oldingi',
                  size: 42,
                  iconSize: 20,
                  icon: Icons.skip_previous_rounded,
                  onTap: () => onCmd(Cmd.prev),
                ),
                _RoundKey(
                  label: 'Keyingi',
                  size: 42,
                  iconSize: 20,
                  icon: Icons.skip_next_rounded,
                  onTap: () => onCmd(Cmd.next),
                ),
                _RoundKey(
                  label: 'Fayl yuborish',
                  size: 42,
                  iconSize: 20,
                  icon: Icons.upload_rounded,
                  onTap: onUpload,
                ),
                _RoundKey(
                  label: 'Klaviatura',
                  size: 42,
                  iconSize: 20,
                  icon: Icons.keyboard_rounded,
                  onTap: onKeyboard,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Qora dumaloq tugma (bosilganda biroz botadi).
class _RoundKey extends StatefulWidget {
  const _RoundKey({
    required this.label,
    required this.icon,
    required this.onTap,
    this.icon2,
    this.size = _RemoteBody.keySize,
    this.iconSize = 26,
    this.outlined = false,
  });
  final String label;
  final IconData icon;
  final IconData? icon2;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool outlined;

  @override
  State<_RoundKey> createState() => _RoundKeyState();
}

class _RoundKeyState extends State<_RoundKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      label: widget.label,
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.outlined
                  ? null
                  : RadialGradient(
                      center: const Alignment(-0.3, -0.5),
                      radius: 1.1,
                      colors: _down
                          ? const [Color(0xFF2A2A2D), Color(0xFF0E0E10)]
                          : const [Color(0xFF1B1B1E), Color(0xFF030303)],
                    ),
              border: Border.all(
                color: widget.outlined
                    ? const Color(0xFF3A3A3C)
                    : const Color(0xFF242427),
                width: widget.outlined ? 1.4 : 1,
              ),
              boxShadow: widget.outlined
                  ? null
                  : const [
                      BoxShadow(
                        color: Colors.black,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
            child: Opacity(
              opacity: enabled ? 1 : 0.35,
              child: widget.icon2 == null
                  ? Icon(widget.icon, color: _ink, size: widget.iconSize)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.icon,
                          color: _ink,
                          size: widget.iconSize - 4,
                        ),
                        Icon(
                          widget.icon2,
                          color: _ink,
                          size: widget.iconSize - 6,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uzun ovoz tugmasi: + tepada, − pastda.
class _VolumeRocker extends StatefulWidget {
  const _VolumeRocker({
    required this.width,
    required this.height,
    required this.onUp,
    required this.onDown,
  });
  final double width, height;
  final VoidCallback onUp, onDown;

  @override
  State<_VolumeRocker> createState() => _VolumeRockerState();
}

class _VolumeRockerState extends State<_VolumeRocker> {
  int _down = 0; // 1 — tepasi, -1 — pasti

  Widget _half(int dir, String label, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        container: true,
        label: label,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = dir),
          onTapCancel: () => setState(() => _down = 0),
          onTapUp: (_) {
            setState(() => _down = 0);
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            color: _down == dir ? const Color(0x22FFFFFF) : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(icon, color: _ink, size: 28),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.width / 2;
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1E), Color(0xFF030303)],
        ),
        border: Border.all(color: const Color(0xFF242427)),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Column(
          children: [
            _half(1, 'Ovozni oshirish', Icons.add_rounded, widget.onUp),
            _half(
              -1,
              'Ovozni pasaytirish',
              Icons.remove_rounded,
              widget.onDown,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sensorli dumaloq panel: surish — yo‘nalish, o‘rtasi — OK, chetlari —
/// o‘sha tomonga. Saytlarda ham shunday: ↑↓←→ — tanlash, OK — bosish.
class _ClickPad extends StatefulWidget {
  const _ClickPad({required this.size, required this.onCmd});
  final double size;
  final ValueChanged<Cmd> onCmd;

  @override
  State<_ClickPad> createState() => _ClickPadState();
}

class _ClickPadState extends State<_ClickPad> {
  Offset _acc = Offset.zero;
  Cmd? _pressed;

  Cmd _zone(Offset p) {
    final r = widget.size / 2;
    final d = p - Offset(r, r);
    if (d.distance < r * 0.56) return Cmd.ok;
    return d.dx.abs() > d.dy.abs()
        ? (d.dx > 0 ? Cmd.right : Cmd.left)
        : (d.dy > 0 ? Cmd.down : Cmd.up);
  }

  void _press(Cmd c) {
    setState(() => _pressed = c);
    widget.onCmd(c);
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (mounted && _pressed == c) setState(() => _pressed = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final inner = s * 0.56;
    Widget dot(Alignment a) => Align(
      alignment: a,
      child: Padding(
        padding: EdgeInsets.all(s * 0.075),
        child: Container(
          width: 4.5,
          height: 4.5,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0x88FFFFFF),
          ),
        ),
      ),
    );
    final ring = _pressed != null && _pressed != Cmd.ok;
    return Semantics(
      container: true,
      label: 'Yo‘nalish paneli',
      child: GestureDetector(
        onTapUp: (d) => _press(_zone(d.localPosition)),
        onPanStart: (_) => _acc = Offset.zero,
        onPanUpdate: (d) {
          _acc += d.delta;
          const step = 36.0;
          if (_acc.dx.abs() > step || _acc.dy.abs() > step) {
            _press(
              _acc.dx.abs() > _acc.dy.abs()
                  ? (_acc.dx > 0 ? Cmd.right : Cmd.left)
                  : (_acc.dy > 0 ? Cmd.down : Cmd.up),
            );
            _acc = Offset.zero;
          }
        },
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(0, -0.25),
              radius: 0.75,
              colors: [Color(0xFF141416), Color(0xFF020202)],
            ),
            border: Border.all(color: const Color(0xFF26262A), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              if (ring)
                Positioned.fill(
                  child: CustomPaint(painter: _WedgePainter(_pressed!)),
                ),
              dot(Alignment.topCenter),
              dot(Alignment.bottomCenter),
              dot(Alignment.centerLeft),
              dot(Alignment.centerRight),
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  width: inner,
                  height: inner,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.2, -0.4),
                      colors: _pressed == Cmd.ok
                          ? const [Color(0xFF2C2C30), Color(0xFF0C0C0E)]
                          : const [Color(0xFF111113), Color(0xFF000000)],
                    ),
                    border: Border.all(color: const Color(0xFF2A2A2D)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bosilgan tomonning yengil yorug‘ ko‘rinishi.
class _WedgePainter extends CustomPainter {
  _WedgePainter(this.cmd);
  final Cmd cmd;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final angle = switch (cmd) {
      Cmd.right => 0.0,
      Cmd.down => math.pi / 2,
      Cmd.left => math.pi,
      _ => -math.pi / 2,
    };
    final paint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0x00FFFFFF), Color(0x26FFFFFF)],
        stops: const [0.55, 1],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      angle - math.pi / 4,
      math.pi / 2,
      true,
      paint,
    );
  }

  @override
  bool shouldRepaint(_WedgePainter old) => old.cmd != cmd;
}

/// Siri tugmasi: bosing — gapiring, yana bosing — tamom. Bosib turing — til.
class _SiriButton extends StatefulWidget {
  const _SiriButton({
    required this.listening,
    required this.onTap,
    required this.onLongPress,
  });
  final bool listening;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_SiriButton> createState() => _SiriButtonState();
}

class _SiriButtonState extends State<_SiriButton>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_SiriButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.listening) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const siri = [
      Color(0xFFFF2D55),
      Color(0xFFAF52DE),
      Color(0xFF5AC8FA),
      Color(0xFF34C759),
      Color(0xFFFF2D55),
    ];
    return Semantics(
      container: true,
      label: 'Yordamchi (mikrofon)',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (context, child) => Container(
            width: 176,
            height: 56,
            padding: EdgeInsets.all(widget.listening ? 2.2 : 1.4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: SweepGradient(
                colors: widget.listening
                    ? siri
                    : const [
                        Color(0xFF3A3A3C),
                        Color(0xFF5E5CE6),
                        Color(0xFF3A3A3C),
                        Color(0xFF2C2C2E),
                        Color(0xFF3A3A3C),
                      ],
                transform: GradientRotation(_spin.value * 2 * math.pi),
              ),
              boxShadow: widget.listening
                  ? const [BoxShadow(color: Color(0x88AF52DE), blurRadius: 22)]
                  : const [
                      BoxShadow(
                        color: Colors.black,
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
            ),
            child: child,
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF151517), Color(0xFF020202)],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.listening
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_rounded,
                  color: _ink,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.listening ? 'Tinglayapman…' : 'Yordamchi',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ======================= Yordamchi oynalar ======================= */

class _AssistBubble extends StatelessWidget {
  const _AssistBubble({
    super.key,
    required this.listening,
    required this.question,
    required this.answer,
    required this.phase,
    required this.onClose,
  });
  final bool listening;
  final String question;
  final String answer;
  final String phase;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final thinking = phase == 'thinking';
    final error = phase == 'error';
    return GestureDetector(
      onTap: onClose,
      child: Container(
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF2D55), Color(0xFFAF52DE), Color(0xFF5AC8FA)],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            color: const Color(0xF20B0B0D),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    listening ? Icons.mic_rounded : Icons.auto_awesome_rounded,
                    size: 16,
                    color: const Color(0xFFAF52DE),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      question.isEmpty
                          ? (listening ? 'Gapiring…' : '')
                          : question,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFFAEAEB2),
                      ),
                    ),
                  ),
                ],
              ),
              if (thinking)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: Color(0xFFAF52DE),
                    backgroundColor: Color(0xFF1C1C1E),
                  ),
                ),
              if (answer.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    answer,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: error ? const Color(0xFFFBBF24) : Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadPill extends StatelessWidget {
  const _UploadPill({required this.status, required this.progress});
  final String status;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Color(0xFFE5E5EA)),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: const Color(0xFF2C2C2E),
                color: const Color(0xFF34C759),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: primary ? Colors.white : const Color(0xFF1C1C1E),
          foregroundColor: primary ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.connected, required this.failed});
  final bool connected;

  /// Hali ulanmagan va urinish yiqildi (brauzer pultidagi kabi xabar).
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF30D158) : const Color(0xFFFFD60A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF111113),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              connected
                  ? 'Ulangan'
                  : failed
                  ? 'PIN noto‘g‘ri yoki TV o‘chiq'
                  : 'Ulanmoqda…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
