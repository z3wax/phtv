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
import '../../native.dart';
import '../external.dart';
import '../input.dart';
import '../services.dart';
import '../sites.dart';
import '../store.dart';
import '../widgets.dart';

const _desktopUa =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

/// AI brauzer: televizor uchun qulay.
///
/// * Pult: ↑↓←→ — kursor (chetida sahifa suriladi), OK — bosish,
///   Orqaga — oldingi sahifa, ⏯ — videoni to‘xtatish/davom ettirish,
///   ⏮⏭ — sahifani yuqoriga/pastga. Telefondagi panel — sichqoncha.
/// * ✨ “Qisqacha” — AI sahifani 2–3 gapda tushuntiradi; “Savol” — sahifa
///   haqida so‘rash (pultdagi mikrofon bilan ham).
/// * Ubuntu’da (ichki brauzer yo‘q) — o‘qish rejimi: matn va havolalar
///   pult bilan yuriladi, videoli saytlar Chrome’da ochiladi.
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

  /// YouTube’ning televizor ko‘rinishi: kursorsiz, pult tugmalari
  /// klaviatura tugmalari bo‘lib sahifaga boradi (↑↓←→, Enter, Esc).
  final bool tvMode;

  static bool get webViewSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  WebViewController? _web;
  String _url = '';
  String _title = '';
  int _progress = 100;

  // Kursor (veb rejim).
  Offset _cursor = const Offset(400, 260);
  Size _area = Size.zero;
  bool _toolbar = false;
  DateTime _lastMove = DateTime(0);
  double _speed = 22;
  final _firstTool = FocusNode(debugLabel: 'browser-tools');

  // O‘qish rejimi.
  _Reader? _reader;
  String? _error;
  bool _loading = false;
  final _readerScroll = ScrollController();
  final _readerFirst = FocusNode(debugLabel: 'reader-first');

  bool get _webMode => _web != null;

  @override
  void initState() {
    super.initState();
    TvInput.instance.push(_onCmd);
    Assistant.instance.pageContext = _pageText;
    final start = widget.url ?? '';
    if (BrowserScreen.webViewSupported) {
      _web = _createWebView();
      if (!widget.tvMode) {
        TvServices.instance.setPointerMode(true);
        TvInput.instance.onPointer = _onPointer;
      }
      final url = start.isEmpty ? 'https://www.google.com/' : start;
      _web!.loadRequest(Uri.parse(url));
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
  void dispose() {
    TvInput.instance.remove(_onCmd);
    if (TvInput.instance.onPointer == _onPointer) {
      TvInput.instance.onPointer = null;
    }
    if (Assistant.instance.pageContext == _pageText) {
      Assistant.instance.pageContext = null;
    }
    if (_webMode) TvServices.instance.setPointerMode(false);
    _firstTool.dispose();
    _readerFirst.dispose();
    _readerScroll.dispose();
    super.dispose();
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
          onProgress: (p) {
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
            TvServices.instance.updateState({
              'title': _title.isEmpty ? null : _title,
            });
          },
        ),
      );
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    return c;
  }

  /* ------------------ AI uchun sahifa matni ------------------ */

  Future<String?> _pageText() async {
    final web = _web;
    if (web != null) {
      try {
        final r = await web.runJavaScriptReturningResult(
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

  void _askAboutPage() => TvServices.instance.editText(
    context,
    title: 'Sahifa haqida savol (yoki pultdagi 🎤)',
    value: '',
    onSubmit: (v) {
      if (v.trim().isNotEmpty) Assistant.instance.ask(v);
    },
  );

  void _editAddress() => TvServices.instance.editText(
    context,
    title: 'Manzil yoki qidiruv',
    value: _webMode ? _url : (_reader?.url ?? ''),
    onSubmit: (v) {
      final t = v.trim();
      if (t.isEmpty) return;
      final url = normalizeUrl(t);
      _go(url ?? searchUrl(t), search: url == null);
    },
  );

  void _go(String url, {bool search = false}) {
    final web = _web;
    if (web != null) {
      web.loadRequest(Uri.parse(url));
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

  /* ------------------ Pult: kursor ------------------ */

  void _onPointer(double dx, double dy) {
    if (!mounted || !_webMode) return;
    setState(() {
      _toolbar = false;
      _cursor = _clamp(_cursor + Offset(dx * 1.4, dy * 1.4));
    });
  }

  Offset _clamp(Offset o) => Offset(
    o.dx.clamp(0, _area.width > 0 ? _area.width - 4 : 2000),
    o.dy.clamp(0, _area.height > 0 ? _area.height - 4 : 2000),
  );

  Future<void> _js(String code) async {
    try {
      await _web?.runJavaScript(code);
    } catch (_) {}
  }

  void _move(Offset dir) {
    final now = DateTime.now();
    _speed = now.difference(_lastMove).inMilliseconds < 260
        ? (_speed * 1.25).clamp(22, 70)
        : 22;
    _lastMove = now;
    final next = _cursor + dir * _speed;
    // Chetga yetganda — sahifani suramiz.
    if (next.dy < 0) {
      _js('window.scrollBy(0, -${(_area.height * 0.6).round()})');
      _checkTop();
    } else if (next.dy > _area.height - 4) {
      _js('window.scrollBy(0, ${(_area.height * 0.6).round()})');
    } else if (next.dx < 0) {
      _js('window.scrollBy(-300, 0)');
    } else if (next.dx > _area.width - 4) {
      _js('window.scrollBy(300, 0)');
    }
    setState(() => _cursor = _clamp(next));
  }

  /// Sahifa eng tepada bo‘lsa — yuqoridagi tugmalar paneliga o‘tamiz.
  Future<void> _checkTop() async {
    try {
      final r = await _web?.runJavaScriptReturningResult('window.scrollY');
      if (!mounted) return;
      if ((num.tryParse('$r') ?? 1) <= 0) {
        setState(() => _toolbar = true);
        _firstTool.requestFocus();
      }
    } catch (_) {}
  }

  Future<void> _click() async {
    final web = _web;
    if (web == null || _area.isEmpty) return;
    final fx = _cursor.dx / _area.width, fy = _cursor.dy / _area.height;
    Object? r;
    try {
      r = await web.runJavaScriptReturningResult('''
(function(fx, fy){
  var x = fx * window.innerWidth, y = fy * window.innerHeight;
  var e = document.elementFromPoint(x, y);
  if (!e) return '';
  var t = e.closest('input,textarea,[contenteditable="true"]');
  var skip = {submit:1, button:1, checkbox:1, radio:1, range:1, file:1, image:1, reset:1};
  if (t && !skip[t.type]) { t.focus(); return 'input:' + (t.value || ''); }
  ['pointerdown','mousedown','pointerup','mouseup'].forEach(function(n){
    e.dispatchEvent(new MouseEvent(n, {bubbles:true, cancelable:true, clientX:x, clientY:y, view:window}));
  });
  e.click();
  return 'click';
})($fx, $fy)''');
    } catch (_) {
      return;
    }
    var res = '$r';
    if (res.startsWith('"')) res = jsonDecode(res) as String;
    if (!res.startsWith('input:') || !mounted) return;
    await TvServices.instance.editText(
      context,
      title: 'Matn yozing',
      value: res.substring(6),
      onSubmit: (v) => _js('''
(function(v){
  var t = document.activeElement; if (!t) return;
  var proto = t.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  var d = Object.getOwnPropertyDescriptor(proto, 'value');
  if (d && d.set && t.tagName !== 'DIV') d.set.call(t, v); else t.innerText = v;
  t.dispatchEvent(new Event('input', {bubbles:true}));
  t.dispatchEvent(new Event('change', {bubbles:true}));
  ['keydown','keypress','keyup'].forEach(function(n){
    t.dispatchEvent(new KeyboardEvent(n, {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true}));
  });
  if (t.form) { if (t.form.requestSubmit) t.form.requestSubmit(); else t.form.submit(); }
})(${jsonEncode(v)})'''),
    );
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
      NativeBridge.sendKey(key);
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
        _move(const Offset(0, -1));
      case Cmd.down:
        _move(const Offset(0, 1));
      case Cmd.left:
        _move(const Offset(-1, 0));
      case Cmd.right:
        _move(const Offset(1, 0));
      case Cmd.ok:
        _click();
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
    NativeBridge.sendKey('escape');
  }

  Future<void> _back() async {
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

  /* ------------------ O‘qish rejimi (Ubuntu) ------------------ */

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
        _error =
            'Sahifani ochib bo‘lmadi. Internetni tekshiring yoki to‘liq brauzerda oching.';
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
          if (_webMode) tool(Icons.refresh_rounded, '', () => _web?.reload()),
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
          if (!_webMode)
            tool(Icons.open_in_new_rounded, '', () {
              final u = _reader?.url;
              if (u != null) TvServices.instance.openApp(u, 'Brauzer');
            }),
        ],
      ),
    );
  }

  static String _pretty(String url) => url
      .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
      .replaceFirst(RegExp(r'/$'), '');

  Widget _webBody() {
    return LayoutBuilder(
      builder: (context, box) {
        _area = Size(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _web!)),
            if (!_toolbar && !widget.tvMode)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 70),
                left: _cursor.dx - 4,
                top: _cursor.dy - 2,
                child: const IgnorePointer(child: _Cursor()),
              ),
          ],
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

class _Cursor extends StatelessWidget {
  const _Cursor();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.85),
        border: Border.all(color: Colors.black54, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
    );
  }
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
