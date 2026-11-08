import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telefon_tv/tv/assistant/ai.dart';
import 'package:telefon_tv/tv/assistant/assistant.dart';
import 'package:telefon_tv/tv/assistant/overlay.dart';
import 'package:telefon_tv/tv/assistant/tts.dart';
import 'package:telefon_tv/tv/external.dart';
import 'package:telefon_tv/tv/input.dart';
import 'package:telefon_tv/tv/screens/browser_screen.dart';
import 'package:telefon_tv/tv/services.dart';

const browserChannel = MethodChannel('telefon_tv/browser');

class BrowserTestAi extends AiClient {
  final requests = <List<AiTurn>>[];

  @override
  Stream<String> chat(
    AiConfig config, {
    required String system,
    required List<AiTurn> turns,
  }) async* {
    requests.add(turns);
    yield 'Sahifa haqida javob.';
  }
}

void main() {
  if (!Platform.isLinux) return;
  final calls = <MethodCall>[];
  var focusedInput = true;
  var failCreate = false;
  var clickInput = false;
  var navResult = 'moved';
  var blockBounds = false;
  Completer<void>? boundsGate;
  late AiClient previousAi;
  late BrowserTestAi ai;

  setUp(() {
    calls.clear();
    focusedInput = true;
    failCreate = false;
    clickInput = false;
    navResult = 'moved';
    blockBounds = false;
    boundsGate = null;
    Assistant.instance.dismiss();
    previousAi = Assistant.instance.client;
    Assistant.instance.client = ai = BrowserTestAi();
    Speech.instance.enabled = false;
    TvServices.instance.onTvDisplay = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browserChannel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'create':
              if (failCreate) {
                throw MissingPluginException();
              }
            case 'canGoBack':
              return false;
            case 'setBounds':
              if (blockBounds) await boundsGate!.future;
            case 'runJavaScript':
              final args = call.arguments as Map;
              if (args['result'] == true) {
                final script = args['script'] as String;
                if (script.contains('function(v)')) {
                  return jsonEncode(focusedInput);
                }
                if (script.contains('__z3nav.ok(')) {
                  return jsonEncode(
                    clickInput ? 'input:old text' : 'click:0.25,0.75',
                  );
                }
                if (script.contains('__z3nav.move(')) {
                  return jsonEncode(navResult);
                }
                if (script == 'window.scrollY') return '0';
                return jsonEncode('Sahifa matni');
              }
          }
          return null;
        });
  });

  tearDown(() {
    Assistant.instance.dismiss();
    Assistant.instance.client = previousAi;
    Speech.instance.enabled = true;
    TvServices.instance.onTvDisplay = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(browserChannel, null);
    TvServices.instance.dispose();
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: TvInput.instance.navigatorKey,
        navigatorObservers: [TvInput.instance.routes],
        builder: (_, child) =>
            Stack(children: [child!, const AssistantOverlay()]),
        home: const Scaffold(body: Text('HOME')),
      ),
    );
  }

  void open(String url) => TvServices.instance.openSite(url, 'Sayt');

  Future<void> close(WidgetTester tester) async {
    Assistant.instance.dismiss();
    TvServices.instance.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('YouTube opens as YouTube TV inside the app', (tester) async {
    await start(tester);
    TvServices.instance.openYoutube('Ўзбек қўшиқлари');
    await tester.pumpAndSettle();
    expect(find.byType(BrowserScreen), findsOneWidget);
    final create = calls.firstWhere((c) => c.method == 'create');
    expect((create.arguments as Map)['userAgent'], tvUserAgent);
    final load = calls.firstWhere((c) => c.method == 'load');
    final url = Uri.parse((load.arguments as Map)['url'] as String);
    expect(url.host, 'www.youtube.com');
    expect(url.path, '/tv');
    expect(Uri.parse(url.fragment).queryParameters['q'], 'O‘zbek qo‘shiqlari');
    expect(calls.any((c) => c.method == 'setBounds'), isTrue);
    // Pult tugmalari sahifaga klaviatura tugmasi bo‘lib boradi.
    TvInput.instance.send(Cmd.down);
    TvInput.instance.send(Cmd.ok);
    await tester.pumpAndSettle();
    final keys = [
      for (final c in calls.where((c) => c.method == 'sendKey'))
        (c.arguments as Map)['key'],
    ];
    expect(keys, ['down', 'enter']);
    // Pultdan yozilgan matn — YouTube TV qidiruvi.
    TvInput.instance.receiveText('multfilm');
    await tester.pumpAndSettle();
    final search = Uri.parse(
      (calls.lastWhere((c) => c.method == 'load').arguments as Map)['url']
          as String,
    );
    expect(search.path, '/tv');
    expect(Uri.parse(search.fragment).queryParameters['q'], 'multfilm');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('YouTube links open in the TV view', (tester) async {
    await start(tester);
    open('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    await tester.pumpAndSettle();
    final create = calls.firstWhere((c) => c.method == 'create');
    expect((create.arguments as Map)['userAgent'], tvUserAgent);
    final load = calls.firstWhere((c) => c.method == 'load');
    expect(
      (load.arguments as Map)['url'],
      'https://www.youtube.com/tv#/watch?v=dQw4w9WgXcQ',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('sites use TV selection instead of a mouse cursor', (
    tester,
  ) async {
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();
    final create = calls.firstWhere((c) => c.method == 'create');
    expect((create.arguments as Map)['userAgent'], isNot(tvUserAgent));

    TvInput.instance.send(Cmd.down);
    TvInput.instance.send(Cmd.right);
    await tester.pumpAndSettle();
    final scripts = calls
        .where((c) => c.method == 'runJavaScript')
        .map((c) => (c.arguments as Map)['script'] as String)
        .toList();
    expect(scripts.any((s) => s.endsWith("__z3nav.move('down')")), isTrue);
    expect(scripts.any((s) => s.endsWith("__z3nav.move('right')")), isTrue);
    expect(calls.any((c) => c.method == 'pointer'), isFalse);
    expect(calls.any((c) => c.method == 'sendKey'), isFalse);

    // OK — tanlangan havola o‘rtasiga haqiqiy bosish.
    TvInput.instance.send(Cmd.ok);
    await tester.pumpAndSettle();
    final click = calls.lastWhere((c) => c.method == 'click');
    expect((click.arguments as Map)['fx'], 0.25);
    expect((click.arguments as Map)['fy'], 0.75);

    // Sahifa tepasida ↑ — yuqoridagi tugmalar paneli.
    navResult = 'top';
    TvInput.instance.send(Cmd.up);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'browser-tools');
    await close(tester);
  });

  testWidgets('returning restores page AI, keyboard and native view', (
    tester,
  ) async {
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();
    final firstContext = Assistant.instance.pageContext;
    final firstText = TvInput.instance.textTarget;
    final firstId =
        (calls.firstWhere((c) => c.method == 'create').arguments as Map)['id'];
    expect(firstContext, isNotNull);
    open('https://second.example/');
    await tester.pumpAndSettle();
    expect(Assistant.instance.pageContext, isNot(firstContext));
    TvInput.instance.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BrowserScreen), findsOneWidget);
    expect(Assistant.instance.pageContext, firstContext);
    expect(TvInput.instance.textTarget, same(firstText));
    expect(await Assistant.instance.pageContext!(), contains('first.example'));
    final visibility = calls.where(
      (c) => c.method == 'setVisible' && (c.arguments as Map)['id'] == firstId,
    );
    expect((visibility.last.arguments as Map)['visible'], isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'remote keyboard sends spaces to page and searches when no input',
    (tester) async {
      await start(tester);
      open('https://first.example/');
      await tester.pumpAndSettle();
      TvInput.instance.receiveText('salom dunyo');
      await tester.pumpAndSettle();
      final scripts = calls
          .where((c) => c.method == 'runJavaScript')
          .map((c) => (c.arguments as Map)['script'] as String);
      expect(scripts.any((s) => s.contains(jsonEncode('salom dunyo'))), isTrue);
      focusedInput = false;
      TvInput.instance.receiveText('ikki so‘z');
      await tester.pumpAndSettle();
      final last = calls.lastWhere((c) => c.method == 'load');
      final url = Uri.parse((last.arguments as Map)['url'] as String);
      expect(url.queryParameters['q'], 'ikki so‘z');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('empty or failed browser tolerates next and previous', (
    tester,
  ) async {
    failCreate = true;
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();
    expect(
      find.text('Ichki brauzerni ishga tushirib bo‘lmadi'),
      findsOneWidget,
    );
    TvInput.instance.send(Cmd.next);
    TvInput.instance.send(Cmd.prev);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('pending TV question keeps its own remote text target', (
    tester,
  ) async {
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();
    TvServices.instance.onTvDisplay = true;

    await tester.tap(find.text('Savol'));
    await tester.pumpAndSettle();
    expect(TvInput.instance.textTarget?.hint, contains('Sahifa haqida savol'));

    TvInput.instance.receiveText('Bu sahifa nima haqida?');
    await tester.pumpAndSettle();
    expect(ai.requests, hasLength(1));
    expect(ai.requests.single.last.text, contains('Sahifa matni'));
    expect(TvInput.instance.textTarget?.hint, 'Matn yoki qidiruv');
    expect(calls.where((c) => c.method == 'load'), hasLength(1));
    await close(tester);
  });

  testWidgets('local page question retains page context after dialog closes', (
    tester,
  ) async {
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Savol'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    TvInput.instance.receiveText('Bu sahifa nima haqida?');
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(ai.requests, hasLength(1));
    expect(ai.requests.single.last.text, contains('first.example'));
    expect(ai.requests.single.last.text, contains('Sahifa matni'));
    expect(TvInput.instance.textTarget?.hint, 'Matn yoki qidiruv');
    await close(tester);
  });

  testWidgets(
    'page input dialog submits text before restoring generic target',
    (tester) async {
      clickInput = true;
      await start(tester);
      open('https://first.example/');
      await tester.pumpAndSettle();

      TvInput.instance.send(Cmd.ok);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('old text'), findsOneWidget);
      expect(TvInput.instance.textTarget?.hint, 'Matn yozing');

      TvInput.instance.receiveText('salom dunyo');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final scripts = calls
          .where((c) => c.method == 'runJavaScript')
          .map((c) => (c.arguments as Map)['script'] as String);
      expect(
        scripts.any(
          (script) =>
              script.contains('function(v)') &&
              script.contains(jsonEncode('salom dunyo')),
        ),
        isTrue,
      );
      expect(TvInput.instance.textTarget?.hint, 'Matn yoki qidiruv');
      expect(calls.where((c) => c.method == 'load'), hasLength(1));
      await close(tester);
    },
  );

  testWidgets('stale native bounds cannot show a view above the assistant', (
    tester,
  ) async {
    await start(tester);
    open('https://first.example/');
    await tester.pumpAndSettle();
    blockBounds = true;
    boundsGate = Completer<void>();
    tester.view.physicalSize = const Size(1400, 800);
    await tester.pump();

    Assistant.instance.listen('start', 'salom');
    await tester.pump();
    expect(
      (calls.lastWhere((c) => c.method == 'setVisible').arguments
          as Map)['visible'],
      isFalse,
    );
    boundsGate!.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(Assistant.instance.state.value.visible, isTrue);
    expect(
      (calls.lastWhere((c) => c.method == 'setVisible').arguments
          as Map)['visible'],
      isFalse,
    );
    await close(tester);
  });
}
