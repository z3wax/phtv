import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/screens/apps_screen.dart';
import 'package:telefon_tv/tv/screens/settings_screen.dart';
import 'package:telefon_tv/tv/services.dart';

const channel = MethodChannel('telefon_tv/native');

void main() {
  final calls = <MethodCall>[];
  var home = false;

  setUp(() {
    calls.clear();
    home = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isTvDevice':
              return true;
            case 'isHomeLauncher':
              return home;
            case 'setHomeLauncher':
              home = (call.arguments as Map)['on'] == true;
              return true;
            case 'listApps':
              return [
                {
                  'package': 'com.google.android.youtube.tv',
                  'label': 'YouTube',
                  'icon': Uint8List(0),
                },
                {
                  'package': 'uz.kinoteatr',
                  'label': 'Kinoteatr',
                  'icon': Uint8List(0),
                },
              ];
            case 'launchApp':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TvServices.instance.dispose();
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'TV qutisidagi ilovalar ro‘yxati ochiladi va ilova ishga tushadi',
    (tester) async {
      await pump(tester, const AppsScreen());
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Kinoteatr'), findsOneWidget);
      await tester.tap(find.text('Kinoteatr'));
      await tester.pump();
      final launch = calls.lastWhere((c) => c.method == 'launchApp');
      expect((launch.arguments as Map)['package'], 'uz.kinoteatr');
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('TV qutisida “Yoqilganda Telefon TV ochilsin” yoqiladi', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    await tester.scrollUntilVisible(
      find.text('Yoqilganda Telefon TV ochilsin'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Yoqilganda Telefon TV ochilsin'), findsOneWidget);
    expect(find.text('O‘chiq'), findsOneWidget);
    await tester.ensureVisible(find.text('Yoqilganda Telefon TV ochilsin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yoqilganda Telefon TV ochilsin'));
    await tester.pumpAndSettle();
    expect(home, isTrue);
    expect(find.text('Yoniq'), findsOneWidget);
  });
}
