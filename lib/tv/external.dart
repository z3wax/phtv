import 'dart:async';
import 'dart:io';

import '../native.dart';
import 'input.dart';
import 'services.dart';

/// Televizor uchun YouTube (youtube.com/tv) shu brauzer nomi bilan
/// pult boshqaradigan TV ko‘rinishida ochiladi.
const tvUserAgent =
    'Mozilla/5.0 (SMART-TV; Linux; Tizen 7.0) AppleWebKit/537.36 '
    '(KHTML, like Gecko) 94.0.4606.31/7.0 TV Safari/537.36';

const youtubeTvUrl = 'https://www.youtube.com/tv';

/// Ubuntu: YouTube, kino saytlari va brauzer — Chrome / Chromium’da,
/// televizor ekranida, to‘liq ekranda. Telefondagi pult ishlayveradi:
/// tugmalar `xdotool` orqali Chrome’ga yuboriladi, sensorli panel —
/// sichqoncha, Home — Chrome yopilib, Telefon TV’ga qaytiladi.
class ExternalBrowser {
  ExternalBrowser._();
  static final instance = ExternalBrowser._();

  Process? _proc;
  bool _tv = false;
  bool _warned = false;
  DateTime _lastMove = DateTime(0);

  bool get active => _proc != null;

  static const _chromes = [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'microsoft-edge',
    'brave-browser',
  ];

  /// [tv] — YouTube’ning televizor ko‘rinishi (↑↓←→ va OK bilan yuriladi).
  Future<bool> open(String url, {bool tv = false}) async {
    await close(present: false);
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final geo = await NativeBridge.tvGeometry();
    final args = [
      // Alohida profil: har doim yangi oyna, shu oyna yopilsa jarayon tugaydi.
      '--user-data-dir=$home/.config/telefon-tv/chrome',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-session-crashed-bubble',
      '--autoplay-policy=no-user-gesture-required',
      if (geo != null) '--window-position=${geo[0]},${geo[1]}',
      if (geo != null) '--window-size=${geo[2]},${geo[3]}',
      '--start-fullscreen',
      if (tv) '--user-agent=$tvUserAgent',
      '--app=$url',
    ];
    for (final exe in _chromes) {
      try {
        _proc = await Process.start(exe, args);
        break;
      } on ProcessException {
        continue;
      }
    }
    final proc = _proc;
    if (proc == null) {
      // Chrome yo‘q — standart brauzer (pult bilan boshqarib bo‘lmaydi).
      try {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
        TvServices.instance.showToast(
          'Pult bilan boshqarish uchun Chrome o‘rnating: sudo apt install chromium-browser',
        );
        return true;
      } catch (_) {
        return false;
      }
    }
    _tv = tv;
    proc.stdout.drain<void>();
    proc.stderr.drain<void>();
    TvInput.instance.push(_onCmd);
    TvInput.instance.onPointer = _onPointer;
    TvServices.instance.setPointerMode(!tv);
    unawaited(
      proc.exitCode.then((_) {
        if (_proc == proc) _closed(present: true);
      }),
    );
    return true;
  }

  Future<void> close({bool present = true}) async {
    final p = _proc;
    if (p == null) return;
    p.kill();
    _closed(present: present);
  }

  void _closed({required bool present}) {
    _proc = null;
    TvInput.instance.remove(_onCmd);
    if (TvInput.instance.onPointer == _onPointer) {
      TvInput.instance.onPointer = null;
    }
    TvServices.instance.setPointerMode(false);
    if (present) unawaited(NativeBridge.present());
  }

  Future<void> _xdo(List<String> args) async {
    try {
      final r = await Process.run('xdotool', args);
      if (r.exitCode != 0) throw const ProcessException('xdotool', []);
    } on ProcessException {
      if (!_warned) {
        _warned = true;
        TvServices.instance.showToast(
          'Pult Chrome’ni boshqarishi uchun: sudo apt install xdotool',
        );
      }
    }
  }

  Future<void> _key(String key) => _xdo(['key', '--clearmodifiers', key]);

  void _onPointer(double dx, double dy) {
    _lastMove = DateTime.now();
    _xdo([
      'mousemove_relative',
      '--',
      '${(dx * 1.6).round()}',
      '${(dy * 1.6).round()}',
    ]);
  }

  bool _onCmd(Cmd cmd) {
    if (_proc == null) return false;
    switch (cmd) {
      case Cmd.up:
        _key('Up');
      case Cmd.down:
        _key('Down');
      case Cmd.left:
        _key('Left');
      case Cmd.right:
        _key('Right');
      case Cmd.ok:
        // Sichqoncha yaqinda surilgan bo‘lsa — o‘sha joyni bosamiz.
        if (DateTime.now().difference(_lastMove).inSeconds < 8) {
          _xdo(['click', '1']);
        } else {
          _key('Return');
        }
      case Cmd.back:
        _key(_tv ? 'Escape' : 'alt+Left');
      case Cmd.playPause:
        _key(_tv ? 'Return' : 'XF86AudioPlay');
      case Cmd.next:
        _key(_tv ? 'Right' : 'XF86AudioNext');
      case Cmd.prev:
        _key(_tv ? 'Left' : 'XF86AudioPrev');
      case Cmd.home || Cmd.power:
        close();
      default:
        return false; // ovoz — kompyuter ovozi
    }
    return true;
  }
}
