import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tv/model.dart';

/// Televizorning USB uyasi faqat fleshkadan fayl o‘qiydi. Shuning uchun
/// “USB orqali” — telefondagi fayllarni televizor tushunadigan shaklda
/// fleshkaga yozish (Android: MainActivity.kt / UsbExporter.kt,
/// iPhone: UsbExporter.swift).
const usbRootFolder = 'TELEFON_TV';

/// FAT32 fleshkaga 4 GB dan katta fayl sig‘maydi.
const fat32Limit = 4294967295;

/// Televizor turiga qarab fleshkaga yozish sozlamalari.
class UsbProfile {
  const UsbProfile({
    required this.id,
    required this.name,
    required this.note,
    required this.maxVideoShort,
    required this.maxImageSide,
  });
  final String id;
  final String name;
  final String note;

  /// Video kichik tomoni shundan katta bo‘lsa — kichraytiriladi (720 → 1280×720).
  final int maxVideoShort;

  /// Rasmning uzun tomoni shundan katta bo‘lsa — JPEG qilib kichraytiriladi.
  final int maxImageSide;
}

/// Yasin LED-32E58TS: Smart emas, MStar plata (MS36631 / 5800-A6M34G),
/// 32″ panel. Uning USB pleyeri uchun eng ishonchli: H.264 720p MP4, JPEG.
const usbProfiles = [
  UsbProfile(
    id: 'yasin_led_32e58ts',
    name: 'Yasin LED-32E58TS',
    note: 'Video H.264 720p MP4, rasm JPEG (1920 gacha), musiqa MP3',
    maxVideoShort: 720,
    maxImageSide: 1920,
  ),
  UsbProfile(
    id: 'full_hd',
    name: 'Boshqa Full HD televizor',
    note: 'Video H.264 1080p MP4, rasm JPEG (3840 gacha)',
    maxVideoShort: 1080,
    maxImageSide: 3840,
  ),
];

class UsbTarget {
  const UsbTarget(this.id, this.name);
  final String id;
  final String name;
}

/// Fleshkaga yoziladigan bitta fayl.
class UsbFile {
  const UsbFile({required this.path, required this.folder, required this.name});
  final String path;

  /// TELEFON_TV ichidagi papka: VIDEO, FOTO, MUSIQA yoki '' (ildiz).
  final String folder;
  final String name;

  Map<String, Object?> toMap() => {
    'path': path,
    'folder': folder,
    'name': name,
  };
}

class UsbProgress {
  const UsbProgress(this.done, this.total, this.name, this.converting);
  final int done, total;
  final String name;
  final bool converting;
}

class UsbResult {
  const UsbResult({
    required this.copied,
    required this.converted,
    required this.failed,
  });
  final int copied, converted;
  final List<String> failed;
}

String folderFor(MediaKind kind) => switch (kind) {
  MediaKind.image => 'FOTO',
  MediaKind.audio => 'MUSIQA',
  _ => 'VIDEO',
};

const _cyr = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'yo',
  'ж': 'j', //
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'x',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': '',
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya', 'ў': 'o', 'қ': 'q', 'ғ': 'g', 'ҳ': 'h',
};

/// Oddiy televizor ham o‘qiy oladigan fayl nomi: lotin harflari, raqam, `_`.
String safeFileName(String title, String ext, {int max = 48}) {
  final b = StringBuffer();
  for (final ch in title.toLowerCase().split('')) {
    if (_cyr.containsKey(ch)) {
      b.write(_cyr[ch]);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      b.write(ch);
    } else if ('‘’ʻʼ\''.contains(ch)) {
      // o‘ → o
    } else {
      b.write('_');
    }
  }
  var base = b
      .toString()
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (base.isEmpty) base = 'fayl';
  if (base.length > max) base = base.substring(0, max);
  final e = ext.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return e.isEmpty ? base : '$base.$e';
}

String extensionOf(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  final dot = path.lastIndexOf('.');
  return dot > slash ? path.substring(dot + 1) : '';
}

/// Asl va konvertatsiyadan keyingi nomlar ham bir-birini bosib yozmasin.
List<UsbFile> planUsb(List<MediaItem> items) {
  final used = <String>{};
  final out = <UsbFile>[];
  for (final item in items) {
    if (!item.isFile) continue;
    final folder = folderFor(item.kind);
    final ext = extensionOf(item.source);
    var name = safeFileName(item.title, ext);
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final suffix = dot > 0 ? name.substring(dot) : '';
    final convertedExt = switch (item.kind) {
      MediaKind.image => 'jpg',
      MediaKind.video || MediaKind.live => 'mp4',
      MediaKind.audio => ext.toLowerCase(),
    };
    Set<String> destinations(String candidate) {
      final candidateDot = candidate.lastIndexOf('.');
      final stem = candidateDot > 0
          ? candidate.substring(0, candidateDot)
          : candidate;
      return {
        '$folder/${candidate.toLowerCase()}',
        if (convertedExt.isNotEmpty)
          '$folder/${stem.toLowerCase()}.$convertedExt',
      };
    }

    for (var n = 2; destinations(name).any(used.contains); n++) {
      name = '${base}_$n$suffix';
    }
    used.addAll(destinations(name));
    out.add(UsbFile(path: item.source, folder: folder, name: name));
  }
  return out;
}

class UsbBridge {
  static const _channel = MethodChannel('telefon_tv/usb');
  static final progress = ValueNotifier<UsbProgress?>(null);
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && call.arguments is Map) {
        final m = call.arguments as Map;
        progress.value = UsbProgress(
          (m['done'] as num?)?.toInt() ?? 0,
          (m['total'] as num?)?.toInt() ?? 0,
          (m['name'] as String?) ?? '',
          m['converting'] == true,
        );
      }
      return null;
    });
  }

  /// Telefonga ulangan fleshkani (yoki undagi papkani) tanlash.
  static Future<UsbTarget?> pickTarget() async {
    _listen();
    final r = await _channel.invokeMapMethod<String, Object?>('pickTarget');
    if (r == null) return null;
    return UsbTarget(r['id'] as String, (r['name'] as String?) ?? 'Fleshka');
  }

  static Future<UsbResult> copy(
    List<UsbFile> files, {
    UsbProfile profile = const UsbProfile(
      id: 'full_hd',
      name: '',
      note: '',
      maxVideoShort: 1080,
      maxImageSide: 3840,
    ),
  }) async {
    _listen();
    progress.value = UsbProgress(0, files.length, '', false);
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('copy', {
        'root': usbRootFolder,
        'maxVideoShort': profile.maxVideoShort,
        'maxImageSide': profile.maxImageSide,
        'files': [for (final f in files) f.toMap()],
      });
      return UsbResult(
        copied: (r?['copied'] as num?)?.toInt() ?? 0,
        converted: (r?['converted'] as num?)?.toInt() ?? 0,
        failed: [for (final f in (r?['failed'] as List?) ?? const []) '$f'],
      );
    } finally {
      progress.value = null;
    }
  }

  /// Android: ilovaning o‘z APK fayli (Smart TV ga o‘rnatish uchun).
  static Future<String?> apkPath() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('apkPath');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
