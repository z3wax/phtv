import 'dart:async';

import 'package:flutter/services.dart';

/// TV qutisi / stik yoki telefonda o‘rnatilgan ilova.
class InstalledApp {
  const InstalledApp(this.package, this.label, this.icon);
  final String package;
  final String label;
  final Uint8List icon;
}

/// Android (MainActivity.kt) va iPhone (AppDelegate.swift) bilan aloqa:
/// televizor ulandi/uzildi xabari va boshqa ilovalarni ochish.
class NativeBridge {
  static const _channel = MethodChannel('telefon_tv/native');
  static final _external = StreamController<bool>.broadcast();
  static final _home = StreamController<void>.broadcast();
  static bool _listening = false;

  /// Faqat telefon ekranidagi (asosiy) Flutter uchun.
  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'externalDisplay') {
        _external.add(call.arguments == true);
      }
      if (call.method == 'home') _home.add(null);
      return null;
    });
  }

  /// Telefon TV bosh ekran (launcher) bo‘lganda Home tugmasi bosildi.
  static Stream<void> get homePressed => _home.stream;

  /// Televizor ulanishi va uzilishi.
  static Stream<bool> get externalDisplayChanges => _external.stream;

  static Future<bool> externalDisplay() async {
    try {
      return await _channel.invokeMethod<bool>('externalDisplay') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// YouTube, brauzer kabi boshqa ilovani ochadi.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    // iPhone’da bu usullar yo‘q (notImplemented → MissingPluginException).
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Android TV qutisi / stik (yoki televizorning o‘zi).
  static Future<bool> isTvDevice() async =>
      await _call<bool>('isTvDevice') ?? false;

  /// Qurilma yoqilganda Telefon TV ochiladimi (bosh ekran).
  static Future<bool> isHomeLauncher() async =>
      await _call<bool>('isHomeLauncher') ?? false;

  static Future<void> setHomeLauncher(bool on) =>
      _call<bool>('setHomeLauncher', {'on': on});

  /// O‘rnatilgan ilovalar (faqat Android).
  static Future<List<InstalledApp>> listApps() async {
    final list = await _call<List<Object?>>('listApps') ?? const [];
    return [
      for (final e in list)
        if (e is Map)
          InstalledApp(
            '${e['package']}',
            '${e['label']}',
            e['icon'] is Uint8List ? e['icon'] as Uint8List : Uint8List(0),
          ),
    ];
  }

  static Future<bool> launchApp(String package) async =>
      await _call<bool>('launchApp', {'package': package}) ?? false;
}
