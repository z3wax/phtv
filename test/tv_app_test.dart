import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/tv_app.dart';

String? focusedText() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final texts = <String>[];
  void visit(Element e) {
    final w = e.widget;
    if (w is Text && w.data != null) texts.add(w.data!);
    e.visitChildElements(visit);
  }

  (ctx as Element).visitChildElements(visit);
  return texts.join(' | ');
}

void main() {
  Future<void> pumpTv(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TvApp(onTvDisplay: false, services: false));
    await tester.pumpAndSettle();
  }

  for (final size in const [
    Size(1920, 1080),
    Size(1280, 720),
    Size(1366, 768),
    Size(844, 390),
  ]) {
    testWidgets(
      'bosh ekran ${size.width.toInt()}x${size.height.toInt()} da sig‘adi',
      (tester) async {
        await pumpTv(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.text('JONLI'), findsOneWidget);
        expect(find.text('OXIRGI KO‘RILGAN'), findsOneWidget);
        // Markaziy karta avtomatik tanlangan.
        expect(focusedText(), contains('JONLI TV'));
      },
    );
  }

  testWidgets('pult bilan yurish: sahifalar, ilova ochish va orqaga', (
    tester,
  ) async {
    await pumpTv(tester, const Size(1280, 720));
    final input = TvInput.instance;

    input.send(Cmd.left);
    input.send(Cmd.up);
    await tester.pumpAndSettle();
    expect(focusedText(), contains('OXIRGI KO‘RILGAN'));

    input.send(Cmd.right);
    input.send(Cmd.right);
    await tester.pumpAndSettle();
    expect(focusedText(), anyOf(contains('MUSIQA'), contains('PULT')));

    // Pastga: dokka, keyin ikkinchi sahifaga (media markazi).
    for (
      var i = 0;
      i < 4 && find.text('Media markazi').evaluate().isEmpty;
      i++
    ) {
      input.send(Cmd.down);
      await tester.pumpAndSettle();
    }
    expect(find.text('Media markazi'), findsOneWidget);
    expect(focusedText(), contains('Ochish'));

    // Orqaga — birinchi sahifa.
    input.send(Cmd.back);
    await tester.pumpAndSettle();
    expect(find.text('Media markazi'), findsNothing);
    expect(find.text('JONLI'), findsOneWidget);

    // Markaziy karta → Jonli TV (kanallar hali yo‘q).
    input.send(Cmd.left);
    input.send(Cmd.right);
    await tester.pumpAndSettle();
    input.send(Cmd.ok);
    await tester.pumpAndSettle();
    expect(find.text('Kanallar hali qo‘shilmagan'), findsOneWidget);
    expect(focusedText(), contains('O‘zbekiston kanallari'));

    input.send(Cmd.back);
    await tester.pumpAndSettle();
    expect(find.text('Kanallar hali qo‘shilmagan'), findsNothing);
    expect(find.text('JONLI'), findsOneWidget);
  });

  testWidgets('klaviatura va Bluetooth pult tugmalari ishlaydi', (
    tester,
  ) async {
    await pumpTv(tester, const Size(1280, 720));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusedText(), contains('OXIRGI KO‘RILGAN'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedText(), anyOf(contains('Ob-havo'), contains('°')));
    // Sozlamalarni ochadi (ob-havo vidjeti → sozlamalar).
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Ob-havo shahri'), findsOneWidget);
    // Shaharni almashtirish (OK) va orqaga (Esc).
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Samarqand'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Ob-havo shahri'), findsNothing);
    expect(find.text('JONLI'), findsOneWidget);
  });

  test('tugmalar buyruqqa aylanadi', () {
    KeyEvent down(LogicalKeyboardKey k) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: k,
      timeStamp: Duration.zero,
    );
    expect(TvInput.commandForKey(down(LogicalKeyboardKey.arrowUp)), Cmd.up);
    expect(TvInput.commandForKey(down(LogicalKeyboardKey.select)), Cmd.ok);
    expect(
      TvInput.commandForKey(down(LogicalKeyboardKey.gameButtonB)),
      Cmd.back,
    );
    expect(
      TvInput.commandForKey(down(LogicalKeyboardKey.mediaPlayPause)),
      Cmd.playPause,
    );
    expect(TvInput.commandForKey(down(LogicalKeyboardKey.channelUp)), Cmd.next);
    expect(TvInput.commandForKey(down(LogicalKeyboardKey.keyQ)), isNull);
  });

  testWidgets(
    'ekrandan Home bilan qaytgach pult ishlayveradi (fokus tiklanadi)',
    (tester) async {
      await pumpTv(tester, const Size(1280, 720));
      final input = TvInput.instance;
      // Markaziy karta → Jonli TV.
      input.send(Cmd.ok);
      await tester.pumpAndSettle();
      expect(find.text('Kanallar hali qo‘shilmagan'), findsOneWidget);
      // Fokus yo‘qolgan holat (film tugagach Home bosilgandek).
      FocusManager.instance.primaryFocus?.unfocus();
      input.send(Cmd.home);
      await tester.pumpAndSettle();
      expect(find.text('Kanallar hali qo‘shilmagan'), findsNothing);
      expect(focusedText(), isNotNull, reason: 'bosh ekranda tugma tanlangan');
      // Pult tugmalari yana ishlaydi.
      final before = focusedText();
      input.send(Cmd.left);
      await tester.pumpAndSettle();
      expect(focusedText(), isNot(before));
      input.send(Cmd.ok);
      await tester.pumpAndSettle();
      expect(find.byType(TvApp), findsOneWidget);
    },
  );

  testWidgets('fokus butunlay yo‘qolsa ham birinchi bosish uni tiklaydi', (
    tester,
  ) async {
    await pumpTv(tester, const Size(1280, 720));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    TvInput.instance.send(Cmd.right);
    await tester.pumpAndSettle();
    expect(focusedText(), isNotNull);
  });
}
