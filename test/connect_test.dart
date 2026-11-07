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

  testWidgets('qora pult: tugmalar, matn va AI savoli televizorga yetadi', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    final commands = <Cmd>[];
    final texts = <String>[];
    final asks = <String>[];
    final server = RemoteServer(
      port: 0,
      keyProvider: () => '1234',
      onCommand: commands.add,
      onText: texts.add,
      onMedia: (_) {},
      onAsk: asks.add,
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
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (var i = 0; i < 10 && find.text('Ulangan').evaluate().isEmpty; i++) {
      await settle();
    }
    expect(find.text('Ulangan'), findsOneWidget);
    expect(find.bySemanticsLabel('Fayl yuborish'), findsOneWidget);
    expect(find.bySemanticsLabel('Yordamchi (mikrofon)'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Orqaga'));
    await tester.tap(find.bySemanticsLabel('Keyingi'));
    await tester.tap(find.bySemanticsLabel('Ovozni oshirish'));
    await tester.tap(find.bySemanticsLabel('Yoqish / o‘chirish'));
    await settle();
    expect(commands, [Cmd.back, Cmd.next, Cmd.volUp, Cmd.power]);

    // Klaviatura: matn yuborish.
    await tester.tap(find.bySemanticsLabel('Klaviatura'));
    await settle();
    await tester.enterText(
      find.byType(TextField),
      'https://example.com/kanallar.m3u',
    );
    await tester.tap(find.text('Yuborish'));
    await settle();
    expect(texts, ['https://example.com/kanallar.m3u']);

    // Oddiy matn klaviaturasi va alohida Space tugmasi kursor joyiga bo‘sh joy qo‘yadi.
    await tester.tap(find.bySemanticsLabel('Klaviatura'));
    await settle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.text);
    await tester.enterText(find.byType(TextField), 'Kinoqidirish');
    field.controller!.selection = const TextSelection.collapsed(offset: 4);
    await tester.tap(find.text('Bo‘sh joy (Space)'));
    await tester.pump();
    expect(field.controller!.text, 'Kino qidirish');
    expect(field.controller!.selection.baseOffset, 5);
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.tap(find.text('Yuborish'));
    await settle();
    expect(texts.last, 'Kino qidirish');

    // Kompyuterda mikrofon yo‘q — savol yozib so‘raladi.
    await tester.tap(find.bySemanticsLabel('Yordamchi (mikrofon)'));
    await settle();
    await tester.enterText(find.byType(TextField), 'ob-havo qanday');
    await tester.tap(find.text('AI’dan so‘rash'));
    await settle();
    expect(asks, ['ob-havo qanday']);

    // Televizor javobi pultda ham ko‘rinadi.
    server.broadcast({
      't': 'assist',
      'phase': 'done',
      'q': 'ob-havo qanday',
      'a': 'Toshkentda +12°',
    });
    await settle();
    expect(find.text('Toshkentda +12°'), findsOneWidget);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(server.stop);
  });

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
