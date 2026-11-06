import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../native.dart';
import '../tv/tv_app.dart';
import 'connect.dart';
import 'remote_screen.dart';
import 'usb_screen.dart';

/// Telefon ekrani.
///
/// * Televizor alohida oyna sifatida ulangan (HDMI / AirPlay / Miracast) —
///   televizorda Smart TV, telefon ekranida pult.
/// * Televizor ulanmagan yoki faqat ekranni takrorlaydi — Smart TV shu yerda.
/// * Pult — kompyuter, Mac yoki boshqa telefondagi Telefon TV’ni boshqarish
///   (televizordagi QR kod orqali, brauzer pultidagi imkoniyatlar bilan).
/// * Birinchi ochilishda shu ikkisidan biri tanlanadi va eslab qolinadi.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

enum _Mode { loading, start, tv, localRemote, otherRemote, usb }

class _PhoneShellState extends State<PhoneShell> {
  bool? _external;
  bool _modeLoaded = false;
  String? _phoneMode; // 'remote' | 'tv' | null (tanlanmagan)
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
    loadPhoneMode().then((m) {
      if (mounted) {
        setState(() {
          _phoneMode = m;
          _modeLoaded = true;
        });
      }
    });
  }

  void _setMode(String? m) {
    savePhoneMode(m);
    setState(() => _phoneMode = m);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  _Mode get _mode {
    if (_external == null || !_modeLoaded) return _Mode.loading;
    if (_external!) return _Mode.localRemote;
    if (_usb) return _Mode.usb;
    if (_phoneMode == 'remote') return _Mode.otherRemote;
    if (_phoneMode == 'tv') return _Mode.tv;
    return _Mode.start;
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
        useAsRemote: () => _setMode('remote'),
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
      _Mode.start => _RemoteApp(
        key: const ValueKey('start'),
        child: StartScreen(
          onRemote: () => _setMode('remote'),
          onTv: () => _setMode('tv'),
        ),
      ),
      _Mode.otherRemote => _RemoteApp(
        key: const ValueKey('other'),
        child: ConnectScreen(onExit: () => _setMode(null)),
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
