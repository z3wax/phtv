import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:path_provider/path_provider.dart';

import '../native.dart';

import 'input.dart';
import 'screens/home_screen.dart';
import 'server.dart';
import 'services.dart';
import 'store.dart';
import 'weather.dart';

/// Televizor ekranidagi Smart TV.
///
/// [onTvDisplay] — true: televizorda alohida oyna (telefon ekrani — pult).
/// false: televizor telefon ekranini takrorlaydi yoki TV hali ulanmagan.
class TvApp extends StatefulWidget {
  const TvApp({
    super.key,
    required this.onTvDisplay,
    this.useAsRemote,
    this.openUsb,
    this.services = true,
  });

  final bool onTvDisplay;
  final VoidCallback? useAsRemote;
  final VoidCallback? openUsb;

  /// Pult serveri va ob-havo (testlarda o‘chiriladi).
  final bool services;

  @override
  State<TvApp> createState() => _TvAppState();
}

class _TvAppState extends State<TvApp> {
  RemoteServer? _server;
  StreamSubscription<void>? _home;

  @override
  void initState() {
    super.initState();
    final s = TvServices.instance
      ..onTvDisplay = widget.onTvDisplay
      ..useAsRemote = widget.useAsRemote
      ..openUsb = widget.openUsb;
    TvStore.instance.load();
    if (widget.services) {
      final server = RemoteServer(
        keyProvider: () => TvStore.instance.remoteKey,
        onCommand: TvInput.instance.send,
        onText: TvInput.instance.receiveText,
        onMedia: s.receiveMedia,
        uploadDir: uploadDirectory,
        onUpload: s.receiveUpload,
      );
      server.clients.addListener(() => s.remotes.value = server.clients.value);
      server.start();
      s.server = _server = server;
      WeatherService.instance.start();
    }
    // TV qutisida bosh ekran bo‘lganda Home tugmasi — bosh sahifa.
    if (!widget.onTvDisplay) {
      _home = NativeBridge.homePressed.listen(
        (_) => TvInput.instance.send(Cmd.home),
      );
    }
  }

  @override
  void dispose() {
    _home?.cancel();
    _server?.stop();
    final s = TvServices.instance;
    if (s.server == _server) s.server = null;
    s.remotes.value = 0;
    s.dispose();
    if (widget.services) WeatherService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telefon TV',
      debugShowCheckedModeBanner: false,
      navigatorKey: TvInput.instance.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B6CFF),
          surface: Color(0xFF15161C),
        ),
        scaffoldBackgroundColor: Colors.black,
        splashFactory: NoSplash.splashFactory,
      ),
      builder: (context, child) => TvCanvas(child: child ?? const SizedBox()),
      home: const HomeScreen(),
    );
  }
}

/// Hamma televizorda bir xil ko‘rinish: interfeys 720 nuqta balandlikda
/// chiziladi va ekranga moslab kattalashtiriladi (720p, 1080p, 4K, telefon).
class TvCanvas extends StatelessWidget {
  const TvCanvas({super.key, required this.child});
  final Widget child;

  static const designHeight = 720.0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: ValueListenableBuilder<TvSettings>(
        valueListenable: TvStore.instance.settings,
        builder: (context, settings, _) => LayoutBuilder(
          builder: (context, box) {
            final o = settings.overscan / 100;
            final w = box.maxWidth * (1 - 2 * o),
                h = box.maxHeight * (1 - 2 * o);
            if (w <= 0 || h <= 0) return const SizedBox();
            final scale = h / designHeight;
            final size = Size(w / scale, designHeight);
            final mq = MediaQuery.of(context);
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topLeft,
                  child: SizedBox.fromSize(
                    size: size,
                    child: MediaQuery(
                      data: mq.copyWith(
                        size: size,
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                        viewInsets: mq.viewInsets / scale,
                        devicePixelRatio: mq.devicePixelRatio * scale,
                        textScaler: TextScaler.noScaling,
                      ),
                      child: Focus(
                        skipTraversal: true,
                        onKeyEvent: (_, e) => TvInput.instance.handleKey(e),
                        child: Stack(
                          children: [
                            Positioned.fill(child: child),
                            const _Toast(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: TvServices.instance.toast,
      builder: (context, text, _) => Positioned(
        left: 0,
        right: 0,
        bottom: 40,
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: text == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xEE1E2130),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 24),
                  ],
                ),
                child: Text(
                  text ?? '',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Telefondan yuborilgan fayllar papkasi: Ubuntu’da “Videolar/Telefon TV”,
/// Mac’da “Filmlar/Telefon TV” (~/Movies), telefonda ilovaning o‘z papkasi.
Future<Directory> uploadDirectory() async {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return Directory('$home/Movies/Telefon TV');
  }
  if (Platform.isLinux) {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    var videos = '$home/Videos';
    try {
      // XDG_VIDEOS_DIR="$HOME/Videolar" (tizim tili o‘zbekcha bo‘lsa va h.k.)
      final dirs = File('$home/.config/user-dirs.dirs').readAsStringSync();
      final m = RegExp(
        r'^XDG_VIDEOS_DIR="(.+)"$',
        multiLine: true,
      ).firstMatch(dirs);
      if (m != null) videos = m.group(1)!.replaceAll(r'$HOME', home);
    } catch (_) {}
    return Directory('$videos/Telefon TV');
  }
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/Telefon TV');
}
