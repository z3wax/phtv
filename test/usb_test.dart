import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/phone/usb_screen.dart';
import 'package:telefon_tv/tv/model.dart';
import 'package:telefon_tv/usb.dart';

void main() {
  test('fayl nomi oddiy televizor o‘qiy oladigan shaklga keltiriladi', () {
    expect(
      safeFileName('O‘zbekiston bo‘ylab sayohat', 'MP4'),
      'ozbekiston_boylab_sayohat.mp4',
    );
    expect(safeFileName('Тошкент оқшоми', 'mov'), 'toshkent_oqshomi.mov');
    expect(safeFileName('IMG_0042 (1)', 'HEIC'), 'img_0042_1.heic');
    expect(safeFileName('!!!', ''), 'fayl');
    expect(safeFileName('a' * 100, 'jpg').length, 48 + 4);
    expect(extensionOf('/a.b/video'), '');
    expect(extensionOf('/x/y/clip.MP4'), 'MP4');
  });

  test('Yasin LED-32E58TS profili 720p va 1920 px', () {
    final yasin = usbProfiles.first;
    expect(yasin.name, 'Yasin LED-32E58TS');
    expect(yasin.maxVideoShort, 720);
    expect(yasin.maxImageSide, 1920);
  });

  test(
    'fayllar VIDEO / FOTO / MUSIQA papkalariga ajratiladi, nomlar takrorlanmaydi',
    () {
      final plan = planUsb([
        MediaItem(title: 'Kino', source: '/p/kino.mp4', kind: MediaKind.video),
        MediaItem(title: 'Kino', source: '/q/kino.mp4', kind: MediaKind.video),
        MediaItem(title: 'Oila', source: '/p/oila.heic', kind: MediaKind.image),
        MediaItem(title: 'Qo‘shiq', source: '/p/q.mp3', kind: MediaKind.audio),
        MediaItem(
          title: 'Kanal',
          source: 'https://x/live.m3u8',
          kind: MediaKind.live,
        ),
      ]);
      expect(plan.map((f) => '${f.folder}/${f.name}'), [
        'VIDEO/kino.mp4',
        'VIDEO/kino_2.mp4',
        'FOTO/oila.heic',
        'MUSIQA/qoshiq.mp3',
      ]);
    },
  );

  test('video konvertatsiyasining MP4 nomi ham band qilinadi', () {
    for (final extensions in [
      ['mov', 'mp4', 'mkv'],
      ['mp4', 'mov', 'mkv'],
    ]) {
      final plan = planUsb([
        for (final ext in extensions)
          MediaItem(
            title: 'Kino',
            source: '/p/kino.$ext',
            kind: MediaKind.video,
          ),
      ]);
      expect(plan.map((f) => f.name), [
        'kino.${extensions[0]}',
        'kino_2.${extensions[1]}',
        'kino_3.${extensions[2]}',
      ]);
      // Natijani bitta formatga o‘tkazish ham nomlarni birlashtirmaydi.
      final converted = plan.map(
        (f) => f.name.replaceFirst(RegExp(r'\.[^.]+$'), '.mp4'),
      );
      expect(converted.toSet().length, plan.length);
    }
  });

  test('HEIC va JPEG konvertatsiyasi bir nomga tushmaydi', () {
    final plan = planUsb([
      MediaItem(title: 'Oila', source: '/p/oila.heic', kind: MediaKind.image),
      MediaItem(title: 'Oila', source: '/p/oila.jpg', kind: MediaKind.image),
      MediaItem(title: 'Oila', source: '/p/oila.jpeg', kind: MediaKind.image),
      MediaItem(
        title: 'Oila_2',
        source: '/p/oila_2.webp',
        kind: MediaKind.image,
      ),
    ]);
    expect(plan.map((f) => f.name), [
      'oila.heic',
      'oila_2.jpg',
      'oila_3.jpeg',
      'oila_2_2.webp',
    ]);
  });

  testWidgets('USB ekrani yo‘riqnoma va tugmalarni ko‘rsatadi', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: const UsbScreen()),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Fleshkani tanlash'), findsOneWidget);
    expect(find.textContaining('Yasin: pultda SOURCE'), findsOneWidget);
    expect(find.textContaining('Telefonsiz doimiy Smart TV'), findsOneWidget);
    // Standart profil — aynan Yasin LED-32E58TS: 720p H.264, HDMI haqida eslatma.
    expect(find.text('Yasin LED-32E58TS'), findsOneWidget);
    expect(find.textContaining('H.264 720p MP4'), findsOneWidget);
    expect(find.textContaining('Orqasida HDMI uyasi bor'), findsOneWidget);
    // Boshqa televizor tanlansa — 1080p.
    await tester.tap(find.text('Boshqa Full HD televizor'));
    await tester.pump();
    expect(find.textContaining('H.264 1080p MP4'), findsOneWidget);
    expect(find.textContaining('Orqasida HDMI uyasi bor'), findsNothing);
    // Fayl tanlanmaguncha yozish tugmasi o‘chiq.
    final write = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Fleshkaga yozish'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(write.onPressed, isNull);
  });
}
