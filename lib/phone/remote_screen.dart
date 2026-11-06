import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../media_picker.dart';
import '../tv/input.dart';
import '../tv/model.dart';
import '../tv/server.dart';
import 'usb_screen.dart';

/// Telefon ekranidagi pult. Televizor shu telefonda bo‘lsa — 127.0.0.1,
/// boshqa telefondagi televizor bo‘lsa — uning Wi-Fi manzili va PIN.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    super.key,
    required this.host,
    this.pin = '',
    this.local = false,
    this.onExit,
  });

  final String host;
  final String pin;

  /// Televizor shu telefonning o‘zida (fayl yuborish shu holatda ishlaydi).
  final bool local;
  final VoidCallback? onExit;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  WebSocket? _ws;
  bool _connected = false;
  bool _disposed = false;
  String _title = '';
  Timer? _retry;
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _ws?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    try {
      final uri =
          'ws://${widget.host}:${RemoteServer.defaultPort}/ws?k=${Uri.encodeQueryComponent(widget.pin)}';
      final ws = await WebSocket.connect(
        uri,
      ).timeout(const Duration(seconds: 6));
      if (_disposed) {
        ws.close();
        return;
      }
      _ws = ws;
      setState(() => _connected = true);
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
    if (_connected) setState(() => _connected = false);
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
        setState(() => _title = (m['title'] as String?) ?? '');
      case 'textFocus':
        _keyboard(
          hint: m['hint'] as String? ?? 'Matn',
          value: m['value'] as String? ?? '',
        );
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
      } else {
        await _upload(items);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fayllarni ochib bo‘lmadi')),
        );
      }
    }
  }

  /// Fayllarni boshqa qurilmadagi televizorga (Ubuntu kompyuter yoki telefon)
  /// Wi-Fi yoki USB kabel orqali yuklaydi.
  Future<void> _upload(List<MediaItem> items) async {
    final messenger = ScaffoldMessenger.of(context);
    final client = HttpClient();
    var ok = 0;
    try {
      for (var i = 0; i < items.length; i++) {
        final file = File(items[i].source);
        final name = file.uri.pathSegments.last;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Yuborilmoqda ${i + 1}/${items.length}: $name'),
            duration: const Duration(minutes: 10),
          ),
        );
        final uri = Uri(
          scheme: 'http',
          host: widget.host,
          port: RemoteServer.defaultPort,
          path: '/upload',
          queryParameters: {
            'k': widget.pin,
            'name': name,
            'index': '$i',
            'count': '${items.length}',
          },
        );
        final req = await client.postUrl(uri);
        req.contentLength = await file.length();
        await req.addStream(file.openRead());
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 200) ok++;
        messenger.hideCurrentSnackBar();
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
    } finally {
      client.close(force: true);
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok == items.length
              ? '$ok ta fayl televizorga yuborildi'
              : '${items.length - ok} ta fayl yuborilmadi',
        ),
      ),
    );
  }

  Future<void> _keyboard({
    String hint = 'Matn yozish',
    String value = '',
  }) async {
    if (_keyboardOpen) return;
    _keyboardOpen = true;
    final controller = TextEditingController(text: value);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1D24),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: () => Navigator.pop(ctx, controller.text),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
    _keyboardOpen = false;
    controller.dispose();
    if (text != null) _send({'t': 'text', 'v': text});
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      // Telefonga ulangan Bluetooth pult / klaviatura ham televizorni boshqaradi.
      onKeyEvent: (_, e) {
        final c = TvInput.commandForKey(e);
        if (c == null) return KeyEventResult.ignored;
        _cmd(c);
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0E12),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.1),
              radius: 1.3,
              colors: [Color(0xFF262A3D), Color(0xFF0D0E12)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final pad = math
                    .min(box.maxWidth - 64, box.maxHeight * 0.42)
                    .clamp(200.0, 340.0);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (widget.onExit != null)
                            IconButton(
                              onPressed: widget.onExit,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          const Icon(Icons.tv_rounded, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.local
                                  ? 'Telefon TV — pult'
                                  : 'Pult · ${widget.host}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _Status(connected: _connected),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 22,
                        child: Text(
                          _title.isEmpty
                              ? (widget.local
                                    ? 'Televizorga qarang — bu yerda boshqaring'
                                    : '')
                              : 'Ekranda: $_title',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9AA3C7),
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _TouchPad(size: pad, onCmd: _cmd),
                      const Spacer(),
                      Row(
                        children: [
                          _Key(
                            icon: Icons.arrow_back_ios_new_rounded,
                            label: 'Orqaga',
                            onTap: () => _cmd(Cmd.back),
                          ),
                          _Key(
                            icon: Icons.tv_rounded,
                            label: 'Bosh',
                            onTap: () => _cmd(Cmd.home),
                          ),
                          _Key(
                            icon: Icons.play_arrow_rounded,
                            label: 'Pauza',
                            onTap: () => _cmd(Cmd.playPause),
                          ),
                          _Key(
                            icon: Icons.volume_off_rounded,
                            label: 'Ovozsiz',
                            onTap: () => _cmd(Cmd.mute),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _Key(
                            icon: Icons.skip_previous_rounded,
                            label: 'Oldingi',
                            onTap: () => _cmd(Cmd.prev),
                          ),
                          _Key(
                            icon: Icons.remove_rounded,
                            label: 'Ovoz',
                            onTap: () => _cmd(Cmd.volDown),
                          ),
                          _Key(
                            icon: Icons.add_rounded,
                            label: 'Ovoz',
                            onTap: () => _cmd(Cmd.volUp),
                          ),
                          _Key(
                            icon: Icons.skip_next_rounded,
                            label: 'Keyingi',
                            onTap: () => _cmd(Cmd.next),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _Key(
                            icon: Icons.keyboard_rounded,
                            label: 'Yozish',
                            onTap: () => _keyboard(),
                            wide: true,
                          ),
                          _Key(
                            icon: Icons.upload_rounded,
                            label: 'Fayl yuborish',
                            onTap: () => _sendFiles(gallery: true),
                          ),
                          if (widget.local) ...[
                            _Key(
                              icon: Icons.usb_rounded,
                              label: 'USB fleshka',
                              onTap: _openUsb,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: connected ? const Color(0xFF0F2E1C) : const Color(0xFF3A2A10),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: connected ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'Ulangan' : 'Ulanmoqda…',
          style: TextStyle(
            fontSize: 13,
            color: connected
                ? const Color(0xFF4ADE80)
                : const Color(0xFFFBBF24),
          ),
        ),
      ],
    ),
  );
}

/// Apple TV pultidagidek dumaloq sensorli panel: surish — yo‘nalish,
/// o‘rtasiga bosish — OK, chetiga bosish — o‘sha tomonga.
class _TouchPad extends StatefulWidget {
  const _TouchPad({required this.size, required this.onCmd});
  final double size;
  final ValueChanged<Cmd> onCmd;

  @override
  State<_TouchPad> createState() => _TouchPadState();
}

class _TouchPadState extends State<_TouchPad> {
  Offset _acc = Offset.zero;
  bool _pressed = false;

  void _tap(Offset p) {
    final r = widget.size / 2;
    final d = p - Offset(r, r);
    if (d.distance < r * 0.38) {
      widget.onCmd(Cmd.ok);
    } else {
      widget.onCmd(
        d.dx.abs() > d.dy.abs()
            ? (d.dx > 0 ? Cmd.right : Cmd.left)
            : (d.dy > 0 ? Cmd.down : Cmd.up),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget arrow(IconData i, Alignment a) => Align(
      alignment: a,
      child: Padding(
        padding: EdgeInsets.all(s * 0.06),
        child: Icon(i, color: Colors.white38, size: s * 0.09),
      ),
    );
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (d) {
        setState(() => _pressed = false);
        _tap(d.localPosition);
      },
      onPanStart: (_) => _acc = Offset.zero,
      onPanUpdate: (d) {
        _acc += d.delta;
        const step = 38.0;
        if (_acc.dx.abs() > step || _acc.dy.abs() > step) {
          widget.onCmd(
            _acc.dx.abs() > _acc.dy.abs()
                ? (_acc.dx > 0 ? Cmd.right : Cmd.left)
                : (_acc.dy > 0 ? Cmd.down : Cmd.up),
          );
          _acc = Offset.zero;
        }
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: s,
          height: s,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              colors: [Color(0xFF3B3E4B), Color(0xFF1B1D25)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: Stack(
            children: [
              arrow(Icons.keyboard_arrow_up_rounded, Alignment.topCenter),
              arrow(Icons.keyboard_arrow_down_rounded, Alignment.bottomCenter),
              arrow(Icons.keyboard_arrow_left_rounded, Alignment.centerLeft),
              arrow(Icons.keyboard_arrow_right_rounded, Alignment.centerRight),
              Center(
                child: Container(
                  width: s * 0.38,
                  height: s * 0.38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(0, -0.5),
                      colors: [Color(0xFF4C5061), Color(0xFF282B36)],
                    ),
                    border: Border.all(color: Colors.white10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: s * 0.07,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
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

class _Key extends StatelessWidget {
  const _Key({
    required this.icon,
    required this.label,
    required this.onTap,
    this.wide = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: wide ? 2 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Material(
          color: const Color(0xFF22252F),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: SizedBox(
              height: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9AA3C7),
                    ),
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
