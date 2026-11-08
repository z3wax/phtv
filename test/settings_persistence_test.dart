import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'support/memory_preferences.dart';
import 'package:telefon_tv/tv/store.dart';

class DelayedPreferences extends MemoryPreferences {
  @override
  Future<void> setString(String key, String value) async {
    await Future<void>.delayed(
      Duration(milliseconds: value.contains('"volume":0.0') ? 20 : 1),
    );
    await super.setString(key, value);
  }
}

void main() {
  test('saved volume and mute restore in a fresh application store', () async {
    final disk = MemoryPreferences();
    final first = TvStore(preferences: disk);
    await first.load();
    await first.setVolume(0.35);
    await first.toggleMute();
    final restarted = TvStore(preferences: disk);
    await restarted.load();
    expect(restarted.settings.value.volume, 0.35);
    expect(restarted.settings.value.effectiveVolume, 0);
    await restarted.toggleMute();
    expect(restarted.settings.value.effectiveVolume, 0.35);
    final again = TvStore(preferences: disk);
    await again.load();
    expect(again.settings.value.effectiveVolume, 0.35);
  });
  test(
    'rapid changes persist the last value and preserve other settings',
    () async {
      final disk = DelayedPreferences();
      final store = TvStore(preferences: disk);
      await store.load();
      await store.updateSettings(store.settings.value.copyWith(city: 3));
      final writes = [for (var i = 0; i < 15; i++) store.setVolume(i / 20)];
      await Future.wait(writes);
      final restarted = TvStore(preferences: disk);
      await restarted.load();
      expect(restarted.settings.value.volume, 0.7);
      expect(restarted.settings.value.city, 3);
      expect((jsonDecode(disk.data['settings']!) as Map)['volume'], 0.7);
    },
  );
  test('old settings migrate and stored volume stays within range', () {
    expect(TvSettings.fromJson({'city': 2}).volume, 1);
    expect(TvSettings.fromJson({'volume': 9}).volume, 1);
    expect(TvSettings.fromJson({'volume': -3}).volume, 0);
    expect(TvSettings.fromJson({'volume': 'bad'}).volume, 1);
  });
}
