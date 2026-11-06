import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ovozni tanish hodisasi: ready, partial (eshitilayotgan so‘zlar),
/// final (tayyor gap), error (permission / language / nomatch / network…).
class VoiceEvent {
  const VoiceEvent(this.type, this.text);
  final String type;
  final String text;
}

/// Telefon mikrofoni → matn. Telefonning o‘z tizimi ishlaydi
/// (Android: Google, iPhone: Siri dvigateli) — qo‘shimcha kutubxonasiz.
class VoiceInput {
  VoiceInput._();
  static final instance = VoiceInput._();

  static const _channel = MethodChannel('telefon_tv/voice');
  final _events = StreamController<VoiceEvent>.broadcast();
  bool _bound = false;

  /// Tanlash mumkin bo‘lgan tillar.
  static const languages = {
    'uz-UZ': 'O‘zbekcha',
    'ru-RU': 'Русский',
    'en-US': 'English',
  };

  Stream<VoiceEvent> get events {
    _bind();
    return _events.stream;
  }

  bool get supported => Platform.isAndroid || Platform.isIOS;

  void _bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      final a = call.arguments;
      _events.add(
        VoiceEvent(call.method, a is String ? a : (a?.toString() ?? '')),
      );
      return null;
    });
  }

  /// Tinglashni boshlaydi. Ovozni tanish bo‘lmasa — false (yozib so‘raladi).
  Future<bool> start(String locale) async {
    if (!supported) return false;
    _bind();
    try {
      return await _channel.invokeMethod<bool>('start', {
            'locale': locale,
            'locales': [locale, ...languages.keys.where((l) => l != locale)],
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Gapirib bo‘ldim — natija `final` hodisasi bilan keladi.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<bool>('cancel');
    } catch (_) {}
  }

  static Future<String> loadLanguage() async {
    try {
      final v = await SharedPreferencesAsync().getString('voiceLang');
      if (v != null && languages.containsKey(v)) return v;
    } catch (_) {}
    return 'uz-UZ';
  }

  static Future<void> saveLanguage(String v) async {
    try {
      await SharedPreferencesAsync().setString('voiceLang', v);
    } catch (_) {}
  }
}
