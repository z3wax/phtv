import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/linux_player.dart';

void main() {
  test('mpv ning zararsiz xabarlari ijroni to‘xtatmaydi', () {
    for (final harmless in [
      'Could not open codec.',
      'Could not open/initialize audio device -> no sound.',
      'Failed to open VDPAU backend',
    ]) {
      expect(TvLinuxPlayer.isFatal(harmless), isFalse, reason: harmless);
    }
    for (final fatal in [
      'Failed to open https://example.com/kanal.m3u8.',
      'Failed to recognize file format.',
      'HTTP error 404 Not Found',
    ]) {
      expect(TvLinuxPlayer.isFatal(fatal), isTrue, reason: fatal);
    }
  });
}
