import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/assistant/assistant.dart';
import 'package:telefon_tv/tv/assistant/overlay.dart';
import 'package:telefon_tv/tv/assistant/tts.dart';
import 'package:telefon_tv/tv/input.dart';

void main() {
  setUp(() {
    Speech.instance.enabled = false;
    Assistant.instance.dismiss();
  });

  tearDown(() {
    Assistant.instance.dismiss();
    Speech.instance.enabled = true;
  });

  Future<void> openScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final input = TvInput.instance;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: input.navigatorKey,
        navigatorObservers: [input.routes],
        builder: (_, child) =>
            Stack(children: [child!, const AssistantOverlay()]),
        home: const Scaffold(body: Text('Bosh ekran')),
      ),
    );
    input.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Ikkinchi ekran')),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ovozli orqaga paneldan o‘tib, oldingi ekranni ochadi', (
    tester,
  ) async {
    await openScreen(tester);

    await Assistant.instance.ask('orqaga');
    await tester.pump(const Duration(seconds: 1));

    expect(TvInput.instance.navigatorKey.currentState!.canPop(), isFalse);
    expect(find.text('Bosh ekran'), findsOneWidget);
    expect(Assistant.instance.state.value.phase, AssistPhase.done);
    expect(Assistant.instance.state.value.answer, 'Orqaga');
    Assistant.instance.dismiss();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ovozli pult buyruqlari va javobi panel tomonidan bekor qilinmaydi',
    (tester) async {
      await openScreen(tester);
      final commands = <Cmd>[];
      bool capture(Cmd cmd) {
        commands.add(cmd);
        return true;
      }

      TvInput.instance.push(capture);
      addTearDown(() => TvInput.instance.remove(capture));

      await Assistant.instance.ask('ovozni ancha ko‘tar');
      expect(commands, List.filled(4, Cmd.volUp));
      expect(Assistant.instance.state.value.phase, AssistPhase.done);
      expect(Assistant.instance.state.value.answer, 'Ovoz balandladi');

      commands.clear();
      await Assistant.instance.ask('pauza');
      expect(commands, [Cmd.playPause]);
      expect(Assistant.instance.state.value.phase, AssistPhase.done);
      Assistant.instance.dismiss();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('qo‘lda Orqaga bosish avval yordamchi panelini yopadi', (
    tester,
  ) async {
    await openScreen(tester);
    await Assistant.instance.ask('soat necha');

    TvInput.instance.send(Cmd.back);
    await tester.pumpAndSettle();

    expect(Assistant.instance.state.value.phase, AssistPhase.idle);
    expect(TvInput.instance.navigatorKey.currentState!.canPop(), isTrue);
    expect(find.text('Ikkinchi ekran'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
