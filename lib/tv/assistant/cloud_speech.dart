import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'edge_token.dart';

/// Keyless online Read Aloud. No Python or downloaded model is needed.
/// The service can change or impose limits; callers retain a system fallback.
class CloudSpeechClient {
  CloudSpeechClient({this.endpoint});
  final Uri? endpoint;
  _SpeechRequest? _active;

  void cancel() {
    _active?.cancel();
    _active = null;
  }

  Future<Uint8List> synthesize(String text, {String voice = 'Madina'}) async {
    cancel();
    if (text.trim().isEmpty || text.length > 16000) {
      throw ArgumentError('Ovoz matni bo‘sh yoki juda uzun');
    }
    final request = _active = _SpeechRequest(endpoint);
    try {
      return await Future.any([
        request.run(text, voice).timeout(const Duration(seconds: 45)),
        request.cancelled.future.then<Uint8List>(
          (_) => throw const SpeechCancelled(),
        ),
      ]);
    } finally {
      request.cancel();
      if (identical(_active, request)) _active = null;
    }
  }
}

class SpeechCancelled implements Exception {
  const SpeechCancelled();
}

class _SpeechRequest {
  _SpeechRequest(this.endpoint);
  final Uri? endpoint;
  final cancelled = Completer<void>();
  HttpClient? _http;
  WebSocket? _socket;

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    unawaited(_socket?.close());
    _http?.close(force: true);
  }

  void _check() {
    if (cancelled.isCompleted) throw const SpeechCancelled();
  }

  Future<Uint8List> run(String text, String voice) async {
    final output = BytesBuilder(copy: false);
    var rest = text.trim();
    while (rest.isNotEmpty) {
      _check();
      var end = rest.length;
      if (end > 1800) {
        end = rest.lastIndexOf(' ', 1800);
        if (end < 1) end = 1800;
        // Do not split a UTF-16 surrogate pair.
        if (rest.codeUnitAt(end - 1) >= 0xd800 &&
            rest.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
      }
      final part = rest.substring(0, end);
      rest = rest.substring(end).trimLeft();
      await _chunk(part, voice, output);
    }
    if (output.isEmpty) {
      throw const FormatException('Bulutli ovoz bo‘sh qaytdi');
    }
    return output.takeBytes();
  }

  Future<void> _chunk(String text, String voice, BytesBuilder output) async {
    final now = DateTime.now().toUtc();
    final uri =
        endpoint ??
        Uri.https(
          'speech.platform.bing.com',
          '/consumer/speech/synthesize/readaloud/edge/v1',
          {
            'TrustedClientToken': edgeClientToken,
            'ConnectionId': _id(),
            'Sec-MS-GEC': edgeToken(now),
            'Sec-MS-GEC-Version': '2-143.0.3650.75',
          },
        );
    final wsUri = endpoint ?? uri.replace(scheme: 'wss', port: 443);
    final http = _http = HttpClient()
      ..userAgent =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0'
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    WebSocket? socket;
    try {
      socket = await WebSocket.connect(
        wsUri.toString(),
        customClient: http,
        compression: CompressionOptions.compressionOff,
        headers: {
          'Cookie': 'muid=${_id().toUpperCase()};',
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      _check();
      final stamp = _timestamp(now);
      socket.add(
        'X-Timestamp:$stamp\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n'
        '${jsonEncode({
          'context': {
            'synthesis': {
              'audio': {
                'metadataoptions': {'sentenceBoundaryEnabled': 'false', 'wordBoundaryEnabled': 'false'},
                'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
              },
            },
          },
        })}\r\n',
      );
      final name = voice == 'Sardor' ? 'Sardor' : 'Madina';
      final safe = text
          .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), ' ')
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      socket.add(
        'X-RequestId:${_id()}\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:${stamp}Z\r\nPath:ssml\r\n\r\n'
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="uz-UZ"><voice name="uz-UZ-${name}Neural"><prosody pitch="+0Hz" rate="+0%" volume="+0%">$safe</prosody></voice></speak>',
      );
      var ended = false;
      await for (final frame in socket.timeout(const Duration(seconds: 12))) {
        _check();
        if (frame is String) {
          if (frame.contains('Path:turn.end')) {
            ended = true;
            break;
          }
        } else if (frame is List<int>) {
          final audio = decodeSpeechAudio(frame);
          if (output.length + audio.length > 4 * 1024 * 1024) {
            throw const FormatException('Ovoz hajmi juda katta');
          }
          output.add(audio);
        }
      }
      if (!ended) throw const FormatException('Bulutli ovoz uzilib qoldi');
    } finally {
      if (socket != null) unawaited(socket.close());
      http.close(force: true);
      if (identical(_socket, socket)) _socket = null;
      if (identical(_http, http)) _http = null;
    }
  }
}

Uint8List decodeSpeechAudio(List<int> frame) {
  if (frame.length < 2) throw const FormatException('Ovoz paketi noto‘g‘ri');
  final length = (frame[0] << 8) | frame[1];
  if (length + 2 > frame.length) {
    throw const FormatException('Ovoz sarlavhasi noto‘g‘ri');
  }
  final header = ascii.decode(frame.sublist(2, length + 2), allowInvalid: true);
  if (!header.contains('Path:audio') ||
      !header.contains('Content-Type:audio/mpeg')) {
    return Uint8List(0);
  }
  return Uint8List.fromList(frame.sublist(length + 2));
}

String _id() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _timestamp(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[d.weekday - 1]} ${months[d.month - 1]} ${two(d.day)} ${d.year} ${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT+0000 (Coordinated Universal Time)';
}
