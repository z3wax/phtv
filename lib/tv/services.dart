import 'dart:async';

import 'package:flutter/material.dart';

import '../media_picker.dart';
import '../native.dart';
import 'input.dart';
import 'model.dart';
import 'screens/files_screen.dart';
import 'screens/player_screen.dart';
import 'server.dart';
import 'store.dart';

/// Televizor ekranining umumiy xizmatlari.
class TvServices {
  TvServices._();
  static final instance = TvServices._();

  /// true — televizorda alohida oyna (telefon ekranida pult).
  /// false — televizor telefon ekranini takrorlaydi yoki TV ulanmagan.
  bool onTvDisplay = false;
  RemoteServer? server;

  /// Telefonni boshqa televizor uchun pultga aylantirish (faqat telefon ekranida).
  VoidCallback? useAsRemote;

  /// USB fleshka ekrani (fayl tanlash faqat telefon ekranida ishlaydi).
  VoidCallback? openUsb;

  /// Ulangan pultlar soni.
  final remotes = ValueNotifier<int>(0);

  /// “USB orqali”: telefon ekranida fleshkaga yozish oynasini ochadi.
  void showUsb() {
    if (openUsb != null) {
      openUsb!();
      return;
    }
    final sent = server?.broadcast({'t': 'usb'}, localOnly: true) ?? 0;
    showToast(
      sent > 0
          ? 'Telefon ekranida: USB fleshka'
          : 'Telefondagi pult ochiq emas',
    );
  }

  final toast = ValueNotifier<String?>(null);
  Timer? _toastTimer;

  void showToast(String text) {
    toast.value = text;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 3), () => toast.value = null);
  }

  void dispose() {
    _toastTimer?.cancel();
    toast.value = null;
  }

  NavigatorState? get _nav => TvInput.instance.navigatorKey.currentState;

  /// TV qutisi / stikdagi o‘rnatilgan ilovani ochish.
  Future<void> launchApp(InstalledApp app) async {
    showToast('${app.label} ochilmoqda…');
    if (!await NativeBridge.launchApp(app.package)) {
      showToast('${app.label} ni ochib bo‘lmadi');
    }
  }

  Future<void> openApp(String url, String name) async {
    showToast('$name ochilmoqda…');
    if (!await NativeBridge.openUrl(url)) showToast('$name ni ochib bo‘lmadi');
  }

  /// Fayl tanlash oynasi faqat telefon ekranida ochiladi: TV alohida oynada
  /// bo‘lsa, so‘rov telefondagi pultga yuboriladi.
  Future<void> pickFromPhone({required bool gallery}) async {
    if (onTvDisplay) {
      final sent =
          server?.broadcast({
            't': 'pick',
            'gallery': gallery,
          }, localOnly: true) ??
          0;
      showToast(
        sent > 0
            ? 'Telefon ekranida fayllarni tanlang'
            : 'Telefondagi pult ochiq emas',
      );
      return;
    }
    try {
      final items = await pickMedia(gallery: gallery);
      if (items.isNotEmpty) receiveMedia(items);
    } catch (_) {
      showToast('Fayllarni ochib bo‘lmadi');
    }
  }

  /// Boshqa telefondan (Wi-Fi yoki USB kabel orqali) yuborilgan fayl.
  /// Oxirgisi kelganda: bitta video/musiqa — darhol ijro, ko‘p — fayllar.
  void receiveUpload(MediaItem item, int index, int count) {
    TvStore.instance.addToLibrary([item]);
    showToast(
      count > 1
          ? 'Qabul qilindi: ${index + 1} / $count'
          : '“${item.title}” qabul qilindi',
    );
    if (index < count - 1) return;
    final nav = _nav;
    if (nav == null) return;
    if (count == 1 && item.kind != MediaKind.image) {
      nav.push(PlayerScreen.route([item], 0));
    } else {
      nav.push(MaterialPageRoute<void>(builder: (_) => const FilesScreen()));
    }
  }

  /// Telefondan kelgan fayllar: bitta video/musiqa bo‘lsa — darhol ijro.
  void receiveMedia(List<MediaItem> items) {
    TvStore.instance.addToLibrary(items);
    final nav = _nav;
    if (nav == null) return;
    if (items.length == 1 && items.first.kind != MediaKind.image) {
      nav.push(PlayerScreen.route(items, 0));
    } else {
      showToast('${items.length} ta fayl qo‘shildi');
      nav.push(MaterialPageRoute<void>(builder: (_) => const FilesScreen()));
    }
  }

  /// Matn kiritish: TV alohida oynada bo‘lsa — pultda yoziladi,
  /// aks holda telefon klaviaturasi ochiladi.
  Future<void> editText(
    BuildContext context, {
    required String title,
    required String value,
    required ValueChanged<String> onSubmit,
  }) async {
    if (onTvDisplay) {
      TvInput.instance.textTarget = TextTarget(
        hint: title,
        value: value,
        onSubmit: (v) {
          TvInput.instance.textTarget = null;
          onSubmit(v);
        },
      );
      final sent =
          server?.broadcast({
            't': 'textFocus',
            'hint': title,
            'value': value,
          }) ??
          0;
      showToast(
        sent > 0 ? 'Pultda yozing: $title' : 'Yozish uchun pultni ulang',
      );
      return;
    }
    final controller = TextEditingController(text: value);
    BuildContext? dialog;
    // Pultdan (telefon, brauzer) yozilgan matn ham shu oynaga tushadi.
    TvInput.instance.textTarget = TextTarget(
      hint: title,
      value: value,
      onSubmit: (v) {
        final ctx = dialog;
        if (ctx != null && ctx.mounted) Navigator.pop(ctx, v);
      },
    );
    server?.broadcast({'t': 'textFocus', 'hint': title, 'value': value});
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        dialog = ctx;
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Saqlash'),
            ),
          ],
        );
      },
    );
    TvInput.instance.textTarget = null;
    controller.dispose();
    if (result != null) onSubmit(result);
  }
}
