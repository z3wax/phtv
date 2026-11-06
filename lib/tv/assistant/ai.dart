import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Bepul AI xizmatlari. Hammasi tekin: kalitsiz yoki bepul kalit bilan.
enum AiProvider {
  /// Kalitsiz (Pollinations). Darrov ishlaydi, lekin sekinroq va cheklangan.
  free,

  /// Google Gemini — bepul kalit (aistudio.google.com, karta shart emas).
  /// O‘zbek tilini eng yaxshi tushunadi, Google qidiruvi bilan javob beradi.
  gemini,

  /// Groq — bepul kalit (console.groq.com). Eng tezkor javob.
  groq,

  /// Boshqa OpenAI-mos xizmat (OpenRouter, LLM7, uydagi Ollama…).
  custom,
}

@immutable
class AiConfig {
  const AiConfig({
    this.provider = AiProvider.free,
    this.keys = const {},
    this.model = '',
    this.endpoint = '',
    this.webSearch = true,
    this.voice = true,
  });

  final AiProvider provider;

  /// Har bir xizmat o‘z kalitini saqlaydi (almashtirganda yo‘qolmaydi).
  final Map<String, String> keys;

  /// Bo‘sh — avtomatik tanlanadi.
  final String model;

  /// Faqat “Boshqa” xizmat uchun: `https://…/v1/chat/completions`.
  final String endpoint;

  /// Gemini: yangiliklar, narxlar, natijalar uchun Google qidiruvi.
  final bool webSearch;

  /// Javobni televizor ovoz chiqarib aytadi.
  final bool voice;

  String get key => keys[provider.name] ?? '';

  bool get needsKey =>
      provider == AiProvider.gemini || provider == AiProvider.groq;

  bool get ready => !needsKey || key.isNotEmpty;

  String get label => switch (provider) {
    AiProvider.free => 'Bepul (kalitsiz)',
    AiProvider.gemini => 'Google Gemini (bepul kalit)',
    AiProvider.groq => 'Groq — eng tez (bepul kalit)',
    AiProvider.custom => 'Boshqa (OpenAI-mos)',
  };

  AiConfig copyWith({
    AiProvider? provider,
    String? key,
    String? model,
    String? endpoint,
    bool? webSearch,
    bool? voice,
  }) {
    final p = provider ?? this.provider;
    return AiConfig(
      provider: p,
      keys: key == null ? keys : {...keys, p.name: key},
      model:
          model ??
          (provider != null && provider != this.provider ? '' : this.model),
      endpoint: endpoint ?? this.endpoint,
      webSearch: webSearch ?? this.webSearch,
      voice: voice ?? this.voice,
    );
  }

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'keys': keys,
    'model': model,
    'endpoint': endpoint,
    'webSearch': webSearch,
    'voice': voice,
  };

  static AiConfig fromJson(Object? j) {
    if (j is! Map) return const AiConfig();
    final keys = j['keys'];
    return AiConfig(
      provider:
          AiProvider.values.where((p) => p.name == j['provider']).firstOrNull ??
          AiProvider.free,
      keys: {
        if (keys is Map)
          for (final e in keys.entries)
            if (e.value is String) '${e.key}': e.value as String,
      },
      model: j['model'] as String? ?? '',
      endpoint: j['endpoint'] as String? ?? '',
      webSearch: j['webSearch'] as bool? ?? true,
      voice: j['voice'] as bool? ?? true,
    );
  }
}

/// Suhbatdagi bitta gap.
@immutable
class AiTurn {
  const AiTurn({required this.user, required this.text});
  final bool user;
  final String text;
}

/// Foydalanuvchiga ko‘rsatiladigan tushunarli xato.
class AiException implements Exception {
  AiException(this.message, {this.status});
  final String message;
  final int? status;

  /// Boshqa model / qidiruvsiz qayta urinish foyda beradimi.
  bool get retryable =>
      status == 404 || status == 429 || status == 400 || status == 503;

  @override
  String toString() => message;
}

/// Bepul AI xizmatlariga so‘rov: javob bo‘lak-bo‘lak (oqim) keladi —
/// birinchi so‘zlar bir soniyadan kam vaqtda ekranda.
class AiClient {
  AiClient({
    this.geminiBase = 'https://generativelanguage.googleapis.com/v1beta',
    this.freeEndpoint = 'https://text.pollinations.ai/openai',
    this.groqEndpoint = 'https://api.groq.com/openai/v1/chat/completions',
  });

  final String geminiBase;
  final String freeEndpoint;
  final String groqEndpoint;

  /// Oxirgi ishlagan model (bepul limit tugagan modelni qayta so‘ramaslik).
  final _working = <AiProvider, String>{};

  static const geminiModels = [
    'gemini-flash-latest',
    'gemini-flash-lite-latest',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
  ];

  static const groqModels = [
    'llama-3.3-70b-versatile',
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'llama-3.1-8b-instant',
  ];

  List<String> _models(AiConfig c) {
    final defaults = switch (c.provider) {
      AiProvider.gemini => geminiModels,
      AiProvider.groq => groqModels,
      AiProvider.free => const ['openai'],
      AiProvider.custom => const <String>[],
    };
    final first = c.model.isNotEmpty ? c.model : _working[c.provider];
    return {?first, ...defaults}.toList();
  }

  /// Javob matnini bo‘lak-bo‘lak qaytaradi.
  Stream<String> chat(
    AiConfig config, {
    required String system,
    required List<AiTurn> turns,
  }) async* {
    if (!config.ready) {
      throw AiException(
        'AI kaliti kiritilmagan. Sozlamalar → AI yordamchi bo‘limiga bepul kalit kiriting.',
      );
    }
    final models = _models(config);
    if (config.provider == AiProvider.custom && models.isEmpty) {
      models.add('');
    }
    AiException? last;
    for (final model in models) {
      var gotText = false;
      try {
        final stream = config.provider == AiProvider.gemini
            ? _gemini(config, model, system, turns, search: config.webSearch)
            : _openAi(config, model, system, turns);
        await for (final piece in stream) {
          gotText = true;
          yield piece;
        }
        _working[config.provider] = model;
        return;
      } on AiException catch (e) {
        if (gotText) rethrow;
        last = e;
        // Google qidiruvi bepul limiti tugagan bo‘lsa — qidiruvsiz.
        if (config.provider == AiProvider.gemini &&
            config.webSearch &&
            (e.status == 400 || e.status == 429)) {
          try {
            var ok = false;
            await for (final piece in _gemini(
              config,
              model,
              system,
              turns,
              search: false,
            )) {
              ok = true;
              yield piece;
            }
            if (ok) {
              _working[config.provider] = model;
              return;
            }
          } on AiException catch (e2) {
            last = e2;
          }
        }
        if (!e.retryable) rethrow;
      }
    }
    throw last ?? AiException('AI javob bermadi');
  }

  Stream<String> _gemini(
    AiConfig c,
    String model,
    String system,
    List<AiTurn> turns, {
    required bool search,
  }) async* {
    final uri = Uri.parse(
      '$geminiBase/models/$model:streamGenerateContent?alt=sse',
    );
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        for (final t in turns)
          {
            'role': t.user ? 'user' : 'model',
            'parts': [
              {'text': t.text},
            ],
          },
      ],
      'generationConfig': {'maxOutputTokens': 700, 'temperature': 0.7},
      if (search)
        'tools': [
          {'google_search': <String, Object?>{}},
        ],
    };
    await for (final data in _post(uri, body, {'x-goog-api-key': c.key})) {
      final Object? j;
      try {
        j = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (j is! Map) continue;
      final blocked = (j['promptFeedback'] as Map?)?['blockReason'];
      if (blocked != null) {
        throw AiException('Bu savolga javob bera olmayman.');
      }
      final cands = j['candidates'];
      if (cands is! List || cands.isEmpty) continue;
      final parts = ((cands.first as Map)['content'] as Map?)?['parts'];
      if (parts is! List) continue;
      final text = StringBuffer();
      for (final p in parts) {
        if (p is Map && p['text'] is String && p['thought'] != true) {
          text.write(p['text']);
        }
      }
      if (text.isNotEmpty) yield text.toString();
    }
  }

  Stream<String> _openAi(
    AiConfig c,
    String model,
    String system,
    List<AiTurn> turns,
  ) async* {
    final endpoint = switch (c.provider) {
      AiProvider.free => freeEndpoint,
      AiProvider.groq => groqEndpoint,
      _ => c.endpoint.trim(),
    };
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme) {
      throw AiException(
        'AI manzili noto‘g‘ri. Masalan: https://openrouter.ai/api/v1/chat/completions',
      );
    }
    final body = {
      if (model.isNotEmpty) 'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        for (final t in turns)
          {'role': t.user ? 'user' : 'assistant', 'content': t.text},
      ],
      'stream': true,
      'max_tokens': 700,
      'temperature': 0.7,
    };
    final headers = {
      if (c.key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer ${c.key}',
    };
    await for (final data in _post(uri, body, headers)) {
      if (data == '[DONE]') return;
      final Object? j;
      try {
        j = jsonDecode(data);
      } catch (_) {
        // Ba’zi bepul xizmatlar oddiy matn qaytaradi.
        if (data.trim().isNotEmpty) yield data;
        continue;
      }
      if (j is! Map) continue;
      final choices = j['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final ch = choices.first as Map;
      final piece =
          (ch['delta'] as Map?)?['content'] ??
          (ch['message'] as Map?)?['content'];
      if (piece is String && piece.isNotEmpty) yield piece;
    }
  }

  /// POST so‘rov. SSE bo‘lsa — har bir `data:` qatori, aks holda butun javob.
  Stream<String> _post(
    Uri uri,
    Map<String, Object?> body,
    Map<String, String> headers,
  ) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'TelefonTV/1.0';
    try {
      final HttpClientResponse res;
      try {
        final req = await client.postUrl(uri);
        req.headers.contentType = ContentType.json;
        headers.forEach(req.headers.set);
        req.add(utf8.encode(jsonEncode(body)));
        res = await req.close().timeout(const Duration(seconds: 30));
      } on TimeoutException {
        throw AiException(
          'AI javob bermadi (vaqt tugadi). Qayta urinib ko‘ring.',
        );
      } on SocketException {
        throw AiException('Internet yo‘q yoki AI xizmatiga ulanib bo‘lmadi.');
      } on HandshakeException {
        throw AiException('AI xizmatiga xavfsiz ulanib bo‘lmadi.');
      }
      if (res.statusCode != 200) {
        final text = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10), onTimeout: () => '');
        throw _error(res.statusCode, text);
      }
      final sse =
          res.headers.contentType?.mimeType == 'text/event-stream' ||
          uri.query.contains('alt=sse');
      final lines = res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
            const Duration(seconds: 25),
            onTimeout: (sink) => sink.addError(
              AiException('AI javobi to‘xtab qoldi. Qayta urinib ko‘ring.'),
            ),
          );
      if (sse) {
        await for (final line in lines) {
          if (line.startsWith('data:')) yield line.substring(5).trim();
        }
      } else {
        final all = await lines.join('\n');
        yield all;
      }
    } finally {
      client.close(force: true);
    }
  }

  static AiException _error(int status, String body) {
    var detail = '';
    try {
      final j = jsonDecode(body);
      final Object? e;
      if (j is List) {
        final first = j.isEmpty ? null : j.first;
        e = first is Map ? first['error'] : null;
      } else {
        e = (j as Map)['error'];
      }
      detail = e is Map ? '${e['message'] ?? ''}' : '${e ?? ''}';
    } catch (_) {
      detail = body.length > 200 ? body.substring(0, 200) : body;
    }
    final lower = detail.toLowerCase();
    final message = switch (status) {
      401 || 403 when lower.contains('location') || lower.contains('region') =>
        'Bu AI xizmati sizning mintaqangizda ishlamaydi. Boshqa xizmatni tanlang.',
      401 || 403 =>
        'AI kaliti noto‘g‘ri yoki muddati o‘tgan. Sozlamalarda tekshiring.',
      400 when lower.contains('api key') =>
        'AI kaliti noto‘g‘ri. Sozlamalar → AI yordamchi’da qayta kiriting.',
      429 =>
        'Bepul limit vaqtincha tugadi. Bir daqiqadan so‘ng urinib ko‘ring.',
      404 => 'Bu model topilmadi.',
      >= 500 => 'AI xizmati hozir band. Birozdan so‘ng urinib ko‘ring.',
      _ => 'AI xatosi ($status)${detail.isEmpty ? '' : ': $detail'}',
    };
    // Kalit xatosi — boshqa modelda ham takrorlanadi, qayta urinmaymiz.
    final keyError = status == 400 && lower.contains('api key');
    return AiException(message, status: keyError ? 401 : status);
  }
}
