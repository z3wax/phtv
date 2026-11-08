import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../media_picker.dart';
import '../tv/model.dart';
import '../usb.dart';

/// “USB orqali televizorga”: telefondagi fayllarni televizor (Yasin, Artel,
/// Samsung…) USB uyasidan o‘qiy oladigan shaklda fleshkaga yozish.
class UsbScreen extends StatefulWidget {
  const UsbScreen({super.key, this.onExit});
  final VoidCallback? onExit;

  @override
  State<UsbScreen> createState() => _UsbScreenState();
}

class _UsbScreenState extends State<UsbScreen> {
  final _items = <MediaItem>[];
  UsbTarget? _target;
  bool _busy = false;
  UsbResult? _result;
  String? _error;
  UsbProfile _profile = usbProfiles.first;

  int _size(MediaItem i) {
    try {
      return File(i.source).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  String _mb(int bytes) => bytes >= 1 << 30
      ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
      : '${(bytes / (1 << 20)).toStringAsFixed(bytes < 10 << 20 ? 1 : 0)} MB';

  Future<void> _pick(bool gallery) async {
    try {
      final picked = await pickMedia(gallery: gallery);
      if (picked.isEmpty) return;
      setState(() {
        final have = _items.map((e) => e.source).toSet();
        _items.addAll(picked.where((e) => !have.contains(e.source)));
        _result = null;
      });
    } catch (_) {
      _snack('Fayllarni ochib bo‘lmadi');
    }
  }

  Future<void> _pickTarget() async {
    try {
      final t = await UsbBridge.pickTarget();
      if (t != null) setState(() => _target = t);
    } on PlatformException catch (e) {
      _snack('Fleshkani ochib bo‘lmadi: ${e.message ?? e.code}');
    }
  }

  Future<void> _write(List<UsbFile> files) async {
    if (_target == null) {
      await _pickTarget();
      if (_target == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await UsbBridge.copy(files, profile: _profile);
      setState(() => _result = r);
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeApk() async {
    final apk = await UsbBridge.apkPath();
    if (apk == null) {
      _snack('APK topilmadi');
      return;
    }
    await _write([UsbFile(path: apk, folder: '', name: 'TelefonTV.apk')]);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (s, i) => s + _size(i));
    final tooBig = _items.where((i) => _size(i) > fat32Limit).toList();
    final counts = {
      for (final k in MediaKind.values)
        k: _items.where((i) => i.kind == k).length,
    };
    return Scaffold(
      appBar: AppBar(
        leading: widget.onExit == null
            ? null
            : IconButton(
                onPressed: widget.onExit,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: const Text('USB orqali televizorga'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Note(
            icon: Icons.info_outline_rounded,
            color: Color(0xFFFBBF24),
            text:
                'Televizorning USB uyasi faqat fleshkadagi fayllarni o‘qiydi — jonli rasm qabul qilmaydi. '
                'Shuning uchun USB orqali: telefondagi video, rasm va musiqani shu yerda fleshkaga yozasiz, '
                'fleshkani televizorga ulaysiz. Oddiy Yasin, Artel, Samsung — hammasida ishlaydi.',
          ),
          const SizedBox(height: 16),
          Text(
            'Televizoringiz',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in usbProfiles)
                ChoiceChip(
                  label: Text(p.name),
                  selected: p == _profile,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _profile = p),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_profile.note, style: const TextStyle(color: Colors.white70)),
          if (_profile == usbProfiles.first) ...[
            const SizedBox(height: 10),
            const _Note(
              icon: Icons.tv_rounded,
              color: Color(0xFF93C5FD),
              text:
                  'Yasin LED-32E58TS — Smart emas. Orqasida HDMI uyasi bor (yorliqdagi HDMI belgisi): '
                  'jonli kanallar, YouTube va telefon pulti bilan to‘liq Smart TV uchun telefonni HDMI sim bilan ulang. '
                  'USB uyasi esa faqat fleshkadagi fayllar uchun — quyidagi qadamlar aynan shu televizorga moslangan.',
            ),
          ],
          const SizedBox(height: 16),
          _Step(
            n: 1,
            title: 'Fayllarni tanlang',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(true),
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('Galereya'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pick(false),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Fayllar'),
                      ),
                    ),
                  ],
                ),
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${_items.length} ta fayl · ${_mb(total)}  '
                    '(video ${counts[MediaKind.video]}, rasm ${counts[MediaKind.image]}, musiqa ${counts[MediaKind.audio]})',
                  ),
                  if (tooBig.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${tooBig.length} ta fayl 4 GB dan katta. FAT32 fleshkaga 4 GB dan katta fayl sig‘maydi; '
                        '720p ga o‘tkazilganda video odatda ancha kichrayadi, lekin juda uzun bo‘lsa yozilmasligi mumkin.',
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                    ),
                  const SizedBox(height: 6),
                  for (final i in _items.take(50))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(switch (i.kind) {
                        MediaKind.image => Icons.photo_rounded,
                        MediaKind.audio => Icons.music_note_rounded,
                        _ => Icons.movie_rounded,
                      }),
                      title: Text(
                        i.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_mb(_size(i))),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _items.remove(i)),
                      ),
                    ),
                  if (_items.length > 50)
                    Text('… yana ${_items.length - 50} ta'),
                ],
              ],
            ),
          ),
          _Step(
            n: 2,
            title: 'Fleshkani telefonga ulang va tanlang',
            subtitle: Platform.isIOS
                ? 'iPhone 15+: USB-C fleshka yoki adapter. iPhone 5–14: Lightning → USB adapter (Camera Adapter).'
                : 'USB-C (yoki micro-USB) OTG adapter orqali. Telefon “USB xotira” ni ko‘rsatadi.',
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickTarget,
              icon: const Icon(Icons.usb_rounded),
              label: Text(
                _target == null
                    ? 'Fleshkani tanlash'
                    : 'Tanlangan: ${_target!.name}',
              ),
            ),
          ),
          _Step(
            n: 3,
            title: 'Fleshkaga yozish',
            subtitle:
                'Fayllar $usbRootFolder/VIDEO, FOTO, MUSIQA papkalariga yoziladi. Televizoringizga mos kelmagan '
                'video (HEVC, 4K, .mov) H.264 MP4 ga (${_profile.maxVideoShort}p gacha), HEIC va katta rasmlar '
                'JPEG ga avtomatik o‘tkaziladi; mosi o‘zgarishsiz yoziladi.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _busy || _items.isEmpty
                      ? null
                      : () => _write(planUsb(_items)),
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Fleshkaga yozish'),
                ),
                if (_busy)
                  ValueListenableBuilder<UsbProgress?>(
                    valueListenable: UsbBridge.progress,
                    builder: (context, p, _) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: p == null || p.total == 0
                                ? null
                                : p.done / p.total,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p == null
                                ? 'Boshlanmoqda…'
                                : '${p.done + 1 > p.total ? p.total : p.done + 1}/${p.total}: ${p.name}'
                                      '${p.converting ? ' — televizor formatiga o‘tkazilmoqda…' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Note(
                      icon: _result!.failed.isEmpty
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: _result!.failed.isEmpty
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFFBBF24),
                      text:
                          '${_result!.copied} ta fayl yozildi'
                          '${_result!.converted > 0 ? ' (${_result!.converted} tasi televizor formatiga o‘tkazildi)' : ''}.'
                          '${_result!.failed.isEmpty ? '' : '\nYozilmadi: ${_result!.failed.join(', ')}'}',
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Note(
                      icon: Icons.error_outline_rounded,
                      color: const Color(0xFFFF8A80),
                      text: _error!,
                    ),
                  ),
              ],
            ),
          ),
          const _Step(
            n: 4,
            title: 'Fleshkani televizorga ulang',
            subtitle:
                'Fleshkani telefondan chiqarib, televizorning USB uyasiga ulang.\n'
                '• Yasin: pultda SOURCE (yoki INPUT) → USB / Media → $usbRootFolder → VIDEO, FOTO yoki MUSIQA.\n'
                '• Artel, Samsung, LG: SOURCE → USB.\n'
                'Fleshka FAT32 formatda bo‘lsin — oddiy televizorlar uni eng ishonchli o‘qiydi '
                '(exFAT ni ko‘pi o‘qimaydi, telefon esa NTFS ga yoza olmaydi).',
          ),
          const Divider(height: 36),
          Text(
            'Telefonsiz doimiy Smart TV: Android TV stik / qutisi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'LED-32E58TS ichida ilova ishlatadigan protsessor yo‘q, shuning uchun uni o‘zini Smart qilib bo‘lmaydi. '
            'Doimiy Smart TV uchun: arzon Android TV stik yoki qutisini Yasin’ning HDMI uyasiga ulang, quvvatini '
            'Yasin’ning USB uyasidan oling. z3wax TV’ni stikka o‘rnating — televizor yoqilganda darhol z3wax TV '
            'ochiladi, stik pulti bilan boshqariladi, telefoningiz QR kod orqali qo‘shimcha pult bo‘ladi.\n'
            '1) Ilovani fleshkaga yozing.  2) Fleshkani stik / qutiga ulang (stikka — OTG adapter bilan).  '
            '3) Fayl menejeri → $usbRootFolder → TelefonTV.apk → O‘rnatish (“noma’lum manbalar” ga ruxsat bering).  '
            '4) z3wax TV → Sozlamalar → “Yoqilganda z3wax TV ochilsin”.\n'
            'Android TV li Smart televizorlarga ham xuddi shunday o‘rnatiladi.',
          ),
          const SizedBox(height: 10),
          if (Platform.isAndroid)
            OutlinedButton.icon(
              onPressed: _busy ? null : _writeApk,
              icon: const Icon(Icons.install_mobile_rounded),
              label: const Text('Ilovani fleshkaga yozish'),
            )
          else
            const Text(
              'iPhone’dan APK yozib bo‘lmaydi: TelefonTV.apk ni GitHub’dan (Actions → Telefon TV) '
              'kompyuter yoki Android telefon orqali fleshkaga yozing.',
              style: TextStyle(color: Colors.white70),
            ),
          const Divider(height: 36),
          const _Note(
            icon: Icons.live_tv_rounded,
            color: Color(0xFF93C5FD),
            text:
                'Jonli kanallar, YouTube va telefon pulti bilan to‘liq Smart TV uchun bitta sim kerak: '
                'telefonning USB uyasidan televizorning HDMI uyasiga (USB-C → HDMI yoki Lightning → HDMI).',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    this.subtitle,
    this.child,
  });
  final int n;
  final String title;
  final String? subtitle;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            child: Text(
              '$n',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
                if (child != null) ...[const SizedBox(height: 10), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
      ],
    ),
  );
}
