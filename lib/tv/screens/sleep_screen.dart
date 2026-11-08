import 'package:flutter/material.dart';

import '../input.dart';
import '../motion.dart';
import '../widgets.dart';

/// Uyqu rejimi: qora ekran va xira soat. Istalgan tugma — qaytish:
/// tizim televizordagidek “z3wax tv” yuklanish ekrani bilan yonadi.
class SleepScreen extends StatefulWidget {
  const SleepScreen({super.key});

  @override
  State<SleepScreen> createState() => _SleepScreenState();
}

class _SleepScreenState extends State<SleepScreen> {
  @override
  void initState() {
    super.initState();
    TvInput.instance.push(_wake);
  }

  @override
  void dispose() {
    TvInput.instance.remove(_wake);
    super.dispose();
  }

  bool _wake(Cmd _) {
    if (mounted && (ModalRoute.isCurrentOf(context) ?? false)) {
      _powerOn();
      return true;
    }
    return false;
  }

  void _powerOn() {
    Navigator.of(context).maybePop();
    TvSplash.replay();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _powerOn,
        child: Ticker(
          builder: (context, now) => Align(
            // Soat har daqiqada biroz siljiydi — ekran kuymasligi uchun.
            alignment: Alignment(
              ((now.minute * 37) % 100) / 50 - 1,
              ((now.minute * 53) % 100) / 50 - 1,
            ),
            child: Padding(
              padding: const EdgeInsets.all(60),
              child: Text(
                hhmm(now),
                style: TextStyle(
                  fontSize: 90,
                  fontWeight: FontWeight.w200,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
