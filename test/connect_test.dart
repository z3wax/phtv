import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/phone/connect.dart';
import 'package:telefon_tv/phone/remote_screen.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/server.dart';

void main() {
  test('televizordagi QR koddan manzil, port va PIN olinadi', () {
    final t = parseRemoteUrl('http://192.168.1.5:8765/?k=1234')!;
    expect((t.host, t.port, t.pin), ('192.168.1.5', 8765, '1234'));
    final usb = parseRemoteUrl(' http://172.20.10.2:9000/?k=0042 ')!;
    expect((usb.host, usb.port, usb.pin), ('172.20.10.2', 9000, '0042'));
    expect(parseRemoteUrl('http://192.168.1.5/?k=7'), isNotNull);
    expect(
      parseRemoteUrl('http://192.168.1.5/?k=7')!.port,
      RemoteServer.defaultPort,
    );
    expect(
      parseRemoteUrl('http://192.168.1.5:8765/'),
      isNull,
      reason: 'PIN yo‘q',
    );
    expect(parseRemoteUrl('https://youtube.com/watch?v=1'), isNull);
    expect(parseRemoteUrl('WIFI:S:uy;T:WPA;P:12345678;;'), isNull);
  });

  testWidgets('boshlang‘ich ekran: pult yoki Smart TV tanlanadi', (
    tester,
  ) async {
    var chosen = '';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: StartScreen(
          onRemote: () => chosen = 'remote',
          onTv: () => chosen = 'tv',
        ),
      ),
    );
    await tester.tap(find.text('Pult'));
    expect(chosen, 'remote');
    await tester.tap(find.text('Smart TV shu telefonda'));
    expect(chosen, 'tv');
  });

  testWidgets(
    'ilovadagi pult brauzer pultidagidek: tugma va matn televizorga yetadi',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final commands = <Cmd>[];
      final texts = <String>[];
      final server = RemoteServer(
        port: 0,
        keyProvider: () => '1234',
        onCommand: commands.add,
        onText: texts.add,
        onMedia: (_) {},
      );
      await tester.runAsync(server.start);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RemoteScreen(
            host: '127.0.0.1',
            port: server.boundPort!,
            pin: '1234',
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
      }

      for (var i = 0; i < 10 && find.text('Ulangan').evaluate().isEmpty; i++) {
        await settle();
      }
      expect(find.text('Ulangan'), findsOneWidget);
      expect(
        find.text('Telefondan video / rasm / musiqa yuborish'),
        findsOneWidget,
      );

      await tester.tap(find.text('Orqaga'));
      await tester.tap(find.text('Keyingi'));
      await settle();
      expect(commands, [Cmd.back, Cmd.next]);

      await tester.enterText(
        find.byType(TextField),
        'https://example.com/kanallar.m3u',
      );
      await tester.tap(find.text('Yuborish'));
      await settle();
      expect(texts, ['https://example.com/kanallar.m3u']);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(server.stop);
    },
  );

  testWidgets('PIN noto‘g‘ri bo‘lsa — brauzer pultidagidek xabar', (
    tester,
  ) async {
    final server = RemoteServer(
      port: 0,
      keyProvider: () => '1234',
      onCommand: (_) {},
      onText: (_) {},
      onMedia: (_) {},
    );
    await tester.runAsync(server.start);
    // Loopback’da PIN shart emas, shuning uchun mavjud bo‘lmagan portga ulanamiz.
    final freePort = server.boundPort! + 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: RemoteScreen(host: '127.0.0.1', port: freePort, pin: '0000'),
      ),
    );
    for (
      var i = 0;
      i < 10 && find.text('PIN noto‘g‘ri yoki TV o‘chiq').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }
    expect(find.text('PIN noto‘g‘ri yoki TV o‘chiq'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(server.stop);
  });
}
