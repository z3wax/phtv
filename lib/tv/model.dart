/// Ilovadagi har bir ko‘riladigan narsa: kanal, video, musiqa yoki rasm.
enum MediaKind { live, video, audio, image }

class MediaItem {
  MediaItem({
    required this.title,
    required this.source,
    required this.kind,
    this.logo,
    this.group = '',
    this.positionMs = 0,
    this.durationMs = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String title;

  /// Internet manzili (https://…, rtmp://…) yoki telefondagi fayl yo‘li.
  final String source;
  final MediaKind kind;
  final String? logo;
  final String group;
  int positionMs;
  int durationMs;
  int updatedAt;

  bool get isFile => !source.contains('://');
  bool get isLive => kind == MediaKind.live;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  String get kindLabel => switch (kind) {
    MediaKind.live => 'Jonli efir',
    MediaKind.video => 'Video',
    MediaKind.audio => 'Musiqa',
    MediaKind.image => 'Rasm',
  };

  Map<String, Object?> toJson() => {
    't': title,
    's': source,
    'k': kind.name,
    if (logo != null && logo!.isNotEmpty) 'l': logo,
    if (group.isNotEmpty) 'g': group,
    if (positionMs > 0) 'p': positionMs,
    if (durationMs > 0) 'd': durationMs,
    'u': updatedAt,
  };

  static MediaItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final title = json['t'], source = json['s'];
    if (title is! String || source is! String || source.isEmpty) return null;
    return MediaItem(
      title: title,
      source: source,
      kind: MediaKind.values.firstWhere(
        (k) => k.name == json['k'],
        orElse: () => MediaKind.video,
      ),
      logo: json['l'] as String?,
      group: (json['g'] as String?) ?? '',
      positionMs: (json['p'] as num?)?.toInt() ?? 0,
      durationMs: (json['d'] as num?)?.toInt() ?? 0,
      updatedAt: (json['u'] as num?)?.toInt(),
    );
  }

  static const _video = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', '3gp', 'ts', 'm3u8', 'mpd', //
  };
  static const _audio = {
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr', //
  };
  static const _image = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', //
  };

  /// Fayl nomidan turini aniqlaydi; noma’lum bo‘lsa — null.
  static MediaKind? kindForName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    if (_video.contains(ext)) return MediaKind.video;
    if (_audio.contains(ext)) return MediaKind.audio;
    if (_image.contains(ext)) return MediaKind.image;
    return null;
  }
}
