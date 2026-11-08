import 'dart:async';
import 'package:telefon_tv/tv/store.dart';
import 'support/memory_preferences.dart';
import 'package:telefon_tv/tv/wallpapers.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WallpaperRepository.enabled = false;
  TvStore.instance = TvStore(preferences: MemoryPreferences());
  await testMain();
}
