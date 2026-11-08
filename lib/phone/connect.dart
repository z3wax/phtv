import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv/server.dart';
import 'remote_screen.dart';

/// Pult qaysi televizorga ulanadi (kompyuter, Mac yoki boshqa telefondagi
/// Telefon TV).
class RemoteTarget {
  const RemoteTarget(this.host, this.port, this.pin);
  final String host;
  final int port;
  final String pin;
}

/// Televizordagi QR kod: `http://IP:8765/?k=PIN` — brauzer pulti ham aynan
/// shu manzilni ochadi.
RemoteTarget? parseRemoteUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  final pin = uri.queryParameters['k'];
  if (pin == null || pin.isEmpty) return null;
  return RemoteTarget(
    uri.host,
    uri.hasPort ? uri.port : RemoteServer.defaultPort,
    pin,
  );
}

Future<RemoteTarget?> loadLastTarget() async {
  try {
    final p = SharedPreferencesAsync();
    final host = await p.getString('remoteHost');
    if (host == null || host.isEmpty) return null;
    return RemoteTarget(
      host,
      await p.getInt('remotePort') ?? RemoteServer.defaultPort,
      await p.getString('remotePin') ?? '',
    );
  } catch (_) {
    return null;
  }
}

Future<void> saveLastTarget(RemoteTarget t) async {
  try {
    final p = SharedPreferencesAsync();
    await p.setString('remoteHost', t.host);
    await p.setInt('remotePort', t.port);
    await p.setString('remotePin', t.pin);
  } catch (_) {}
}

/// Telefon qaysi rejimda ochilsin: 'remote' — pult, 'tv' — Smart TV shu
/// telefonda, null — hali tanlanmagan.
Future<String?> loadPhoneMode() async {
  try {
    return await SharedPreferencesAsync().getString('phoneMode');
  } catch (_) {
    return null;
  }
}

Future<void> savePhoneMode(String? mode) async {
  try {
    final p = SharedPreferencesAsync();
    mode == null
        ? await p.remove('phoneMode')
        : await p.setString('phoneMode', mode);
  } catch (_) {}
}

/// Birinchi ochilishda: telefon pultmi yoki Smart TV ning o‘zimi.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.onRemote, required this.onTv});
  final VoidCallback onRemote;
  final VoidCallback onTv;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          children: [
            const Text(
              'z3wax TV',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bu telefon nima bo‘lsin?',
              style: TextStyle(fontSize: 17, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            _Choice(
              icon: Icons.settings_remote_rounded,
              color: const Color(0xFF3B6CFF),
              title: 'Pult',
              text:
                  'Televizorni kompyuter, Mac yoki boshqa telefon ko‘rsatyapti — bu telefon bilan '
                  'boshqarasiz va video yuborasiz. Televizordagi QR kodni skanerlang.',
              onTap: onRemote,
            ),
            const SizedBox(height: 14),
            _Choice(
              icon: Icons.tv_rounded,
              color: const Color(0xFFE11D48),
              title: 'Smart TV shu telefonda',
              text:
                  'Telefon televizorga HDMI adapter yoki AirPlay orqali ulanadi (televizorda Smart TV, '
                  'telefonda pult) yoki Smart TV telefon ekranining o‘zida.',
              onTap: onTv,
            ),
            const SizedBox(height: 18),
            const Text(
              'Keyin o‘zgartirish mumkin: pult ekranidagi yopish tugmasi; Smart TV da Sozlamalar → “Bu telefonni pult qilish”.',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title, text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1D24),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pultni televizorga ulash: QR kod (asosiy yo‘l), oxirgi televizor yoki
/// IP va PIN qo‘lda.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.onExit,
    this.autoConnect = true,
  });
  final VoidCallback onExit;

  /// Oxirgi televizor saqlangan bo‘lsa — darhol ulanish.
  final bool autoConnect;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _host = TextEditingController();
  final _pin = TextEditingController();
  RemoteTarget? _last;
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final last = await loadLastTarget();
    if (!mounted) return;
    setState(() {
      _last = last;
      _host.text = last?.host ?? '';
      _pin.text = last?.pin ?? '';
    });
    if (last != null && widget.autoConnect) _open(last);
  }

  @override
  void dispose() {
    _host.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _open(RemoteTarget t) async {
    await saveLastTarget(t);
    if (!mounted) return;
    setState(() => _last = t);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => RemoteScreen(
          host: t.host,
          port: t.port,
          pin: t.pin,
          onExit: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _scan() async {
    final t = await Navigator.of(
      context,
    ).push<RemoteTarget>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (t != null) await _open(t);
  }

  void _openManual() {
    final host = _host.text.trim();
    if (host.isEmpty) return;
    _open(RemoteTarget(host, RemoteServer.defaultPort, _pin.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Pult — televizorga ulanish'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B6CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
              label: const Text(
                'QR kodni skanerlash',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Televizorda: Pult bo‘limi (dokdagi pult belgisi) — u yerdagi QR kodni skanerlang. '
            'Telefon va televizor bitta Wi-Fi da yoki USB kabel bilan ulangan bo‘lsin.',
            style: TextStyle(fontSize: 14, height: 1.4, color: Colors.white70),
          ),
          if (last != null) ...[
            const SizedBox(height: 22),
            Material(
              color: const Color(0xFF1B1D24),
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: const Icon(Icons.history_rounded),
                title: const Text('Oxirgi televizor'),
                subtitle: Text('${last.host}:${last.port}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(last),
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (!_manual)
            TextButton.icon(
              onPressed: () => setState(() => _manual = true),
              icon: const Icon(Icons.keyboard_rounded),
              label: const Text('IP va PIN ni qo‘lda kiritish'),
            )
          else ...[
            TextField(
              controller: _host,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'IP manzil (masalan 192.168.1.5)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'PIN',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _openManual(),
            ),
            FilledButton.icon(
              onPressed: _openManual,
              icon: const Icon(Icons.settings_remote_rounded),
              label: const Text('Ulanish'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Telefon kamerasi bilan televizordagi QR kodni o‘qish.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  String? _wrong;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final t = parseRemoteUrl(raw);
      if (t != null) {
        _done = true;
        Navigator.of(context).pop(t);
        return;
      }
      if (_wrong != raw) setState(() => _wrong = raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('QR kodni skanerlang'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Text(
              _wrong == null
                  ? 'Televizordagi Pult bo‘limidagi QR kodni ramkaga to‘g‘rilang'
                  : 'Bu z3wax TV QR kodi emas — televizordagi Pult bo‘limini oching',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 8)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
