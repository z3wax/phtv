import 'package:flutter/material.dart';

import '../assistant/ai.dart';
import '../assistant/assistant.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';

/// AI yordamchi: qaysi bepul xizmat, kalit, ovozli javob, sinab ko‘rish.
class AssistantSettingsScreen extends StatelessWidget {
  const AssistantSettingsScreen({super.key});

  static const _next = {
    AiProvider.free: AiProvider.gemini,
    AiProvider.gemini: AiProvider.groq,
    AiProvider.groq: AiProvider.custom,
    AiProvider.custom: AiProvider.free,
  };

  @override
  Widget build(BuildContext context) {
    final store = TvStore.instance;
    final services = TvServices.instance;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            children: [
              const TvHeader(title: 'AI yordamchi'),
              const SizedBox(height: 20),
              Expanded(
                child: ValueListenableBuilder<AiConfig>(
                  valueListenable: store.assistant,
                  builder: (context, c, _) {
                    final keyHelp = switch (c.provider) {
                      AiProvider.gemini =>
                        'Bepul kalit: aistudio.google.com/apikey → “Create API key” (karta shart emas)',
                      AiProvider.groq =>
                        'Bepul kalit: console.groq.com/keys → “Create API Key”',
                      AiProvider.custom =>
                        'OpenRouter, LLM7, Ollama va boshqa OpenAI-mos xizmat kaliti',
                      AiProvider.free => '',
                    };
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
                      children: [
                        _Row(
                          icon: Icons.auto_awesome_rounded,
                          title: 'Xizmat',
                          subtitle: switch (c.provider) {
                            AiProvider.free =>
                              'Kalitsiz darrov ishlaydi. Tezroq va aqlliroq bo‘lishi uchun Gemini yoki Groq’ning bepul kalitini kiriting',
                            AiProvider.gemini =>
                              'O‘zbek tilini eng yaxshi tushunadi, Google qidiruvi bilan yangiliklarni ham biladi',
                            AiProvider.groq =>
                              'Eng tez javob (Llama), bepul limit katta',
                            AiProvider.custom =>
                              'O‘zingiz tanlagan OpenAI-mos manzil',
                          },
                          value: c.label,
                          autofocus: true,
                          onTap: () => store.updateAssistant(
                            c.copyWith(provider: _next[c.provider]),
                          ),
                        ),
                        if (c.provider != AiProvider.free)
                          _Row(
                            icon: Icons.key_rounded,
                            title: 'Kalit (API key)',
                            subtitle: keyHelp,
                            value: c.key.isEmpty
                                ? 'Kiritilmagan'
                                : '••••${c.key.length > 4 ? c.key.substring(c.key.length - 4) : ''}',
                            onTap: () => services.editText(
                              context,
                              title: '${c.label} — kalit',
                              value: c.key,
                              onSubmit: (v) => store.updateAssistant(
                                c.copyWith(key: v.trim()),
                              ),
                            ),
                          ),
                        if (c.provider == AiProvider.custom)
                          _Row(
                            icon: Icons.link_rounded,
                            title: 'Manzil',
                            subtitle:
                                'Masalan: https://openrouter.ai/api/v1/chat/completions',
                            value: c.endpoint.isEmpty
                                ? 'Kiritilmagan'
                                : c.endpoint,
                            onTap: () => services.editText(
                              context,
                              title: 'OpenAI-mos manzil',
                              value: c.endpoint,
                              onSubmit: (v) => store.updateAssistant(
                                c.copyWith(endpoint: v.trim()),
                              ),
                            ),
                          ),
                        if (c.provider != AiProvider.free)
                          _Row(
                            icon: Icons.memory_rounded,
                            title: 'Model',
                            subtitle:
                                'Bo‘sh qoldiring — eng mosi o‘zi tanlanadi',
                            value: c.model.isEmpty ? 'Avtomatik' : c.model,
                            onTap: () => services.editText(
                              context,
                              title: 'Model nomi (bo‘sh — avtomatik)',
                              value: c.model,
                              onSubmit: (v) => store.updateAssistant(
                                c.copyWith(model: v.trim()),
                              ),
                            ),
                          ),
                        if (c.provider == AiProvider.gemini)
                          _Row(
                            icon: Icons.travel_explore_rounded,
                            title: 'Google qidiruvi bilan javob',
                            subtitle:
                                'Yangiliklar, narxlar, o‘yin natijalari — hozirgi ma’lumot',
                            value: c.webSearch ? 'Yoniq' : 'O‘chiq',
                            onTap: () => store.updateAssistant(
                              c.copyWith(webSearch: !c.webSearch),
                            ),
                          ),
                        _Row(
                          icon: Icons.record_voice_over_rounded,
                          title: 'Ovozli javob',
                          subtitle: 'Javobni televizor ovoz chiqarib aytadi',
                          value: c.voice ? 'Yoniq' : 'O‘chiq',
                          onTap: () => store.updateAssistant(
                            c.copyWith(voice: !c.voice),
                          ),
                        ),
                        _Row(
                          icon: Icons.play_circle_rounded,
                          title: 'Sinab ko‘rish',
                          subtitle:
                              'Yordamchiga savol berish (pultdagi 🎤 tugmasi ham)',
                          onTap: () => services.editText(
                            context,
                            title: 'Savol yoki buyruq',
                            value: 'Salom! Sen nimalar qila olasan?',
                            onSubmit: Assistant.instance.ask,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Misollar: “YouTube’da multfilm qo‘y”, “Sevimli TV ni qo‘y”, '
                          '“ovozni ko‘tar”, “ob-havo qanday”, “ivi’ni och”, “Messi necha yoshda?”. '
                          'Kalitlar faqat shu qurilmada saqlanadi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TvFocusable(
        autofocus: autofocus,
        scale: 1.02,
        radius: 18,
        onTap: onTap,
        builder: (context, f) {
          final fg = f ? Colors.black : Colors.white;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            color: f ? Colors.white : Colors.white.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 30),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 15,
                            color: fg.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.6),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
