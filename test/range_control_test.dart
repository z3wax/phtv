import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/store.dart';
import 'package:telefon_tv/tv/widgets.dart';

void main() {
  testWidgets(
    'remote slider updates the shared saved volume including unmute',
    (tester) async {
      final store = TvStore.instance;
      await store.setVolume(0.3);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<TvSettings>(
              valueListenable: store.settings,
              builder: (c, s, _) => TvRangeControl(
                icon: Icons.volume_up,
                title: 'Ovoz',
                value: s.effectiveVolume,
                onChanged: store.setVolume,
              ),
            ),
          ),
        ),
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.focusNode!.requestFocus();
      await tester.pump();
      TvInput.instance.send(Cmd.left);
      await tester.pump();
      expect(store.settings.value.volume, 0.25);
      expect(find.text('25%'), findsOneWidget);
      await store.toggleMute();
      await tester.pump();
      expect(find.text('0%'), findsOneWidget);
      TvInput.instance.send(Cmd.right);
      await tester.pump();
      expect(store.settings.value.effectiveVolume, 0.05);
      expect(store.settings.value.muted, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
