import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/assistant/cloud_speech.dart';
import 'package:telefon_tv/tv/assistant/edge_token.dart';

List<int> audioFrame(List<int> data) {
  final header = ascii.encode('Path:audio\r\nContent-Type:audio/mpeg\r\n');
  return [header.length >> 8, header.length & 255, ...header, ...data];
}

void main() {
  test('published v2 protocol vectors match the reference client', () {
    expect(
      edgeToken(
        DateTime.fromMillisecondsSinceEpoch(1780000000000, isUtc: true),
      ),
      'FDA8112B8756B195-BA3F4ED428AF8E21948543EAD66D831CEAAFE0A00E5471312ECDDC3C7422E611',
    );
    expect(
      edgeToken(
        DateTime.fromMillisecondsSinceEpoch(1794000000000, isUtc: true),
      ),
      '6EA6AF6A0550F520-17E5A544A1EFE811EA5248AFBD9780637964201A6D3A15ADE53A30AB9D066A4F',
    );
  });

  test(
    'streams and combines audio, escapes SSML and closes the connection',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final messages = <String>[];
      final closed = Completer<void>();
      server.listen((request) async {
        final ws = await WebSocketTransformer.upgrade(request);
        ws.listen(
          (data) {
            messages.add('$data');
            if ('$data'.contains('Path:ssml')) {
              ws.add(audioFrame([0xff, 0xfb, 1]));
              ws.add(audioFrame([2, 3]));
              ws.add('Path:turn.end\r\n\r\n');
            }
          },
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
      });
      final client = CloudSpeechClient(
        endpoint: Uri.parse('ws://127.0.0.1:${server.port}/speech'),
      );
      try {
        expect(
          await client.synthesize('Salom <dunyo> & do‘stlar', voice: 'Sardor'),
          [0xff, 0xfb, 1, 2, 3],
        );
        expect(messages.first, contains('audio-24khz-48kbitrate-mono-mp3'));
        expect(messages.last, contains('uz-UZ-SardorNeural'));
        expect(messages.last, contains('Salom &lt;dunyo&gt; &amp; do‘stlar'));
        await closed.future.timeout(const Duration(seconds: 2));
      } finally {
        client.cancel();
        await server.close(force: true);
      }
    },
  );

  test('cancel completes promptly while a service is still waiting', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final connected = Completer<void>();
    WebSocket? socket;
    server.listen((request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket!.listen((_) {
        if (!connected.isCompleted) connected.complete();
      });
    });
    final client = CloudSpeechClient(
      endpoint: Uri.parse('ws://127.0.0.1:${server.port}/speech'),
    );
    try {
      final pending = client.synthesize('Bekor qilinadigan javob');
      final assertion = expectLater(pending, throwsA(isA<SpeechCancelled>()));
      await connected.future;
      client.cancel();
      await assertion.timeout(const Duration(seconds: 2));
    } finally {
      client.cancel();
      await socket?.close();
      await server.close(force: true);
    }
  });

  test('broken audio headers fail instead of returning corrupted audio', () {
    expect(() => decodeSpeechAudio([0]), throwsFormatException);
    expect(() => decodeSpeechAudio([1, 255, 0]), throwsFormatException);
    expect(decodeSpeechAudio(audioFrame([1, 2, 3])), [1, 2, 3]);
  });
}
