import 'package:flutter/material.dart';

/// Bosh ekrandagi kino saytlari. Manzilni pultdan o‘zgartirish mumkin,
/// yangi sayt ham qo‘shiladi (masalan, iDub manzili).
@immutable
class Site {
  const Site({
    required this.id,
    required this.name,
    required this.url,
    required this.colors,
    this.aliases = const [],
    this.custom = false,
  });

  final String id;
  final String name;

  /// Bo‘sh — manzil hali kiritilmagan (birinchi bosilganda so‘raladi).
  final String url;
  final List<Color> colors;

  /// Ovozli buyruqda shu so‘zlar bilan ham tanilsin (“иви”, “uzmovie”…).
  final List<String> aliases;

  /// Foydalanuvchi qo‘shgan sayt (o‘chirish mumkin).
  final bool custom;

  Site withUrl(String u) => Site(
    id: id,
    name: name,
    url: u,
    colors: colors,
    aliases: aliases,
    custom: custom,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'colors': [for (final c in colors) c.toARGB32()],
  };

  static Site? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['url'] is! String) return null;
    final colors = j['colors'];
    return Site(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? j['url'] as String,
      url: j['url'] as String,
      colors: colors is List && colors.length == 2
          ? [for (final c in colors) Color((c as num).toInt())]
          : const [Color(0xFF475569), Color(0xFF1E293B)],
      custom: true,
    );
  }
}

const defaultSites = <Site>[
  Site(
    id: 'ivi',
    name: 'ivi',
    url: 'https://www.ivi.tv/uz',
    colors: [Color(0xFFEA003D), Color(0xFF7A0021)],
    aliases: ['ivi', 'иви', 'айви'],
  ),
  Site(
    id: 'uzmovi',
    name: 'Uzmovi',
    url: 'https://uzmovi.tv/',
    colors: [Color(0xFF0EA5E9), Color(0xFF0C4A6E)],
    aliases: ['uzmovi', 'uzmovie', 'uz movi', 'узмови', 'узмуви'],
  ),
  Site(
    id: 'idub',
    name: 'iDub',
    url: '', // rasmiy manzil tasdiqlanmadi — birinchi ochishda kiritiladi
    colors: [Color(0xFFF59E0B), Color(0xFF92400E)],
    aliases: ['idub', 'i dub', 'ай даб', 'айдаб', 'idab'],
  ),
  Site(
    id: 'kinopoisk',
    name: 'Kinopoisk',
    url: 'https://hd.kinopoisk.ru/',
    colors: [Color(0xFFFF6600), Color(0xFF9A3412)],
    aliases: ['kinopoisk', 'kino poisk', 'кинопоиск'],
  ),
  Site(
    id: 'okko',
    name: 'Okko',
    url: 'https://okko.tv/',
    colors: [Color(0xFF7C3AED), Color(0xFF3B0764)],
    aliases: ['okko', 'окко'],
  ),
  Site(
    id: 'megogo',
    name: 'MEGOGO',
    url: 'https://megogo.net/',
    colors: [Color(0xFF2563EB), Color(0xFF1E1B4B)],
    aliases: ['megogo', 'мегого'],
  ),
  Site(
    id: 'itv',
    name: 'iTV',
    url: 'https://itv.uz/',
    colors: [Color(0xFF10B981), Color(0xFF064E3B)],
    aliases: ['itv', 'ай ти ви', 'айтиви'],
  ),
  Site(
    id: 'netflix',
    name: 'Netflix',
    url: 'https://www.netflix.com/',
    colors: [Color(0xFFE50914), Color(0xFF3F0306)],
    aliases: ['netflix', 'нетфликс'],
  ),
];

/// “ivi.tv”, “https://ivi.tv/uz” → to‘liq manzil; bo‘sh yoki noto‘g‘ri — null.
String? normalizeUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty || s.contains(' ')) return null;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null || !u.host.contains('.')) return null;
  return u.toString();
}
