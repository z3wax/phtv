import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/linux_browser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('telefon_tv/browser');
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'canGoBack') return true;
      if (call.method == 'runJavaScript' &&
          (call.arguments as Map)['result'] == true) {
        return jsonEncode({'text': 'salom dunyo', 'count': 2});
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> event(Map<String, Object?> data) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('event', data)),
      (_) {},
    );
  }

  test(
    'Linux browser creates in-window session before navigation and decodes JavaScript',
    () async {
      final browser = LinuxBrowserController(userAgent: 'TelefonTV');
      await browser.loadRequest(Uri.parse('https://example.com/'));
      await browser.setBounds(const Rect.fromLTWH(30, 100, 1000, 600));
      await browser.setVisible(true);
      expect(calls.map((c) => c.method), [
        'create',
        'load',
        'setBounds',
        'setVisible',
      ]);
      expect((calls[0].arguments as Map)['userAgent'], 'TelefonTV');
      expect((calls[1].arguments as Map)['url'], 'https://example.com/');
      expect((calls[2].arguments as Map)['x'], 30);
      expect((calls[2].arguments as Map)['height'], 600);
      expect(await browser.canGoBack(), isTrue);
      expect(
        await browser.runJavaScriptReturningResult('document.body.innerText'),
        {'text': 'salom dunyo', 'count': 2},
      );
      await browser.pointer(-0.5, 2);
      expect((calls.last.arguments as Map)['fx'], 0.0);
      expect((calls.last.arguments as Map)['fy'], 1.0);
      await browser.dispose();
    },
  );

  test(
    'nested browsers keep independent page events and ignore disposed sessions',
    () async {
      final first = LinuxBrowserController();
      final second = LinuxBrowserController();
      final firstTitles = <String>[];
      final secondTitles = <String>[];
      first.onTitleChange = firstTitles.add;
      second.onTitleChange = secondTitles.add;
      await first.loadRequest(Uri.parse('https://first.example/'));
      await second.loadRequest(Uri.parse('https://second.example/'));
      await event({'id': first.id, 'type': 'title', 'title': 'First page'});
      await event({'id': second.id, 'type': 'title', 'title': 'Second page'});
      expect(firstTitles, ['First page']);
      expect(secondTitles, ['Second page']);
      expect(await first.getTitle(), 'First page');
      expect(await second.getTitle(), 'Second page');
      await second.dispose();
      await event({
        'id': second.id,
        'type': 'title',
        'title': 'Late closed page',
      });
      await event({'id': first.id, 'type': 'title', 'title': 'Still open'});
      expect(firstTitles, ['First page', 'Still open']);
      expect(secondTitles, ['Second page']);
      await first.dispose();
    },
  );
}
