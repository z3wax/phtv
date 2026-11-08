import 'package:flutter/material.dart';

import '../../media_picker.dart';
import '../../platform.dart';
import '../model.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';
import 'files_screen.dart';
import 'player_screen.dart';

/// Video pleyer: kompyuterdagi yoki telefondagi fayl, havola (mp4, m3u8),
/// oxirgi ko‘rilganlar. Pleyerda: tezlik, ±10 soniya, ovoz, sevimlilar.
class PlayerHubScreen extends StatelessWidget {
  const PlayerHubScreen({super.key});

  Future<void> _fromComputer(BuildContext context) async {
    final nav = Navigator.of(context);
    try {
      final items = await pickMedia(gallery: false);
      if (items.isEmpty) return;
      TvStore.instance.addToLibrary(items);
      await nav.push(PlayerScreen.route(items, 0));
    } catch (_) {
      TvServices.instance.showToast('Fayllarni ochib bo‘lmadi');
    }
  }

  void _fromLink(BuildContext context) {
    final nav = Navigator.of(context);
    TvServices.instance.editText(
      context,
      title: 'Video havolasi (mp4, m3u8, mkv…)',
      value: '',
      onSubmit: (v) {
        final url = v.trim();
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          TvServices.instance.showToast('Havola noto‘g‘ri');
          return;
        }
        final name = uri.pathSegments.isEmpty
            ? uri.host
            : uri.pathSegments.last;
        final item = MediaItem(
          title: name.isEmpty ? 'Video' : Uri.decodeComponent(name),
          source: url,
          kind: MediaItem.kindForName(name) ?? MediaKind.video,
        );
        nav.push(PlayerScreen.route([item], 0));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = TvServices.instance;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TvHeader(title: 'Video pleyer'),
              const SizedBox(height: 28),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  if (isDesktop)
                    _Big(
                      icon: Icons.computer_rounded,
                      title: 'Kompyuterdan',
                      subtitle: 'Video, musiqa, rasm',
                      colors: const [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
                      autofocus: true,
                      onTap: () => _fromComputer(context),
                    ),
                  _Big(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Telefondan',
                    subtitle: isDesktop ? 'Pult orqali yuborish' : 'Galereya',
                    colors: const [Color(0xFF22C55E), Color(0xFF14532D)],
                    autofocus: !isDesktop,
                    onTap: () => isDesktop
                        ? services.showToast(
                            'Pultdagi ⬆ tugmasi bilan telefondan video yuboring',
                          )
                        : services.pickFromPhone(gallery: true),
                  ),
                  _Big(
                    icon: Icons.link_rounded,
                    title: 'Havola',
                    subtitle: 'mp4, m3u8, mkv…',
                    colors: const [Color(0xFFA855F7), Color(0xFF4C1D95)],
                    onTap: () => _fromLink(context),
                  ),
                  _Big(
                    icon: Icons.video_library_rounded,
                    title: 'Videolarim',
                    subtitle: 'Yuborilgan fayllar',
                    colors: const [Color(0xFFF97316), Color(0xFF7C2D12)],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const FilesScreen(filter: MediaKind.video),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
              const Text(
                'Oxirgi ko‘rilganlar',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ValueListenableBuilder<List<MediaItem>>(
                  valueListenable: TvStore.instance.history,
                  builder: (context, list, _) {
                    final videos = list
                        .where(
                          (e) =>
                              e.kind == MediaKind.video ||
                              e.kind == MediaKind.audio,
                        )
                        .toList();
                    if (videos.isEmpty) {
                      return Text(
                        'Hali hech narsa ko‘rilmagan',
                        style: TextStyle(
                          fontSize: 19,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      );
                    }
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: videos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 18),
                      itemBuilder: (context, i) {
                        final v = videos[i];
                        return Align(
                          alignment: Alignment.topCenter,
                          child: TvFocusable(
                            onTap: () => Navigator.of(
                              context,
                            ).push(PlayerScreen.route(videos, i)),
                            builder: (context, f) => SizedBox(
                              width: 260,
                              height: 170,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ArtBox(
                                    seed: v.title,
                                    icon: Icons.play_arrow_rounded,
                                  ),
                                  Positioned(
                                    left: 14,
                                    right: 14,
                                    bottom: 16,
                                    child: Text(
                                      v.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        shadows: [Shadow(blurRadius: 8)],
                                      ),
                                    ),
                                  ),
                                  if (v.progress > 0)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: LinearProgressIndicator(
                                        value: v.progress,
                                        minHeight: 5,
                                        color: const Color(0xFFFF3B5C),
                                        backgroundColor: Colors.black45,
                                      ),
                                    ),
                                ],
                              ),
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

class _Big extends StatelessWidget {
  const _Big({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onTap: onTap,
      builder: (context, f) => Container(
        width: 250,
        height: 150,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
