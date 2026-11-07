import 'dart:convert';

import 'package:flutter/services.dart';

/// A WebKitGTK view embedded in the same Linux window as Flutter.
///
/// Bounds use Flutter view coordinates, before the TV canvas transform. Each
/// browser route owns a controller, so returning to a previous page retains its
/// navigation history and document instead of opening another desktop window.
class LinuxBrowserController {
  LinuxBrowserController({String? userAgent}) : id = ++_nextId {
    _controllers[id] = this;
    if (!_listening) {
      _channel.setMethodCallHandler(_onMethod);
      _listening = true;
    }
    _ready = _channel.invokeMethod<void>('create', {
      'id': id,
      if (userAgent != null) 'userAgent': userAgent,
    });
  }

  static const _channel = MethodChannel('telefon_tv/browser');
  static final _controllers = <int, LinuxBrowserController>{};
  static int _nextId = 0;
  static bool _listening = false;

  final int id;
  late final Future<void> _ready;
  bool _disposed = false;
  String? _title;

  void Function(int progress)? onProgress;
  void Function(String url)? onPageStarted;
  void Function(String url)? onPageFinished;
  void Function(String url)? onUrlChange;
  void Function(String title)? onTitleChange;
  void Function(String message)? onError;
  void Function(String key)? onKey;

  static Future<Object?> _onMethod(MethodCall call) async {
    if (call.method != 'event' || call.arguments is! Map) return null;
    final event = call.arguments as Map;
    final controller = _controllers[event['id']];
    if (controller == null || controller._disposed) return null;
    final url = event['url'] as String? ?? '';
    switch (event['type']) {
      case 'started':
        controller.onPageStarted?.call(url);
      case 'finished':
        controller.onPageFinished?.call(url);
      case 'progress':
        controller.onProgress?.call((event['progress'] as num?)?.round() ?? 0);
      case 'url':
        controller.onUrlChange?.call(url);
      case 'title':
        controller._title = event['title'] as String? ?? '';
        controller.onTitleChange?.call(controller._title!);
      case 'error':
        controller.onError?.call(
          event['error'] as String? ?? 'Sahifa ochilmadi',
        );
      case 'key':
        controller.onKey?.call(event['key'] as String? ?? '');
    }
    return null;
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    await _ready;
    if (_disposed) return null;
    return _channel.invokeMethod<T>(method, {'id': id, ...?arguments});
  }

  Future<void> loadRequest(Uri uri) => _invoke<void>('load', {'url': '$uri'});

  Future<void> runJavaScript(String script) =>
      _invoke<void>('runJavaScript', {'script': script, 'result': false});

  Future<Object> runJavaScriptReturningResult(String script) async {
    final result = await _invoke<String>('runJavaScript', {
      'script': script,
      'result': true,
    });
    if (result == null) return '';
    return jsonDecode(result) ?? '';
  }

  Future<String?> getTitle() async => _title;
  Future<bool> canGoBack() async => await _invoke<bool>('canGoBack') ?? false;
  Future<void> goBack() => _invoke<void>('goBack');
  Future<void> reload() => _invoke<void>('reload');
  Future<void> setVisible(bool visible) =>
      _invoke<void>('setVisible', {'visible': visible});

  Future<void> setBounds(Rect bounds) => _invoke<void>('setBounds', {
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  });

  Future<void> pointer(double fx, double fy) => _invoke<void>('pointer', {
    'fx': fx.clamp(0.0, 1.0),
    'fy': fy.clamp(0.0, 1.0),
  });

  Future<void> click(double fx, double fy) => _invoke<void>('click', {
    'fx': fx.clamp(0.0, 1.0),
    'fy': fy.clamp(0.0, 1.0),
  });

  Future<void> sendKey(String key) => _invoke<void>('sendKey', {'key': key});
  Future<void> typeText(String text) =>
      _invoke<void>('typeText', {'text': text});

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controllers.remove(id);
    try {
      await _ready;
      await _channel.invokeMethod<void>('dispose', {'id': id});
    } on PlatformException {
      // The native window may already have been closed.
    } on MissingPluginException {
      // No native window exists in widget tests.
    }
  }
}
