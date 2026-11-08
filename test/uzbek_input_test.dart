import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/latin_input.dart';
import 'package:telefon_tv/uzbek_text.dart';
import 'package:telefon_tv/tv/assistant/ai.dart';
import 'package:telefon_tv/tv/store.dart';
import 'support/memory_preferences.dart';

void main() {
  test(
    'Uzbek recognition text becomes Latin with names, spaces and apostrophes',
    () {
      expect(
        uzbekToLatin('Ўзбекистон қўшиқлари Шоҳрух — 2026'),
        'O‘zbekiston qo‘shiqlari Shohrux — 2026',
      );
      expect(uzbekToLatin('Salom! YouTube 4K'), 'Salom! YouTube 4K');
    },
  );
  test(
    'keyboard dictation keeps caret and composition after expanded letters',
    () {
      const value = TextEditingValue(
        text: 'Шаҳар қўшиқ',
        selection: TextSelection(baseOffset: 3, extentOffset: 8),
        composing: TextRange(start: 0, end: 3),
      );
      final result = const UzbekLatinFormatter().formatEditUpdate(
        TextEditingValue.empty,
        value,
      );
      expect(result.text, 'Shahar qo‘shiq');
      expect(
        result.selection,
        const TextSelection(baseOffset: 4, extentOffset: 10),
      );
      expect(result.composing, const TextRange(start: 0, end: 4));
    },
  );
  test(
    'voice, Latin search and background preferences survive an app restart',
    () async {
      final prefs = MemoryPreferences();
      final store = TvStore(preferences: prefs);
      await store.load();
      await store.updateAssistant(
        const AiConfig(
          uzbekVoice: 'Sardor',
          cloudVoice: true,
          latinSearch: false,
        ),
      );
      await store.updateSettings(
        store.settings.value.copyWith(
          volume: 0.25,
          wallpaperBlur: 0.5,
          wallpaperSeconds: 300,
        ),
      );
      final fresh = TvStore(preferences: prefs);
      await fresh.load();
      expect(fresh.assistant.value.uzbekVoice, 'Sardor');
      expect(fresh.assistant.value.cloudVoice, isTrue);
      expect(fresh.assistant.value.latinSearch, isFalse);
      expect(fresh.settings.value.effectiveVolume, 0.25);
      expect(fresh.settings.value.wallpaperBlur, 0.5);
      expect(fresh.settings.value.wallpaperSeconds, 300);
      expect(AiConfig.fromJson({}).cloudVoice, isTrue);
      expect(AiConfig.fromJson({'uzbekVoice': 'unknown'}).uzbekVoice, 'Madina');
    },
  );
}
