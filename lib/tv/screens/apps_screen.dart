import 'package:flutter/material.dart';

import '../../native.dart';
import '../services.dart';
import '../widgets.dart';

/// TV qutisi / stikdagi barcha ilovalar (YouTube, brauzer, kinoteatrlar…).
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  late final Future<List<InstalledApp>> _apps = NativeBridge.listApps();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            children: [
              const TvHeader(title: 'Ilovalar'),
              const SizedBox(height: 22),
              Expanded(
                child: FutureBuilder<List<InstalledApp>>(
                  future: _apps,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final apps = snap.data ?? const [];
                    if (apps.isEmpty) {
                      return const Center(
                        child: Text(
                          'Ilovalar ro‘yxati faqat Android qurilmada (TV qutisi, stik, telefon) ko‘rinadi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 22, color: Colors.white70),
                        ),
                      );
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 40),
                      cacheExtent: 800,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            childAspectRatio: 0.95,
                            mainAxisSpacing: 22,
                            crossAxisSpacing: 22,
                          ),
                      itemCount: apps.length,
                      itemBuilder: (context, i) {
                        final app = apps[i];
                        return TvFocusable(
                          autofocus: i == 0,
                          radius: 22,
                          onTap: () => TvServices.instance.launchApp(app),
                          builder: (context, f) => Container(
                            color: f
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.1),
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                Expanded(
                                  child: app.icon.isEmpty
                                      ? Icon(
                                          Icons.apps_rounded,
                                          size: 64,
                                          color: f
                                              ? Colors.black54
                                              : Colors.white70,
                                        )
                                      : Image.memory(
                                          app.icon,
                                          fit: BoxFit.contain,
                                          gaplessPlayback: true,
                                        ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  app.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: f ? Colors.black : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
