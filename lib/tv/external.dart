/// Televizor uchun YouTube (youtube.com/tv) shu brauzer nomi bilan
/// pult boshqaradigan TV ko‘rinishida ochiladi (kompyuter YouTube’i emas).
const tvUserAgent =
    'Mozilla/5.0 (SMART-TV; Linux; Tizen 7.0) AppleWebKit/537.36 '
    '(KHTML, like Gecko) 94.0.4606.31/7.0 TV Safari/537.36';

const youtubeTvUrl = 'https://www.youtube.com/tv';

/// YouTube TV’da qidiruv natijalari.
String youtubeTvSearchUrl(String query) =>
    '$youtubeTvUrl#/search?q=${Uri.encodeQueryComponent(query.trim())}';

/// YouTube manzili (youtube.com, youtu.be, m.youtube.com) bo‘lsa — uning
/// televizor ko‘rinishidagi manzili, aks holda null.
String? youtubeTvFor(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return null;
  final host = u.host.toLowerCase();
  final short = host == 'youtu.be' || host == 'www.youtu.be';
  final youtube =
      host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com';
  if (!short && !youtube) return null;
  final segments = u.pathSegments.where((s) => s.isNotEmpty).toList();
  String? video;
  if (short) {
    video = segments.firstOrNull;
  } else if (segments.firstOrNull == 'watch') {
    video = u.queryParameters['v'];
  } else if (segments.length >= 2 &&
      (segments.first == 'shorts' ||
          segments.first == 'live' ||
          segments.first == 'embed')) {
    video = segments[1];
  }
  if (video != null && RegExp(r'^[\w-]{6,}$').hasMatch(video)) {
    return '$youtubeTvUrl#/watch?v=$video';
  }
  final query = u.queryParameters['search_query'];
  if (segments.firstOrNull == 'results' && query != null && query.isNotEmpty) {
    return youtubeTvSearchUrl(query);
  }
  if (youtube && segments.firstOrNull == 'tv') return url.trim();
  return youtubeTvUrl;
}
