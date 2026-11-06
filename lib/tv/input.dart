import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pultning har bir tugmasi. Telefon pulti, brauzer pulti, Bluetooth pult,
/// klaviatura va o‘yin pulti — hammasi shu buyruqlarga aylanadi.
enum Cmd {
  up,
  down,
  left,
  right,
  ok,
  back,
  home,
  playPause,
  next,
  prev,
  volUp,
  volDown,
  mute,
}

typedef CmdHandler = bool Function(Cmd cmd);

/// Televizordagi matn maydoni: pultdan yozilgan matn shu yerga tushadi.
class TextTarget {
  const TextTarget({
    required this.hint,
    required this.value,
    required this.onSubmit,
  });
  final String hint;
  final String value;
  final ValueChanged<String> onSubmit;
}

class TvInput {
  TvInput._();
  static final instance = TvInput._();

  final navigatorKey = GlobalKey<NavigatorState>();
  final _handlers = <CmdHandler>[];

  /// Har bir bosishda o‘sadi: pleyer paneli shunga qarab ko‘rinadi.
  final activity = ValueNotifier<int>(0);
  TextTarget? textTarget;

  /// Ekran o‘z tugmalarini ushlashi uchun (oxirgi qo‘shilgani birinchi).
  void push(CmdHandler h) => _handlers.add(h);
  void remove(CmdHandler h) => _handlers.remove(h);

  void send(Cmd cmd) {
    activity.value++;
    for (final h in _handlers.reversed.toList()) {
      if (h(cmd)) return;
    }
    _default(cmd);
  }

  void receiveText(String value) => textTarget?.onSubmit(value);

  bool moveFocus(TraversalDirection d) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) return false;
    return node.focusInDirection(d);
  }

  void activate() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
  }

  void _default(Cmd cmd) {
    switch (cmd) {
      case Cmd.up:
        moveFocus(TraversalDirection.up);
      case Cmd.down:
        moveFocus(TraversalDirection.down);
      case Cmd.left:
        moveFocus(TraversalDirection.left);
      case Cmd.right:
        moveFocus(TraversalDirection.right);
      case Cmd.ok:
        activate();
      case Cmd.back:
        navigatorKey.currentState?.maybePop();
      case Cmd.home:
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
      default:
        break;
    }
  }

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static final _keys = <LogicalKeyboardKey, Cmd>{
    LogicalKeyboardKey.arrowUp: Cmd.up,
    LogicalKeyboardKey.arrowDown: Cmd.down,
    LogicalKeyboardKey.arrowLeft: Cmd.left,
    LogicalKeyboardKey.arrowRight: Cmd.right,
    LogicalKeyboardKey.enter: Cmd.ok,
    LogicalKeyboardKey.numpadEnter: Cmd.ok,
    LogicalKeyboardKey.select: Cmd.ok,
    LogicalKeyboardKey.gameButtonA: Cmd.ok,
    LogicalKeyboardKey.escape: Cmd.back,
    LogicalKeyboardKey.goBack: Cmd.back,
    LogicalKeyboardKey.browserBack: Cmd.back,
    LogicalKeyboardKey.gameButtonB: Cmd.back,
    LogicalKeyboardKey.browserHome: Cmd.home,
    LogicalKeyboardKey.gameButtonMode: Cmd.home,
    LogicalKeyboardKey.mediaPlayPause: Cmd.playPause,
    LogicalKeyboardKey.mediaPlay: Cmd.playPause,
    LogicalKeyboardKey.mediaPause: Cmd.playPause,
    LogicalKeyboardKey.gameButtonStart: Cmd.playPause,
    LogicalKeyboardKey.mediaTrackNext: Cmd.next,
    LogicalKeyboardKey.mediaFastForward: Cmd.next,
    LogicalKeyboardKey.channelUp: Cmd.next,
    LogicalKeyboardKey.gameButtonRight1: Cmd.next,
    LogicalKeyboardKey.mediaTrackPrevious: Cmd.prev,
    LogicalKeyboardKey.mediaRewind: Cmd.prev,
    LogicalKeyboardKey.channelDown: Cmd.prev,
    LogicalKeyboardKey.gameButtonLeft1: Cmd.prev,
  };

  /// Klaviatura / Bluetooth pult / o‘yin pulti tugmasini buyruqqa aylantiradi.
  static Cmd? commandForKey(KeyEvent event) {
    if (event is KeyUpEvent) return null;
    final key = event.logicalKey;
    final typing = _typing();
    if (!typing && key == LogicalKeyboardKey.backspace) return Cmd.back;
    if (!typing && key == LogicalKeyboardKey.space) return Cmd.playPause;
    final cmd = _keys[key];
    if (cmd == null) return null;
    // Matn yozilayotganda kursor va Enter matn maydonining o‘ziga qoladi.
    if (typing && (cmd == Cmd.left || cmd == Cmd.right || cmd == Cmd.ok)) {
      return null;
    }
    return cmd;
  }

  KeyEventResult handleKey(KeyEvent event) {
    final cmd = commandForKey(event);
    if (cmd == null) return KeyEventResult.ignored;
    send(cmd);
    return KeyEventResult.handled;
  }
}
