import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../input.dart';
import 'assistant.dart';

/// Televizor ekranining pastida Siri uslubidagi panel: rangli shar,
/// eshitilgan savol va oqim bo‘lib kelayotgan javob.
class AssistantOverlay extends StatefulWidget {
  const AssistantOverlay({super.key});

  @override
  State<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends State<AssistantOverlay>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  final _a = Assistant.instance;
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    _a.state.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _a.state.removeListener(_changed);
    if (_handling) TvInput.instance.remove(_onCmd);
    _spin.dispose();
    super.dispose();
  }

  void _changed() {
    final s = _a.state.value;
    if (s.visible && !_handling) {
      TvInput.instance.push(_onCmd);
      _handling = true;
    } else if (!s.visible && _handling) {
      TvInput.instance.remove(_onCmd);
      _handling = false;
    }
    final busy =
        s.phase == AssistPhase.listening ||
        s.phase == AssistPhase.thinking ||
        s.phase == AssistPhase.answering;
    _spin.duration = Duration(
      milliseconds: s.phase == AssistPhase.thinking ? 1400 : 4000,
    );
    if (s.visible && (busy || !_spin.isAnimating)) {
      _spin.repeat();
    } else if (!s.visible) {
      _spin.stop();
    }
  }

  /// Panel ochiq: Orqaga / OK — yopadi, boshqa tugmalar — yopib, o‘tkazadi.
  bool _onCmd(Cmd cmd) {
    _a.dismiss();
    return cmd == Cmd.back || cmd == Cmd.ok;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistState>(
      valueListenable: _a.state,
      builder: (context, s, _) {
        final listening = s.phase == AssistPhase.listening;
        final error = s.phase == AssistPhase.error;
        final answer = switch (s.phase) {
          AssistPhase.listening => '',
          AssistPhase.thinking => '',
          _ => s.answer,
        };
        final question = s.question.isEmpty && listening
            ? 'Gapiring, eshityapman…'
            : s.question;
        return IgnorePointer(
          ignoring: !s.visible,
          child: AnimatedSlide(
            offset: s.visible ? Offset.zero : const Offset(0, 0.4),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: s.visible ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(60, 0, 60, 34),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(36),
                      child: DefaultTextStyle(
                        style: const TextStyle(decoration: TextDecoration.none),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(26, 22, 34, 24),
                          decoration: BoxDecoration(
                            color: const Color(0xEB0B0B10),
                            borderRadius: BorderRadius.circular(36),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _spin,
                                builder: (context, _) => _Orb(
                                  turn: _spin.value,
                                  pulse: listening,
                                  error: error,
                                ),
                              ),
                              const SizedBox(width: 26),
                              Expanded(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: Alignment.topLeft,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (question.isNotEmpty)
                                        Text(
                                          question,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: answer.isEmpty ? 28 : 20,
                                            fontWeight: answer.isEmpty
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: Colors.white.withValues(
                                              alpha: answer.isEmpty
                                                  ? 0.95
                                                  : 0.55,
                                            ),
                                          ),
                                        ),
                                      if (s.phase == AssistPhase.thinking)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            'O‘ylayapman…',
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.white.withValues(
                                                alpha: 0.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (answer.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          answer,
                                          maxLines: 7,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 27,
                                            height: 1.3,
                                            fontWeight: FontWeight.w600,
                                            color: error
                                                ? const Color(0xFFFBBF24)
                                                : Colors.white,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Siri’ga o‘xshash aylanuvchi rangli shar.
class _Orb extends StatelessWidget {
  const _Orb({required this.turn, required this.pulse, required this.error});
  final double turn;
  final bool pulse;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scale = pulse ? 1 + 0.08 * math.sin(turn * math.pi * 8) : 1.0;
    const colors = [
      Color(0xFFFF2D55),
      Color(0xFFAF52DE),
      Color(0xFF5AC8FA),
      Color(0xFF34C759),
      Color(0xFFFF2D55),
    ];
    return Transform.scale(
      scale: scale,
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Transform.rotate(
              angle: turn * 2 * math.pi,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: error
                        ? const [
                            Color(0xFFFBBF24),
                            Color(0xFFEF4444),
                            Color(0xFFFBBF24),
                          ]
                        : colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (error
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFAF52DE))
                              .withValues(alpha: 0.55),
                      blurRadius: 34,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF1C1C24), Color(0xFF050507)],
                ),
              ),
              child: Icon(
                pulse ? Icons.mic_rounded : Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
