import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native.dart';
import '../tv/tv_app.dart';
import 'remote_screen.dart';
import 'usb_screen.dart';

/// Telefon ekrani.
///
/// * Televizor alohida oyna sifatida ulangan (HDMI / AirPlay / Miracast) —
///   televizorda Smart TV, telefon ekranida pult.
/// * Televizor ulanmagan yoki faqat ekranni takrorlaydi — Smart TV shu yerda.
/// * “Bu telefonni pult qilish” — boshqa telefondagi Telefon TV’ni boshqarish.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

enum _Mode { loading, tv, localRemote, otherRemote, usb }

class _PhoneShellState extends State<PhoneShell> {
  bool? _external;
  bool _otherRemote = false;
  bool _usb = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    NativeBridge.listen();
    _sub = NativeBridge.externalDisplayChanges.listen(
      (v) => setState(() => _external = v),
    );
    NativeBridge.externalDisplay().then((v) {
      if (mounted && _external == null) setState(() => _external = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  _Mode get _mode {
    if (_external == null) return _Mode.loading;
    if (_external!) return _Mode.localRemote;
    if (_otherRemote) return _Mode.otherRemote;
    if (_usb) return _Mode.usb;
    return _Mode.tv;
  }

  _Mode? _applied;
  void _applySystemUi(_Mode m) {
    if (_applied == m) return;
    _applied = m;
    if (m == _Mode.tv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    _applySystemUi(mode);
    return switch (mode) {
      _Mode.loading => const ColoredBox(color: Colors.black),
      _Mode.tv => TvApp(
        key: const ValueKey('tv'),
        onTvDisplay: false,
        useAsRemote: () => setState(() => _otherRemote = true),
        openUsb: () => setState(() => _usb = true),
      ),
      _Mode.localRemote => const _RemoteApp(
        key: ValueKey('local'),
        child: RemoteScreen(host: '127.0.0.1', local: true),
      ),
      _Mode.usb => _RemoteApp(
        key: const ValueKey('usb'),
        child: UsbScreen(onExit: () => setState(() => _usb = false)),
      ),
      _Mode.otherRemote => _RemoteApp(
        key: const ValueKey('other'),
        child: _ConnectScreen(
          onExit: () => setState(() => _otherRemote = false),
        ),
      ),
    };
  }
}

class _RemoteApp extends StatelessWidget {
  const _RemoteApp({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Telefon TV',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B6CFF),
        brightness: Brightness.dark,
      ),
    ),
    home: child,
  );
}

/// Boshqa telefondagi televizorga ulanish: IP va PIN (televizorda “Pult” bo‘limida).
class _ConnectScreen extends StatefulWidget {
  const _ConnectScreen({required this.onExit});
  final VoidCallback onExit;

  @override
  State<_ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<_ConnectScreen> {
  final _host = TextEditingController();
  final _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = SharedPreferencesAsync();
      _host.text = await p.getString('remoteHost') ?? '';
      _pin.text = await p.getString('remotePin') ?? '';
    } catch (_) {}
  }

  @override
  void dispose() {
    _host.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final host = _host.text.trim(), pin = _pin.text.trim();
    if (host.isEmpty) return;
    try {
      final p = SharedPreferencesAsync();
      await p.setString('remoteHost', host);
      await p.setString('remotePin', pin);
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteScreen(
          host: host,
          pin: pin,
          onExit: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Boshqa televizorga ulanish'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Televizor ko‘rsatayotgan telefonda: Sozlamalar → “Boshqa telefonni pult qilish”. '
            'U yerda IP va PIN yozilgan. Ikkala telefon bitta Wi-Fi’da bo‘lsin.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _host,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _go,
            icon: const Icon(Icons.settings_remote_rounded),
            label: const Text('Ulanish'),
          ),
        ],
      ),
    );
  }
}
