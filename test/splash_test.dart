import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/motion.dart';

void main() {
  late bool motion;
  setUp(() => motion = TvMotion.enabled);
  tearDown(() => TvMotion.enabled = motion);

  for (final (name, size) in [
    ('televizor', const Size(1280, 720)),
    ('telefon', const Size(390, 844)),
  ]) {
    testWidgets('“z3wax tv” yuklanish ekrani: $name', (tester) async {
      TvMotion.enabled = true;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned.fill(child: Text('HOME')),
              Positioned.fill(child: TvSplash()),
            ],
          ),
        ),
      );
      expect(find.text('z3wax'), findsOneWidget);
      for (var ms = 0; ms < 3000; ms += 300) {
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
      expect(find.text('z3wax'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('z3wax'), findsNothing);

      // Uyqudan uyg‘onganda — qaytadan.
      TvSplash.replay();
      await tester.pump();
      expect(find.text('z3wax'), findsOneWidget);
      // Bosilsa — kutmasdan yo‘qoladi.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(Offset(size.width / 2, size.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('z3wax'), findsNothing);
    });
  }

  testWidgets('animatsiyalar o‘chiq bo‘lsa — ko‘rinmaydi', (tester) async {
    TvMotion.enabled = false;
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: TvSplash()),
    );
    expect(find.text('z3wax'), findsNothing);
    TvSplash.replay();
    await tester.pump();
    expect(find.text('z3wax'), findsNothing);
  });
}
