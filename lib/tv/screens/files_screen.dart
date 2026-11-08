import 'dart:io';

import 'package:flutter/material.dart';

import '../../platform.dart';

import '../model.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';
import 'player_screen.dart';

/// Telefondagi video, musiqa va rasmlar — katta ekranda.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, this.filter});
  final MediaKind? filter;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  late MediaKind? _filter = widget.filter;

  static const _titles = {
    null: 'Mening fayllarim',
    MediaKind.video: 'Filmlar va videolar',
    MediaKind.audio: 'Musiqa',
    MediaKind.image: 'Rasmlar',
  };

  @override
  Widget build(BuildContext context) {
    final services = TvServices.instance;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: ValueListenableBuilder<List<MediaItem>>(
            valueListenable: TvStore.instance.library,
            builder: (context, library, _) {
              final list = library
                  .where(
                    (e) =>
                        (_filter == null || e.kind == _filter) &&
                        (!e.isFile || File(e.source).existsSync()),
                  )
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TvHeader(
                    title: _titles[_filter]!,
                    trailing: [
                      TvButton(
                        icon: Icons.photo_library_rounded,
                        label: 'Galereya',
                        primary: true,
                        autofocus: list.isEmpty,
                        onTap: () => services.pickFromPhone(gallery: true),
                      ),
                      TvButton(
                        icon: Icons.folder_open_rounded,
                        label: 'Fayllar',
                        onTap: () => services.pickFromPhone(gallery: false),
                      ),
                      if (_filter == MediaKind.image && list.isNotEmpty)
                        TvButton(
                          icon: Icons.slideshow_rounded,
                          label: 'Slayd-shou',
                          onTap: () => Navigator.of(
                            context,
                          ).push(PlayerScreen.route(list, 0)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      for (final k in [
                        null,
                        MediaKind.video,
                        MediaKind.audio,
                        MediaKind.image,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: TvFocusable(
                            radius: 22,
                            scale: 1.04,
                            onTap: () => setState(() => _filter = k),
                            builder: (context, f) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              color: f
                                  ? Colors.white
                                  : k == _filter
                                  ? Colors.white.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.08),
                              child: Text(
                                switch (k) {
                                  null => 'Hammasi',
                                  MediaKind.video => 'Video',
                                  MediaKind.audio => 'Musiqa',
                                  MediaKind.image => 'Rasm',
                                  MediaKind.live => '',
                                },
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: f ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: list.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.perm_media_rounded,
                                  size: 90,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Hali fayl yo‘q',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isDesktop
                                      ? 'Telefondan yuboring: Pult → “Fayl yuborish” (USB kabel yoki Wi-Fi orqali). '
                                            'Yoki “Fayllar” bilan shu kompyuterdagi videolarni oching.'
                                      : services.onTvDisplay
                                      ? '“Galereya” ni bosing va telefon ekranida video, rasm yoki musiqani tanlang.'
                                      : '“Galereya” yoki “Fayllar” ni bosib telefondagi fayllarni tanlang.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 19,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 40),
                            cacheExtent: 800,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 260,
                                  childAspectRatio: 16 / 11,
                                  mainAxisSpacing: 22,
                                  crossAxisSpacing: 22,
                                ),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final item = list[i];
                              return TvFocusable(
                                radius: 18,
                                onTap: () => Navigator.of(
                                  context,
                                ).push(PlayerScreen.route(list, i)),
                                builder: (context, f) => Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ArtBox(
                                      seed: item.title,
                                      icon: iconFor(item.kind),
                                      image: item.kind == MediaKind.image
                                          ? imageFor(item, width: 360)
                                          : null,
                                      cover: true,
                                    ),
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Color(0xBB000000),
                                          ],
                                          stops: [0.5, 1],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 12,
                                      right: 12,
                                      bottom: item.progress > 0 ? 14 : 10,
                                      child: Text(
                                        item.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (item.progress > 0)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 0,
                                        child: LinearProgressIndicator(
                                          value: item.progress,
                                          minHeight: 4,
                                          backgroundColor: Colors.white12,
                                          color: const Color(0xFF3B6CFF),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
