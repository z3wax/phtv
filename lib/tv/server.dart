import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'input.dart';
import 'model.dart';
import 'remote_page.dart';

/// Kompyuter / telefonning tarmoq manzili va u qaysi ulanish ekani.
class LocalAddress {
  const LocalAddress(this.ip, this.interface, this.label);
  final String ip;
  final String interface;

  /// “USB kabel”, “Wi-Fi”, “Hotspot”, “LAN kabel”…
  final String label;
}

/// Pult serveri: televizor ko‘rsatayotgan qurilmada (telefon yoki Ubuntu
/// kompyuter) ishlaydi.
///
/// * Shu qurilmaning o‘zi (127.0.0.1) — PIN so‘ramaydi.
/// * Boshqa telefon (Wi-Fi yoki USB kabel orqali) — brauzerda
///   `http://IP:8765/?k=PIN` yoki Telefon TV ilovasidagi “Pult” rejimi orqali.
/// * `POST /upload?k=PIN&name=…` — telefondan video, rasm, musiqa yuborish.
class RemoteServer {
  RemoteServer({
    required this.keyProvider,
    required this.onCommand,
    required this.onText,
    required this.onMedia,
    this.uploadDir,
    this.onUpload,
    this.onAsk,
    this.onListen,
    this.port = defaultPort,
  });

  static const defaultPort = 8765;

  final String Function() keyProvider;
  final void Function(Cmd cmd) onCommand;
  final void Function(String text) onText;
  final void Function(List<MediaItem> items) onMedia;

  /// Telefondan yuborilgan fayllar saqlanadigan papka.
  final Future<Directory> Function()? uploadDir;

  /// Fayl yuborildi: [index] — nechanchisi, [count] — jami nechta.
  final void Function(MediaItem item, int index, int count)? onUpload;

  /// Pult mikrofonidan (yoki yozib) AI yordamchiga savol.
  final void Function(String text)? onAsk;

  /// Mikrofon holati: start / partial (eshitilgan so‘zlar) / cancel / error.
  final void Function(String phase, String text)? onListen;
  final int port;

  HttpServer? _server;
  final _clients = <WebSocket, bool>{}; // qiymat: shu qurilmaning o‘zimi
  final _uploadsInProgress = <String>{};
  final clients = ValueNotifier<int>(0);
  Map<String, Object?>? _state;
  bool _stopped = false;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    _stopped = false;
    while (!_stopped && _server == null) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      } catch (_) {
        // Port hali band (boshqa ekrandagi nusxa yopilmoqda) — biroz kutamiz.
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    final server = _server;
    if (server == null) return;
    if (_stopped) {
      await server.close(force: true);
      _server = null;
      return;
    }
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    _stopped = true;
    for (final ws in _clients.keys.toList()) {
      await ws.close();
    }
    _clients.clear();
    clients.value = 0;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final local = req.connectionInfo?.remoteAddress.isLoopback ?? false;
      final allowed = local || req.uri.queryParameters['k'] == keyProvider();
      if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        if (!allowed) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        ws.pingInterval = const Duration(seconds: 10);
        _clients[ws] = local;
        clients.value = _clients.length;
        ws.add(jsonEncode({'t': 'hello', 'name': 'Telefon TV'}));
        if (_state != null) ws.add(jsonEncode(_state));
        ws.listen(
          (data) => _onMessage(data, local),
          onDone: () => _drop(ws),
          onError: (_) => _drop(ws),
          cancelOnError: true,
        );
        return;
      }
      if (req.uri.path == '/upload' && req.method == 'POST') {
        await _upload(req, allowed);
        return;
      }
      if (req.uri.path == '/' || req.uri.path == '/index.html') {
        req.response.headers.contentType = ContentType.html;
        req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        req.response.write(remotePageHtml);
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _reply(
    HttpRequest req,
    int status,
    Map<String, Object?> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  /// Telefondan kelgan faylni saqlaydi va televizorda ochadi.
  Future<void> _upload(HttpRequest req, bool allowed) async {
    final dirProvider = uploadDir;
    if (!allowed) {
      await req.drain<void>();
      return _reply(req, HttpStatus.forbidden, {
        'ok': false,
        'error': 'PIN noto‘g‘ri',
      });
    }
    final q = req.uri.queryParameters;
    final name = safeUploadName(q['name'] ?? '');
    final kind = MediaItem.kindForName(name);
    if (dirProvider == null || kind == null) {
      await req.drain<void>();
      return _reply(req, HttpStatus.unsupportedMediaType, {
        'ok': false,
        'error': 'Faqat video, rasm yoki musiqa yuborish mumkin',
      });
    }
    final dir = await dirProvider();
    await dir.create(recursive: true);
    final file = uniqueFile(dir, name, reserved: _uploadsInProgress);
    // Boshqa pult ayni nomni yuborsa, tugallanmagan fayl ham band hisoblanadi.
    _uploadsInProgress.add(file.path);
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    try {
      await sink.addStream(req);
      await sink.close();
      await part.rename(file.path);
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      return _reply(req, HttpStatus.internalServerError, {
        'ok': false,
        'error': 'Saqlab bo‘lmadi',
      });
    } finally {
      _uploadsInProgress.remove(file.path);
    }
    final dot = name.lastIndexOf('.');
    final item = MediaItem(
      title: dot > 0 ? name.substring(0, dot) : name,
      source: file.path,
      kind: kind,
    );
    final count = int.tryParse(q['count'] ?? '') ?? 1;
    final index = int.tryParse(q['index'] ?? '') ?? 0;
    await _reply(req, HttpStatus.ok, {'ok': true});
    onUpload?.call(item, index.clamp(0, count - 1), count < 1 ? 1 : count);
  }

  /// Fayl nomidan papka yo‘lini va xavfli belgilarni olib tashlaydi.
  static String safeUploadName(String raw) {
    var name = raw.split(RegExp(r'[/\\]')).last.trim();
    name = name.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_');
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    if (name.length > 120) {
      final dot = name.lastIndexOf('.');
      final ext = dot > 0 && name.length - dot <= 8 ? name.substring(dot) : '';
      name = name.substring(0, 120 - ext.length) + ext;
    }
    return name.isEmpty ? 'fayl' : name;
  }

  /// Bir xil nomli fayl bo‘lsa — “nom (2).mp4”.
  static File uniqueFile(
    Directory dir,
    String name, {
    Set<String> reserved = const {},
  }) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var f = File('${dir.path}/$name');
    for (var n = 2; f.existsSync() || reserved.contains(f.path); n++) {
      f = File('${dir.path}/$base ($n)$ext');
    }
    return f;
  }

  void _drop(WebSocket ws) {
    _clients.remove(ws);
    clients.value = _clients.length;
  }

  void _onMessage(Object? data, bool local) {
    if (data is! String) return;
    final Object? msg;
    try {
      msg = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (msg is! Map) return;
    final Map<Object?, Object?> m = msg;
    switch (m['t']) {
      case 'cmd':
        final cmd = Cmd.values.where((c) => c.name == m['c']).firstOrNull;
        if (cmd != null) onCommand(cmd);
      case 'text':
        final v = m['v'];
        if (v is String) onText(v);
      case 'ask':
        final v = m['v'];
        if (v is String && v.trim().isNotEmpty) onAsk?.call(v.trim());
      case 'listen':
        final phase = m['phase'];
        if (phase is String) {
          final v = m['v'];
          onListen?.call(phase, v is String ? v : '');
        }
      case 'media':
        // Fayl yo‘llari faqat shu qurilmaning o‘zidan qabul qilinadi.
        if (!local || m['items'] is! List) return;
        final items = [
          for (final e in m['items'] as List)
            if (MediaItem.fromJson(e) case final item?) item,
        ];
        if (items.isNotEmpty) onMedia(items);
    }
  }

  /// Hamma pultlarga xabar yuboradi; nechta pultga yetganini qaytaradi.
  int broadcast(Map<String, Object?> msg, {bool localOnly = false}) {
    final text = jsonEncode(msg);
    var sent = 0;
    _clients.forEach((ws, local) {
      if (localOnly && !local) return;
      ws.add(text);
      sent++;
    });
    return sent;
  }

  /// Hozir nima ko‘rsatilayotgani (pult ekranida chiqadi).
  void setState(Map<String, Object?> state) {
    _state = {'t': 'state', ...state};
    broadcast(_state!);
  }

  /// Boshqa telefon ulanishi mumkin bo‘lgan manzillar: USB kabel, Wi-Fi,
  /// hotspot, LAN (mobil internet, VPN, Docker emas).
  static Future<List<LocalAddress>> localAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      list.sort(
        (a, b) => interfaceRank(a.name).compareTo(interfaceRank(b.name)),
      );
      return [
        for (final i in list)
          if (interfaceRank(i.name) < 9)
            for (final a in i.addresses)
              if (!a.isLoopback && !a.isLinkLocal)
                LocalAddress(
                  a.address,
                  i.name,
                  // iPhone modem rejimi (USB kabel yoki Wi-Fi) shu tarmoqni beradi.
                  a.address.startsWith('172.20.10.')
                      ? 'iPhone (USB / modem)'
                      : interfaceLabel(i.name),
                ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Kichik raqam — birinchi ko‘rsatiladi; 9 — umuman ko‘rsatilmaydi.
  static int interfaceRank(String name) {
    final n = name.toLowerCase();
    const hidden = [
      'rmnet', 'pdp', 'ccmni', 'utun', 'tun', 'tap', 'docker', 'virbr', //
      'veth', 'br-', 'lxc', 'vmnet', 'vboxnet', 'zt', 'tailscale', 'wg', 'lo',
      'awdl', 'llw', 'anpi', 'gif', 'stf', // macOS ichki interfeyslari
    ];
    if (hidden.any(n.startsWith)) return 9;
    if (n.startsWith('usb') || n.startsWith('enx') || n.startsWith('rndis')) {
      return 0; // USB kabel
    }
    if (n.startsWith('wl') || n == 'en0') return 1; // Wi-Fi
    if (n.startsWith('ap') || n.startsWith('swlan') || n.startsWith('bridge')) {
      return 2; // hotspot
    }
    if (n.startsWith('en') || n.startsWith('eth')) return 3; // LAN kabel
    return 5;
  }

  static String interfaceLabel(String name) {
    final n = name.toLowerCase();
    if (n.startsWith('usb') || n.startsWith('enx') || n.startsWith('rndis')) {
      return 'USB kabel';
    }
    if (n.startsWith('wl') || n == 'en0') return 'Wi-Fi';
    if (n.startsWith('ap') || n.startsWith('swlan') || n.startsWith('bridge')) {
      return 'Hotspot';
    }
    if (n.startsWith('en') || n.startsWith('eth')) return 'Kabel (LAN)';
    return name;
  }
}
