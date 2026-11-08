import 'package:flutter/material.dart';

import '../widgets.dart';

/// Qanday ulanadi: kabel, televizor menyusi va pult.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _cards = <(IconData, String, List<String>)>[
    (
      Icons.cable_rounded,
      'Kabel — bitta sim',
      [
        'iPhone 15 va yangilari: USB-C → HDMI kabel.',
        'iPhone 5–14: Apple Lightning Digital AV Adapter + HDMI kabel.',
        'Android: USB-C → HDMI kabel (telefon “DisplayPort” ni qo‘llashi kerak — Samsung Galaxy S/Note/Tab va boshqalar).',
        'Simning bir uchi telefonning USB uyasiga, ikkinchisi televizorning HDMI uyasiga.',
      ],
    ),
    (
      Icons.tv_rounded,
      'Samsung · Artel · Yasin',
      [
        'Televizor pultida SOURCE yoki INPUT ni bosing.',
        'HDMI 1 yoki HDMI 2 ni tanlang — ekranda z3wax TV chiqadi.',
        'Yasin LED-32E58TS: orqasida HDMI uyasi bor — SOURCE → HDMI.',
        'Chetlari kesilsa: televizor menyusida “16:9 / Screen Fit / Just Scan” yoki shu ilovadagi “Ekran chetlari”.',
      ],
    ),
    (
      Icons.usb_rounded,
      'USB orqali (Yasin va boshqalar)',
      [
        'Televizorning USB uyasi faqat fleshkadagi fayllarni o‘qiydi, jonli rasm qabul qilmaydi.',
        'Dokdagi “USB”: video, rasm, musiqa televizor o‘qiydigan formatda fleshkaga yoziladi → fleshkani TV ga ulang → SOURCE → USB.',
        'Smart Yasin (Android TV): ilovaning o‘zi fleshka orqali televizorga o‘rnatiladi — TV pulti bilan ishlaydi.',
      ],
    ),
    (
      Icons.phone_iphone_rounded,
      'Adapter yo‘q bo‘lsa (iPhone, Lightning)',
      [
        'Oddiy zaryad simi bilan TV ning USB uyasiga ulangan iPhone faqat zaryadlanadi — jonli rasm uzatmaydi.',
        'Sinab ko‘ring: sim bilan ulang → iPhone’da “Ishonish” → TV pultida SOURCE → USB. Rasm va videolar chiqsa — ular shu sim orqali ochiladi.',
        'Jonli Smart TV uchun eng arzon yo‘l: simsiz HDMI dongle (AirPlay / Miracast) — HDMI ga ulanadi, quvvati TV ning USB uyasidan; iPhone’da “Ekranni takrorlash”.',
      ],
    ),
    (
      Icons.computer_rounded,
      'Kompyuter (Ubuntu / Mac) orqali',
      [
        'Kompyuter HDMI kabel bilan televizorga, telefon zaryad simi bilan kompyuterga ulanadi.',
        'Telefonda “USB modem” (Android) yoki “Modem rejimi” (iPhone) ni yoqing → Pult bo‘limidagi QR kodni skanerlang.',
        'Pultdan video va rasmlarni USB kabel orqali yuborasiz — televizorda darhol ochiladi.',
      ],
    ),
    (
      Icons.cast_connected_rounded,
      'Telefonsiz doimiy Smart TV',
      [
        'Android TV stik / qutisini televizorning HDMI uyasiga ulang, quvvatini televizorning USB uyasidan oling.',
        'z3wax TV’ni stikka fleshka orqali o‘rnating (USB → “Ilovani fleshkaga yozish”).',
        'Sozlamalar → “Yoqilganda z3wax TV ochilsin”: televizor yoqilganda darhol Smart TV.',
      ],
    ),
    (
      Icons.settings_remote_rounded,
      'Pult',
      [
        'Telefonning o‘z ekrani — pult (sensorli panel, tugmalar, klaviatura).',
        'Ikkinchi telefon — QR kod orqali brauzerda pult.',
        'Bluetooth pult, klaviatura yoki o‘yin pulti — telefonga ulang, darhol ishlaydi.',
        'Televizorning o‘z (infraqizil) pulti telefonga signal yubora olmaydi.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            children: [
              const TvHeader(title: 'Televizorga qanday ulanadi'),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 2.15,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    for (final (icon, title, lines) in _cards)
                      TvFocusable(
                        scale: 1.02,
                        builder: (context, f) => Container(
                          padding: const EdgeInsets.all(22),
                          color: Colors.white.withValues(alpha: f ? 0.2 : 0.1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 28),
                                  const SizedBox(width: 12),
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              for (final l in lines)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(
                                    '•  $l',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
