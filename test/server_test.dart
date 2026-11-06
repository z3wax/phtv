import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/model.dart';
import 'package:telefon_tv/tv/server.dart';

void main() {
  late RemoteServer server;
  final commands = <Cmd>[];
  final texts = <String>[];
  final media = <List<MediaItem>>[];
  final uploaded = <String>[];
  late Directory uploads;

  setUp(() async {
    commands.clear();
    texts.clear();
    media.clear();
    uploaded.clear();
    uploads = await Directory.systemTemp.createTemp('telefon_tv_upload');
    server = RemoteServer(
      port: 0,
      keyProvider: () => '1234',
      onCommand: commands.add,
      onText: texts.add,
      onMedia: media.add,
      uploadDir: () async => uploads,
      onUpload: (item, index, count) =>
          uploaded.add('${item.title}|$index|$count|${item.kind.name}'),
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await uploads.delete(recursive: true);
  });

  Future<(int, String)> post(String query, List<int> body) async {
    final client = HttpClient();
    final req = await client.post(
      '127.0.0.1',
      server.boundPort!,
      '/upload?$query',
    );
    req.add(body);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    client.close();
    return (res.statusCode, text);
  }

  test('telefondan yuborilgan video saqlanadi va televizorga yetadi', () async {
    final bytes = List<int>.generate(300000, (i) => i % 251);
    final (status, body) = await post(
      'name=${Uri.encodeQueryComponent('Oila/../Sayohat.mp4')}&index=1&count=2',
      bytes,
    );
    expect(status, 200, reason: body);
    final saved = File('${uploads.path}/Sayohat.mp4');
    expect(saved.existsSync(), isTrue);
    expect(saved.lengthSync(), bytes.length);
    expect(uploaded, ['Sayohat|1|2|video']);
    // Bir xil nom — ustiga yozilmaydi.
    expect((await post('name=Sayohat.mp4', [1, 2, 3])).$1, 200);
    expect(File('${uploads.path}/Sayohat (2).mp4').existsSync(), isTrue);
    // Video / rasm / musiqa bo‘lmagan fayl qabul qilinmaydi.
    final (bad, _) = await post('name=dastur.exe', [1, 2, 3]);
    expect(bad, HttpStatus.unsupportedMediaType);
    expect(
      uploads.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.exe'),
      ),
      isEmpty,
    );
  });

  test('USB kabel, Wi-Fi va keraksiz tarmoqlar ajratiladi', () {
    expect(RemoteServer.interfaceLabel('usb0'), 'USB kabel');
    expect(RemoteServer.interfaceLabel('enx0a1b2c3d4e5f'), 'USB kabel');
    expect(RemoteServer.interfaceLabel('wlp2s0'), 'Wi-Fi');
    expect(RemoteServer.interfaceLabel('enp3s0'), 'Kabel (LAN)');
    expect(
      RemoteServer.interfaceRank('usb0'),
      lessThan(RemoteServer.interfaceRank('wlp2s0')),
    );
    for (final hidden in [
      'docker0',
      'virbr0',
      'rmnet_data0',
      'tailscale0',
      'lo',
    ]) {
      expect(RemoteServer.interfaceRank(hidden), 9, reason: hidden);
    }
    expect(RemoteServer.safeUploadName('../../.bashrc'), 'bashrc');
    expect(RemoteServer.safeUploadName('a:b?.mp4'), 'a_b_.mp4');
  });

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 100 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('pult sahifasi brauzerga beriladi', () async {
    final client = HttpClient();
    final res = await (await client.get(
      '127.0.0.1',
      server.boundPort!,
      '/',
    )).close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    expect(res.statusCode, 200);
    expect(body, contains('Telefon TV'));
    expect(body, contains('/ws?k='));
  });

  test('WebSocket orqali buyruq, matn va fayllar keladi', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.boundPort}/ws');
    final hello = Completer<Map<String, dynamic>>();
    ws.listen((d) {
      final m = jsonDecode(d as String) as Map<String, dynamic>;
      if (!hello.isCompleted) hello.complete(m);
    });
    expect((await hello.future)['t'], 'hello');
    await until(() => server.clients.value == 1);
    expect(server.clients.value, 1);

    ws.add(jsonEncode({'t': 'cmd', 'c': 'down'}));
    ws.add(jsonEncode({'t': 'cmd', 'c': 'nonsense'}));
    ws.add(jsonEncode({'t': 'text', 'v': 'https://example.com/a.m3u'}));
    ws.add(
      jsonEncode({
        't': 'media',
        'items': [
          MediaItem(
            title: 'Video',
            source: '/tmp/v.mp4',
            kind: MediaKind.video,
          ).toJson(),
        ],
      }),
    );
    await until(() => media.isNotEmpty);
    expect(commands, [Cmd.down]);
    expect(texts, ['https://example.com/a.m3u']);
    expect(media.single.single.title, 'Video');

    expect(server.broadcast({'t': 'pick'}, localOnly: true), 1);
    await ws.close();
    await until(() => server.clients.value == 0);
    expect(server.clients.value, 0);
  });
}
