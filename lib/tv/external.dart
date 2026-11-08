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

/// YouTube TV’ga qurilma faqat H.264 va 1080p gacha videoni o‘ynata oladi deb
/// ko‘rsatadi. Televizor nomi (Tizen) bilan YouTube 4K AV1/VP9 beradi —
/// kompyuter va telefon uni dasturiy dekodlashga ulgurmaydi: ovoz boradi,
/// tasvir qora bo‘lib qotadi. H.264 deyarli hamma joyda apparat dekodlanadi.
/// Sahifa skriptlaridan oldin ishlashi kerak (Linux — hujjat boshida,
/// boshqa joyda — yuklanish davomida qayta-qayta).
const youtubeVideoLimitScript = r'''
(function(){
if(window.__z3video)return;window.__z3video=1;
var MAXW=1920,MAXH=1080;
function ok(type){
 var t=String(type||'').toLowerCase();
 if(/av01|av1|vp09|vp9|vp8|hev1|hvc1|dvh1|dvhe/.test(t))return false;
 var n=function(k){var m=new RegExp(k+'=(\\d+)').exec(t);return m?+m[1]:0};
 if(n('width')>MAXW||n('height')>MAXH)return false;
 return true;
}
var MS=window.MediaSource||window.WebKitMediaSource;
if(MS&&MS.isTypeSupported){
 var orig=MS.isTypeSupported.bind(MS);
 MS.isTypeSupported=function(t){return ok(t)&&orig(t)};
}
if(window.ManagedMediaSource&&ManagedMediaSource.isTypeSupported){
 var mm=ManagedMediaSource.isTypeSupported.bind(ManagedMediaSource);
 ManagedMediaSource.isTypeSupported=function(t){return ok(t)&&mm(t)};
}
var cpt=HTMLMediaElement.prototype.canPlayType;
HTMLMediaElement.prototype.canPlayType=function(t){return ok(t)?cpt.call(this,t):''};
var mc=navigator.mediaCapabilities;
if(mc&&mc.decodingInfo){
 var di=mc.decodingInfo.bind(mc);
 mc.decodingInfo=function(c){
  var v=c&&c.video;
  if(v&&(!ok(v.contentType)||v.width>MAXW||v.height>MAXH)){
   return Promise.resolve({supported:false,smooth:false,powerEfficient:false});
  }
  return di(c);
 };
}
})();
''';
