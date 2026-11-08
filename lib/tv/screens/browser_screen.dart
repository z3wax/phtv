import '../../uzbek_text.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../assistant/assistant.dart';
import '../../linux_browser.dart';
import '../../native.dart';
import '../external.dart';
import '../input.dart';
import '../services.dart';
import '../sites.dart';
import '../store.dart';
import '../web_nav.dart';
import '../widgets.dart';

const _desktopUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

/// AI brauzer: televizor uchun qulay.
///
/// * Pult: ↑↓←→ — televizordagidek odatiy tanlash (keyingi havola yoki
///   tugma ajratiladi, kerak bo‘lsa sahifa suriladi), OK — bosish,
///   Orqaga — oldingi sahifa, ⏯ — videoni to‘xtatish/davom ettirish,
///   ⏮⏭ — sahifani yuqoriga/pastga. Sichqoncha kursori yo‘q.
/// * ✨ “Qisqacha” — AI sahifani 2–3 gapda tushuntiradi; “Savol” — sahifa
///   haqida so‘rash (pultdagi mikrofon bilan ham).
/// * Linux’da ham WebKit ilovaning o‘z oynasida ishlaydi.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    this.url,
    this.search = false,
    this.tvMode = false,
  });

  /// Bo‘sh — bosh sahifa (qidiruv).
  final String? url;

  /// [url] — qidiruv natijalari (o‘qish rejimida DuckDuckGo ishlatiladi).
  final bool search;

  /// YouTube’ning televizor ko‘rinishi (youtube.com/tv): pult tugmalari
  /// klaviatura tugmalari bo‘lib sahifaga boradi (↑↓←→, Enter, Esc).
  final bool tvMode;

  static bool get webViewSupported =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux);

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  WebViewController? _web;
  LinuxBrowserController? _linux;
  final _surfaceKey = GlobalKey();
  bool _linuxReady = false;
  bool _routeActive = false;
  int _surfaceSeq = 0;
  Animation<double>? _routeAnimation;
  TextTarget? _remoteText;
  String _url = '';
  String _title = '';
  int _progress = 100;

  // Sahifa tepasidagi tugmalar paneli tanlanganmi (veb rejim).
  bool _toolbar = false;
  final _firstTool = FocusNode(debugLabel: 'browser-tools');

  // O‘qish rejimi.
  _Reader? _reader;
  String? _error;
  bool _loading = false;
  final _readerScroll = ScrollController();
  final _readerFirst = FocusNode(debugLabel: 'reader-first');

  bool get _webMode => _web != null || _linux != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    TvInput.instance.push(_onCmd);
    Assistant.instance.state.addListener(_assistantChanged);
    TvStore.instance.settings.addListener(_applyAudioLevel);
    final start = widget.url ?? '';
    if (Platform.isLinux) {
      _url = start.isEmpty ? 'https://www.google.com/' : start;
      _createLinuxView();
    } else if (BrowserScreen.webViewSupported) {
      _web = _createWebView();
      final url = start.isEmpty ? 'https://www.google.com/' : start;
      unawaited(_loadInitialWeb(url));
      _url = url;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (start.isEmpty) {
          _firstTool.requestFocus();
        } else {
          _openReader(start);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_animationChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_animationChanged);
    }
    final active = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeActive != active) {
      _routeActive = active;
      _syncRemoteOwnership();
    }
    _scheduleLinuxSurface();
  }

  @override
  void didChangeMetrics() => _scheduleLinuxSurface();

  void _syncRemoteOwnership() {
    final input = TvInput.instance;
    if (_routeActive) {
      Assistant.instance.pageContext = _pageText;
      TvServices.instance.updateState({
        'title': _title.isEmpty ? null : _title,
        'kind': null,
      });
      if (_webMode &&
          (input.textTarget == null ||
              input.textTarget is _BrowserTextTarget)) {
        _remoteText ??= _BrowserTextTarget(
          hint: 'Matn yoki qidiruv',
          value: '',
          onSubmit: _receiveText,
        );
        input.textTarget = _remoteText;
      }
    } else {
      unawaited(
        _js(
          "document.querySelectorAll('video,audio').forEach(function(v){v.pause();})",
        ),
      );
      if (Assistant.instance.pageContext == _pageText) {
        Assistant.instance.pageContext = null;
      }
      if (input.textTarget == _remoteText) input.textTarget = null;
    }
  }

  void _assistantChanged() => _scheduleLinuxSurface();
  void _animationChanged(AnimationStatus _) => _scheduleLinuxSurface();

  void _scheduleLinuxSurface() {
    if (_linux == null) return;
    _surfaceSeq++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncLinuxSurface();
    });
  }

  Future<void> _syncLinuxSurface() async {
    final linux = _linux;
    if (linux == null || !_linuxReady) return;
    final seq = ++_surfaceSeq;
    final visible =
        _routeActive &&
        _error == null &&
        !Assistant.instance.state.value.visible &&
        (_routeAnimation == null || _routeAnimation!.isCompleted);
    try {
      final box = _surfaceKey.currentContext?.findRenderObject();
      if (visible && box is RenderBox && box.hasSize) {
        final rect = Rect.fromPoints(
          box.localToGlobal(Offset.zero),
          box.localToGlobal(Offset(box.size.width, box.size.height)),
        );
        await linux.setBounds(rect);
      }
      if (!mounted || seq != _surfaceSeq) return;
      await linux.setVisible(visible);
    } catch (_) {
      // The route may have closed while a native layout update was pending.
    }
  }

  @override
  void dispose() {
    _surfaceSeq++;
    WidgetsBinding.instance.removeObserver(this);
    _routeAnimation?.removeStatusListener(_animationChanged);
    Assistant.instance.state.removeListener(_assistantChanged);
    TvStore.instance.settings.removeListener(_applyAudioLevel);
    TvInput.instance.remove(_onCmd);
    if (Assistant.instance.pageContext == _pageText) {
      Assistant.instance.pageContext = null;
    }
    if (TvInput.instance.textTarget == _remoteText) {
      TvInput.instance.textTarget = null;
    }
    // A previous BrowserScreen reclaims these callbacks when it becomes current.
    unawaited(_linux?.dispose());
    _firstTool.dispose();
    _readerFirst.dispose();
    _readerScroll.dispose();
    super.dispose();
  }

  Future<void> _createLinuxView() async {
    final linux = LinuxBrowserController(
      userAgent: widget.tvMode ? tvUserAgent : _desktopUa,
      // YouTube TV: H.264 va 1080p gacha — hujjat boshida, sahifadan oldin.
      userScript: widget.tvMode ? youtubeVideoLimitScript : null,
    );
    _linux = linux;
    linux
      ..onProgress = (p) {
        if (mounted) setState(() => _progress = p);
      }
      ..onUrlChange = (url) {
        if (mounted) setState(() => _url = url);
      }
      ..onPageStarted = (_) {
        if (mounted) setState(() => _error = null);
        _applyAudioLevel();
      }
      ..onPageFinished = (url) {
        if (!mounted) return;
        setState(() {
          _url = url;
          _progress = 100;
        });
        _scheduleLinuxSurface();
        _applyAudioLevel();
      }
      ..onTitleChange = (title) {
        if (!mounted) return;
        setState(() => _title = title);
        if (_routeActive) TvServices.instance.updateState({'title': title});
      }
      ..onError = (message) {
        if (mounted) {
          setState(() {
            _error = message;
            _progress = 100;
          });
          _scheduleLinuxSurface();
        }
      }
      ..onKey = (key) {
        if (!_routeActive) return;
        if (key == 'address') {
          _editAddress();
          return;
        }
        final cmd = switch (key) {
          'escape' => Cmd.back,
          'home' => Cmd.home,
          _ => null,
        };
        if (cmd != null) TvInput.instance.send(cmd);
      };
    try {
      await linux.ready;
      await TvStore.instance.load();
      if (!mounted) return;
      await linux.loadRequest(Uri.parse(_url));
      if (!mounted) return;
      _linuxReady = true;
      _syncRemoteOwnership();
      _scheduleLinuxSurface();
    } catch (_) {
      await linux.dispose();
      if (!mounted) return;
      setState(() {
        _linux = null;
        _error = 'Ichki brauzerni ishga tushirib bo‘lmadi';
        _progress = 100;
      });
      _syncRemoteOwnership();
    }
  }

  Future<void> _loadInitialWeb(String url) async {
    try {
      await TvStore.instance.load();
      if (mounted) await _web?.loadRequest(Uri.parse(url));
    } catch (_) {
      if (mounted) setState(() => _error = 'Sahifani ochib bo‘lmadi');
    }
  }

  Future<Object> _runJsResult(String script) async {
    if (_linux case final linux?) {
      return linux.runJavaScriptReturningResult(script);
    }
    return await _web?.runJavaScriptReturningResult(script) ?? '';
  }

  Future<void> _reload() async {
    try {
      if (_linux case final linux?) {
        await linux.reload();
      } else {
        await _web?.reload();
      }
    } catch (_) {}
  }

  WebViewController _createWebView() {
    PlatformWebViewControllerCreationParams params =
        const PlatformWebViewControllerCreationParams();
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    }
    final c = WebViewController.fromPlatformCreationParams(
      params,
      onPermissionRequest: (r) => r.grant(),
    );
    try {
      c.setBackgroundColor(Colors.black); // Mac’da qo‘llanmaydi
    } catch (_) {}
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.tvMode ? tvUserAgent : _desktopUa)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _limitVideo();
            _applyAudioLevel();
          },
          onProgress: (p) {
            _limitVideo();
            if (mounted) setState(() => _progress = p);
          },
          onUrlChange: (change) {
            if (mounted && change.url != null) {
              setState(() => _url = change.url!);
            }
          },
          onPageFinished: (url) async {
            final t = await c.getTitle();
            if (!mounted) return;
            setState(() {
              _url = url;
              _title = t ?? '';
              _progress = 100;
            });
            if (_routeActive) {
              TvServices.instance.updateState({
                'title': _title.isEmpty ? null : _title,
              });
            }
            _limitVideo();
            _applyAudioLevel();
          },
        ),
      );
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    return c;
  }

  /// YouTube TV: video faqat H.264 va 1080p gacha (4K AV1/VP9 qora ekran va
  /// qotishga olib keladi). Bu yerda hujjat boshida qo‘shib bo‘lmaydi —
  /// sahifa yuklanayotganda bir necha marta (skript bir martagina ishlaydi).
  /// Linux’da [LinuxBrowserController.new] `userScript` orqali qo‘shiladi.
  void _limitVideo() {
    if (!widget.tvMode || _linux != null) return;
    unawaited(_js(youtubeVideoLimitScript));
  }

  void _applyAudioLevel() {
    final s = TvStore.instance.settings.value;
    unawaited(
      _js('''
(()=>{
  window.__telefonTvAudio={volume:${s.volume},muted:${s.muted}};
  const apply=v=>{if(v && (v.tagName==='VIDEO'||v.tagName==='AUDIO')){
    if(v.volume!==window.__telefonTvAudio.volume) v.volume=window.__telefonTvAudio.volume;
    if(v.muted!==window.__telefonTvAudio.muted) v.muted=window.__telefonTvAudio.muted;
  }};
  document.querySelectorAll('video,audio').forEach(apply);
  if(!window.__telefonTvAudioBound){
    window.__telefonTvAudioBound=true;
    document.addEventListener('play',e=>apply(e.target),true);
    document.addEventListener('volumechange',e=>apply(e.target),true);
    new MutationObserver(records=>records.forEach(r=>r.addedNodes.forEach(n=>{
      apply(n);if(n.querySelectorAll)n.querySelectorAll('video,audio').forEach(apply);
    }))).observe(document,{childList:true,subtree:true});
  }
})()
'''),
    );
  }

  /* ------------------ AI uchun sahifa matni ------------------ */

  Future<String?> _pageText() async {
    if (_webMode) {
      try {
        final r = await _runJsResult(
          "(document.body ? document.body.innerText : '').slice(0, 6000)",
        );
        var text = '$r';
        if (text.startsWith('"')) text = jsonDecode(text) as String;
        return '${_title.isEmpty ? '' : '$_title\n'}$_url\n$text';
      } catch (_) {
        return '$_title\n$_url';
      }
    }
    final r = _reader;
    if (r == null) return null;
    final text = r.blocks
        .where((b) => b.kind != _Kind.link)
        .map((b) => b.text)
        .join('\n');
    return '${r.title}\n${r.url}\n${text.length > 6000 ? text.substring(0, 6000) : text}';
  }

  void _summarize() =>
      Assistant.instance.ask('Shu sahifani 2–3 gapda qisqacha tushuntirib ber');

  bool _restoreForSubmit() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _routeActive = true;
    _syncRemoteOwnership();
    return true;
  }

  Future<void> _askAboutPage() async {
    await TvServices.instance.editText(
      context,
      title: 'Sahifa haqida savol (yoki pultdagi 🎤)',
      value: '',
      onSubmit: (v) {
        if (!_restoreForSubmit()) return;
        if (v.trim().isNotEmpty) Assistant.instance.ask(v);
      },
    );
    if (mounted) _syncRemoteOwnership();
  }

  Future<void> _editAddress() async {
    await TvServices.instance.editText(
      context,
      title: 'Manzil yoki qidiruv',
      value: _webMode ? _url : (_reader?.url ?? ''),
      onSubmit: (v) {
        if (!_restoreForSubmit()) return;
        final t = v.trim();
        if (t.isEmpty) return;
        final url = normalizeUrl(t);
        _go(url ?? searchUrl(t), search: url == null);
        _syncRemoteOwnership();
      },
    );
    if (mounted) _syncRemoteOwnership();
  }

  void _go(String url, {bool search = false}) {
    if (_webMode) {
      final load =
          _linux?.loadRequest(Uri.parse(url)) ??
          _web!.loadRequest(Uri.parse(url));
      unawaited(
        load.catchError((Object _) {
          if (mounted) setState(() => _error = 'Sahifani ochib bo‘lmadi');
        }),
      );
      setState(() {
        _url = url;
        _toolbar = false;
      });
      return;
    }
    _openReader(url, search: search);
  }

  void _bookmark() {
    final url = _webMode ? _url : _reader?.url;
    if (url == null || url.isEmpty) return;
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
    final name = _title.isNotEmpty && _title.length <= 18 ? _title : host;
    TvStore.instance.addSite(name, url);
    TvServices.instance.showToast('“$name” bosh ekranga qo‘shildi');
  }

  /* ------------------ Pult: odatiy tanlash ------------------ */

  Future<void> _js(String code) async {
    try {
      if (_linux case final linux?) {
        await linux.runJavaScript(code);
      } else {
        await _web?.runJavaScript(code);
      }
    } catch (_) {}
  }

  Future<String> _jsText(String code) async {
    var res = '${await _runJsResult(code)}';
    if (res.startsWith('"')) res = jsonDecode(res) as String;
    return res;
  }

  /// ↑↓←→: sahifadagi keyingi havola / tugma ajratiladi (kursor yo‘q).
  /// Sahifa eng tepada bo‘lsa — yuqoridagi tugmalar paneliga o‘tamiz.
  Future<void> _nav(String dir) async {
    final String res;
    try {
      res = await _jsText(webNavMove(dir));
    } catch (_) {
      return;
    }
    if (res == 'top' && mounted && _routeActive) {
      setState(() => _toolbar = true);
      _firstTool.requestFocus();
    }
  }

  /// OK: ajratilgan havola / tugmani bosish, matn maydoni — pultda yozish.
  Future<void> _activate() async {
    final linux = _linux;
    final String res;
    try {
      res = await _jsText(webNavOk(native: linux != null));
    } catch (_) {
      return;
    }
    if (res.startsWith('click:') && linux != null) {
      final at = res.substring(6).split(',');
      final fx = double.tryParse(at.first), fy = double.tryParse(at.last);
      if (at.length != 2 || fx == null || fy == null) return;
      try {
        await linux.click(fx, fy);
      } catch (_) {}
      return;
    }
    if (!res.startsWith('input:') || !mounted) return;
    await TvServices.instance.editText(
      context,
      title: _latinYoutube ? 'YouTube qidiruvi (lotincha)' : 'Matn yozing',
      latin: _latinYoutube,
      value: res.substring(6),
      onSubmit: (value) {
        if (!_restoreForSubmit()) return;
        unawaited(_receiveText(value));
      },
    );
    if (mounted) _syncRemoteOwnership();
  }

  /// YouTube TV: tugma sahifaga haqiqiy klaviatura tugmasi bo‘lib boradi
  /// (Linux, Mac); boshqa joyda — JavaScript orqali.
  Future<void> _sendTvKey(String key) async {
    if (_linux case final linux?) {
      try {
        await linux.sendKey(key);
      } catch (_) {}
      return;
    }
    if (Platform.isMacOS && await NativeBridge.sendKey(key)) return;
    final script = webKeyScript(key);
    if (script.isNotEmpty) await _js(script);
  }

  bool get _latinYoutube {
    final host = Uri.tryParse(_url)?.host.toLowerCase() ?? '';
    return TvStore.instance.assistant.value.latinSearch &&
        (host == 'youtube.com' || host.endsWith('.youtube.com'));
  }

  Future<void> _receiveText(String value) async {
    if (_latinYoutube) value = uzbekToLatin(value);
    if (!_webMode || !_restoreForSubmit()) return;
    if (widget.tvMode) {
      // YouTube TV’ning o‘z klaviaturasi bor: pultdan yozilgani — qidiruv.
      final text = value.trim();
      if (text.isNotEmpty) _go(youtubeTvSearchUrl(text));
      return;
    }
    try {
      final handled = await _runJsResult('''
(function(v){
  var t = document.activeElement;
  if (!t || !t.matches('input,textarea,[contenteditable="true"]')) return false;
  var proto = t.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  var d = Object.getOwnPropertyDescriptor(proto, 'value');
  if (t.isContentEditable) t.innerText = v;
  else if (d && d.set) d.set.call(t, v);
  else t.value = v;
  t.dispatchEvent(new Event('input', {bubbles:true}));
  t.dispatchEvent(new Event('change', {bubbles:true}));
  ['keydown','keypress','keyup'].forEach(function(n){
    t.dispatchEvent(new KeyboardEvent(n, {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true}));
  });
  if (t.form) { if (t.form.requestSubmit) t.form.requestSubmit(); else t.form.submit(); }
  return true;
})(${jsonEncode(value)})''');
      if (handled != true && handled != 'true' && mounted) {
        final text = value.trim();
        if (text.isNotEmpty) _go(normalizeUrl(text) ?? searchUrl(text));
      }
    } catch (_) {
      TvServices.instance.showToast('Matnni sahifaga yuborib bo‘lmadi');
    }
  }

  bool _onCmd(Cmd cmd) {
    if (!mounted || !(ModalRoute.isCurrentOf(context) ?? false)) return false;
    if (cmd == Cmd.back) {
      if (widget.tvMode) {
        _tvBack();
      } else {
        _back();
      }
      return true;
    }
    if (!_webMode) return _readerCmd(cmd);
    if (widget.tvMode) {
      final key = switch (cmd) {
        Cmd.up => 'up',
        Cmd.down => 'down',
        Cmd.left => 'left',
        Cmd.right => 'right',
        Cmd.ok || Cmd.playPause => 'enter',
        _ => null,
      };
      if (key == null) return false;
      unawaited(_sendTvKey(key));
      return true;
    }
    if (_toolbar) {
      if (cmd == Cmd.down) {
        setState(() => _toolbar = false);
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      }
      return false; // tugmalar orasida oddiy yurish
    }
    switch (cmd) {
      case Cmd.up:
        unawaited(_nav('up'));
      case Cmd.down:
        unawaited(_nav('down'));
      case Cmd.left:
        unawaited(_nav('left'));
      case Cmd.right:
        unawaited(_nav('right'));
      case Cmd.ok:
        unawaited(_activate());
      case Cmd.playPause:
        _js(
          "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}",
        );
      case Cmd.next:
        _js('window.scrollBy(0, window.innerHeight * 0.85)');
      case Cmd.prev:
        _js('window.scrollBy(0, -window.innerHeight * 0.85)');
      default:
        return false; // ovoz, Home — umumiy
    }
    return true;
  }

  DateTime _lastBack = DateTime(0);

  /// YouTube TV: Orqaga — sahifaning o‘zida (Esc); tez ikki marta — chiqish.
  void _tvBack() {
    final now = DateTime.now();
    if (now.difference(_lastBack).inMilliseconds < 700) {
      Navigator.of(context).maybePop();
      return;
    }
    _lastBack = now;
    unawaited(_sendTvKey('escape'));
  }

  Future<void> _back() async {
    final linux = _linux;
    if (linux != null && await linux.canGoBack()) {
      await linux.goBack();
      return;
    }
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
      return;
    }
    final r = _reader;
    if (r != null && r.previous != null) {
      setState(() => _reader = r.previous);
      return;
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  bool _readerCmd(Cmd cmd) {
    if ((cmd == Cmd.next || cmd == Cmd.prev) && !_readerScroll.hasClients) {
      return true;
    }
    switch (cmd) {
      case Cmd.next:
        _readerScroll.animateTo(
          (_readerScroll.offset + 500).clamp(
            0,
            _readerScroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return true;
      case Cmd.prev:
        _readerScroll.animateTo(
          (_readerScroll.offset - 500).clamp(
            0,
            _readerScroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return true;
      default:
        return false;
    }
  }

  /* ------------------ O‘qish rejimi ------------------ */

  Future<void> _openReader(String url, {bool search = false}) async {
    var target = url;
    if (search || widget.search && _reader == null) {
      final q =
          Uri.tryParse(url)?.queryParameters['q'] ??
          Uri.tryParse(url)?.queryParameters['search_query'];
      if (q != null) {
        target =
            'https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(q)}';
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _Reader.load(target);
      if (!mounted) return;
      page.previous = _reader;
      setState(() {
        _reader = page;
        _title = page.title;
        _loading = false;
      });
      TvServices.instance.updateState({'title': page.title});
      if (_readerScroll.hasClients) _readerScroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _readerFirst.requestFocus();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sahifani ochib bo‘lmadi. Internetni tekshiring.';
      });
    }
  }

  /* ------------------ Ko‘rinish ------------------ */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          if (!widget.tvMode) _toolbarRow(),
          if (_progress < 100 || _loading)
            LinearProgressIndicator(
              value: _loading ? null : _progress / 100,
              minHeight: 3,
              color: const Color(0xFF5AC8FA),
              backgroundColor: Colors.transparent,
            )
          else
            const SizedBox(height: 3),
          Expanded(child: _webMode ? _webBody() : _readerBody()),
        ],
      ),
    );
  }

  Widget _toolbarRow() {
    Widget tool(
      IconData icon,
      String label,
      VoidCallback onTap, {
      FocusNode? focus,
    }) => Padding(
      padding: const EdgeInsets.only(right: 10),
      child: TvFocusable(
        focusNode: focus,
        onTap: onTap,
        radius: 14,
        scale: 1.05,
        builder: (context, f) => Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          color: f ? Colors.white : Colors.white.withValues(alpha: 0.1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: f ? Colors.black : Colors.white),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: f ? Colors.black : Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final shownUrl = _webMode ? _url : (_reader?.url ?? '');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      color: const Color(0xFF0B0B0D),
      child: Row(
        children: [
          tool(Icons.arrow_back_rounded, '', _back, focus: _firstTool),
          if (_webMode) tool(Icons.refresh_rounded, '', _reload),
          tool(Icons.home_rounded, '', () => TvInput.instance.send(Cmd.home)),
          Expanded(
            child: TvFocusable(
              onTap: _editAddress,
              radius: 14,
              scale: 1.02,
              builder: (context, f) => Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: f ? Colors.white : Colors.white.withValues(alpha: 0.07),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: f ? Colors.black54 : Colors.white54,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        shownUrl.isEmpty
                            ? 'Qidiruv yoki manzil'
                            : _pretty(shownUrl),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          color: f ? Colors.black : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          tool(Icons.auto_awesome_rounded, 'Qisqacha', _summarize),
          tool(Icons.question_answer_rounded, 'Savol', _askAboutPage),
          tool(Icons.bookmark_add_rounded, '', _bookmark),
        ],
      ),
    );
  }

  static String _pretty(String url) => url
      .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
      .replaceFirst(RegExp(r'/$'), '');

  Widget _webBody() {
    if (_error != null) return _readerBody();
    return LayoutBuilder(
      builder: (context, box) {
        _scheduleLinuxSurface();
        final web = _web;
        return SizedBox.expand(
          key: _surfaceKey,
          child: web != null
              ? WebViewWidget(controller: web)
              : const ColoredBox(color: Colors.black),
        );
      },
    );
  }

  Widget _readerBody() {
    final r = _reader;
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, color: Colors.white70),
        ),
      );
    }
    if (r == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.travel_explore_rounded,
              size: 80,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              _loading
                  ? 'Ochilmoqda…'
                  : 'Manzil yoki qidiruvni yozing — yoki pultdagi 🎤 bilan so‘rang',
              style: const TextStyle(fontSize: 22, color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _readerScroll,
      padding: const EdgeInsets.fromLTRB(140, 24, 140, 60),
      itemCount: r.blocks.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              r.title,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
            ),
          );
        }
        final b = r.blocks[i - 1];
        final link = b.kind == _Kind.link;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TvFocusable(
            focusNode: i == 1 ? _readerFirst : null,
            onTap: link ? () => _openReader(b.href!) : null,
            radius: 12,
            scale: 1.01,
            builder: (context, f) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: f
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              child: Text(
                link ? '↗ ${b.text}' : b.text,
                style: TextStyle(
                  fontSize: b.kind == _Kind.heading ? 26 : 21,
                  height: 1.45,
                  fontWeight: b.kind == _Kind.heading
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: link
                      ? const Color(0xFF7DD3FC)
                      : Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Generic browser input can be restored without replacing a pending dialog.
class _BrowserTextTarget extends TextTarget {
  const _BrowserTextTarget({
    required super.hint,
    required super.value,
    required super.onSubmit,
  });
}

enum _Kind { heading, text, link }

class _Block {
  const _Block(this.kind, this.text, [this.href]);
  final _Kind kind;
  final String text;
  final String? href;
}

/// Sahifaning o‘qiladigan ko‘rinishi: sarlavhalar, matn, havolalar.
class _Reader {
  _Reader(this.url, this.title, this.blocks);
  final String url;
  final String title;
  final List<_Block> blocks;
  _Reader? previous;

  static Future<_Reader> load(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = _desktopUa;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'uz,ru;q=0.8,en;q=0.6');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      final body = utf8.decode(bytes, allowMalformed: true);
      final finalUrl = res.redirects.isEmpty
          ? url
          : res.redirects.last.location.toString();
      return parse(Uri.parse(url).resolve(finalUrl).toString(), body);
    } finally {
      client.close(force: true);
    }
  }

  @visibleForTesting
  static _Reader parse(String url, String body) {
    final doc = html.parse(body);
    for (final tag in [
      'script',
      'style',
      'noscript',
      'svg',
      'nav',
      'footer',
      'header',
      'form',
      'iframe',
    ]) {
      for (final e in doc.querySelectorAll(tag)) {
        e.remove();
      }
    }
    final base = Uri.parse(url);
    final blocks = <_Block>[];
    final seen = <String>{};
    var links = 0;
    String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

    String? resolve(String href) {
      if (href.startsWith('javascript:') || href.startsWith('#')) return null;
      var u = base.resolve(href);
      // DuckDuckGo natijalari: //duckduckgo.com/l/?uddg=<asl manzil>
      final real = u.queryParameters['uddg'];
      if (real != null) u = Uri.parse(real);
      if (u.scheme != 'http' && u.scheme != 'https') return null;
      return u.toString();
    }

    void walk(dom.Element e) {
      final tag = e.localName;
      if (tag == 'h1' || tag == 'h2' || tag == 'h3') {
        final t = clean(e.text);
        if (t.length > 1 && seen.add(t)) blocks.add(_Block(_Kind.heading, t));
        return;
      }
      if (tag == 'p' || tag == 'li' || tag == 'blockquote' || tag == 'td') {
        final a = e.querySelector('a[href]');
        final t = clean(e.text);
        if (a != null &&
            clean(a.text).length >= t.length * 0.8 &&
            links < 120) {
          final href = resolve(a.attributes['href'] ?? '');
          if (href != null && t.length >= 3 && seen.add(href)) {
            blocks.add(_Block(_Kind.link, t, href));
            links++;
          }
          return;
        }
        if (t.length >= 20 && seen.add(t)) blocks.add(_Block(_Kind.text, t));
        return;
      }
      if (tag == 'a') {
        final t = clean(e.text);
        final href = resolve(e.attributes['href'] ?? '');
        if (href != null && t.length >= 4 && links < 120 && seen.add(href)) {
          blocks.add(_Block(_Kind.link, t, href));
          links++;
        }
        return;
      }
      for (final c in e.children) {
        walk(c);
      }
    }

    final root = doc.body;
    if (root != null) walk(root);
    final title = clean(doc.querySelector('title')?.text ?? '');
    return _Reader(
      url,
      title.isEmpty ? base.host : title,
      blocks.isEmpty
          ? const [_Block(_Kind.text, 'Sahifada o‘qiladigan matn topilmadi.')]
          : blocks,
    );
  }
}

/// Testlar uchun: o‘qish rejimidagi bloklar (matn) ro‘yxati.
@visibleForTesting
List<String> readerTextsForTest(String url, String body) =>
    _Reader.parse(url, body).blocks
        .map((b) => b.href == null ? b.text : '${b.text} -> ${b.href}')
        .toList();
