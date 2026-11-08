import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/m3u.dart';
import 'package:telefon_tv/tv/model.dart';

void main() {
  test('M3U pleylistdan kanallar, logotip va guruh olinadi', () {
    const text = '''
#EXTM3U
#EXTINF:-1 tvg-id="Sevimli.uz" tvg-logo="https://example.com/sevimli.png" group-title="Entertainment",Sevimli TV (1080p)
https://example.com/sevimli/index.m3u8
#EXTINF:-1 tvg-logo="" group-title="News;General",Dunyo bo'ylab
http://example.com/dunyo.m3u8
#EXTINF:-1,Nomsiz guruh
rtmp://example.com/live/stream
#EXTINF:-1,Buzuq qator
not a url
''';
    final list = parseM3u(text);
    expect(list, hasLength(3));
    expect(list[0].title, 'Sevimli TV (1080p)');
    expect(list[0].logo, 'https://example.com/sevimli.png');
    expect(list[0].group, 'Ko‘ngilochar');
    expect(list[0].kind, MediaKind.live);
    expect(list[1].title, "Dunyo bo'ylab");
    expect(list[1].logo, isNull);
    expect(list[1].group, 'Yangiliklar');
    expect(list[2].group, 'Boshqa');
    expect(list[2].source, 'rtmp://example.com/live/stream');
  });

  test('MediaItem JSON orqali saqlanib, qayta tiklanadi', () {
    final item = MediaItem(
      title: 'Kino',
      source: '/tmp/kino.mp4',
      kind: MediaKind.video,
      positionMs: 1000,
      durationMs: 4000,
    );
    final back = MediaItem.fromJson(item.toJson())!;
    expect(back.title, 'Kino');
    expect(back.isFile, isTrue);
    expect(back.progress, 0.25);
    expect(MediaItem.kindForName('qoshiq.MP3'), MediaKind.audio);
    expect(MediaItem.kindForName('rasm.heic'), MediaKind.image);
    expect(MediaItem.kindForName('hujjat.pdf'), isNull);
  });
}
