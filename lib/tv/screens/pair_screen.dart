import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../platform.dart';

import '../server.dart';
import '../services.dart';
import '../store.dart';
import '../widgets.dart';

/// Boshqa telefonni pult qilish: QR kodni skanerlash kifoya.
/// Telefon Wi-Fi orqali yoki USB kabel orqali (USB modem / iPhone modem
/// rejimi) ulanishi mumkin — har biri o‘z manziliga ega.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  List<LocalAddress>? _addresses;
  int _selected = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // USB kabel yoki Wi-Fi keyinroq ulanishi mumkin — ro‘yxatni yangilab turamiz.
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await RemoteServer.localAddresses();
    if (!mounted) return;
    final current = _addresses == null || _addresses!.isEmpty
        ? null
        : _addresses![_selected.clamp(0, _addresses!.length - 1)].ip;
    final keep = list.indexWhere((a) => a.ip == current);
    setState(() {
      _addresses = list;
      _selected = keep >= 0 ? keep : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = TvStore.instance.remoteKey;
    final list = _addresses;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 30),
          child: Column(
            children: [
              const TvHeader(title: 'Telefonni pult qilish'),
              Expanded(
                child: list == null
                    ? const Center(child: CircularProgressIndicator())
                    : list.isEmpty
                    ? const _NoNetwork()
                    : _body(list, key),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<LocalAddress> list, String key) {
    final a = list[_selected.clamp(0, list.length - 1)];
    final url = 'http://${a.ip}:${RemoteServer.defaultPort}/?k=$key';
    final desktop = isDesktop;
    final steps = a.label == 'USB kabel' || a.label.startsWith('iPhone')
        ? const [
            '1. Telefon shu kompyuterga USB kabel bilan ulangan.',
            '2. Kamerani QR kodga qarating — brauzerda pult ochiladi.',
            '3. Pultdagi “Fayl yuborish” — video va rasmlar shu kabel orqali keladi.',
          ]
        : [
            desktop
                ? '1. Telefon shu kompyuter bilan bitta Wi-Fi da bo‘lsin (yoki USB kabel bilan ulang).'
                : '1. Ikkala telefon bitta Wi-Fi (yoki hotspot) da bo‘lsin.',
            '2. Kamerani QR kodga qarating — brauzerda pult ochiladi.',
            '3. Yoki Telefon TV ilovasida: Sozlamalar → “Bu telefonni pult qilish”.',
          ];
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: QrImageView(
            data: url,
            size: 300,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 56),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Telefon — pult',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              if (list.length > 1) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < list.length; i++)
                      TvFocusable(
                        autofocus: i == _selected,
                        radius: 16,
                        scale: 1.04,
                        onTap: () => setState(() => _selected = i),
                        builder: (context, f) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          color: f
                              ? Colors.white
                              : i == _selected
                              ? const Color(0xFF3B6CFF)
                              : Colors.white.withValues(alpha: 0.12),
                          child: Text(
                            list[i].label,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: f ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              for (final s in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    s,
                    style: const TextStyle(fontSize: 21, height: 1.3),
                  ),
                ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _Chip(label: a.label, value: a.ip),
                  _Chip(label: 'PIN', value: key),
                ],
              ),
              const SizedBox(height: 22),
              ValueListenableBuilder<int>(
                valueListenable: TvServices.instance.remotes,
                builder: (context, n, _) => Row(
                  children: [
                    Icon(
                      n > 0
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: n > 0 ? const Color(0xFF4ADE80) : Colors.white54,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      n > 0 ? 'Ulangan pultlar: $n' : 'Pult kutilmoqda…',
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoNetwork extends StatelessWidget {
  const _NoNetwork();

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop;
    return Center(
      child: SizedBox(
        width: 900,
        child: Text(
          desktop
              ? 'Telefon bilan aloqa yo‘q.\n\n'
                    'USB kabel orqali: telefonni kompyuterga ulang va\n'
                    '• Android: Sozlamalar → Hotspot / Modem → “USB modem” ni yoqing;\n'
                    '• iPhone: Sozlamalar → “Modem rejimi” ni yoqing (kabel ulangan holda).\n'
                    'Yoki telefon va kompyuterni bitta Wi-Fi ga ulang. Manzil o‘zi paydo bo‘ladi.'
              : 'Wi-Fi topilmadi.\n\nTelefonni Wi-Fi’ga ulang — yoki telefonda “Modem rejimi / Hotspot” ni '
                    'yoqing va ikkinchi telefonni shu tarmoqqa ulang.',
          textAlign: desktop ? TextAlign.left : TextAlign.center,
          style: const TextStyle(fontSize: 23, height: 1.45),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label  ',
            style: const TextStyle(color: Colors.white60),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 26),
    ),
  );
}
