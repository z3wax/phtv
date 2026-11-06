import 'dart:io';

import 'package:flutter/material.dart';

import '../../native.dart';

import '../services.dart';
import '../store.dart';
import '../weather.dart';
import '../widgets.dart';
import 'help_screen.dart';
import 'pair_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmReset = false;
  bool _isTv = false;
  bool _isHome = false;

  @override
  void initState() {
    super.initState();
    _checkTv();
  }

  Future<void> _checkTv() async {
    final tv = await NativeBridge.isTvDevice();
    final home = tv && await NativeBridge.isHomeLauncher();
    if (mounted) {
      setState(() {
        _isTv = tv;
        _isHome = home;
      });
    }
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final store = TvStore.instance;
    final services = TvServices.instance;
    return Scaffold(
      body: TvBackdrop(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 36, 56, 0),
          child: Column(
            children: [
              const TvHeader(title: 'Sozlamalar'),
              const SizedBox(height: 20),
              Expanded(
                child: ValueListenableBuilder<TvSettings>(
                  valueListenable: store.settings,
                  builder: (context, s, _) => ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 40),
                    children: [
                      _Row(
                        icon: Icons.location_city_rounded,
                        title: 'Ob-havo shahri',
                        value: cities[s.city.clamp(0, cities.length - 1)].name,
                        autofocus: true,
                        onTap: () => store.updateSettings(
                          s.copyWith(city: (s.city + 1) % cities.length),
                        ),
                      ),
                      _Row(
                        icon: Icons.crop_free_rounded,
                        title: 'Ekran chetlari',
                        subtitle:
                            'Televizor rasm chetini kesib qo‘ysa, oshiring',
                        value: '${s.overscan}%',
                        onTap: () => store.updateSettings(
                          s.copyWith(overscan: (s.overscan + 1) % 9),
                        ),
                      ),
                      _Row(
                        icon: Icons.playlist_play_rounded,
                        title: 'IPTV pleylist manzili',
                        value: s.playlistUrl.isEmpty
                            ? 'Kiritilmagan'
                            : s.playlistUrl,
                        onTap: () => services.editText(
                          context,
                          title: 'M3U pleylist manzili',
                          value: s.playlistUrl,
                          onSubmit: (v) async {
                            final url = v.trim();
                            if (!url.startsWith('http')) return;
                            try {
                              final n = await store.loadPlaylistFromUrl(url);
                              services.showToast('$n ta kanal yuklandi');
                            } catch (_) {
                              services.showToast('Pleylistni yuklab bo‘lmadi');
                            }
                          },
                        ),
                      ),
                      _Row(
                        icon: Icons.settings_remote_rounded,
                        title: 'Boshqa telefonni pult qilish',
                        subtitle: 'QR kod — ilova o‘rnatmasdan',
                        onTap: () => _push(const PairScreen()),
                      ),
                      if (!services.onTvDisplay && services.useAsRemote != null)
                        _Row(
                          icon: Icons.phonelink_rounded,
                          title: 'Bu telefonni pult qilish',
                          subtitle:
                              'Boshqa telefondagi Telefon TV’ni boshqarish',
                          onTap: services.useAsRemote!,
                        ),
                      if (_isTv)
                        _Row(
                          icon: Icons.power_settings_new_rounded,
                          title: 'Yoqilganda Telefon TV ochilsin',
                          subtitle:
                              'TV qutisi / stik uchun: Telefon TV bosh ekran bo‘ladi (Home tugmasi ham)',
                          value: _isHome ? 'Yoniq' : 'O‘chiq',
                          onTap: () async {
                            await NativeBridge.setHomeLauncher(!_isHome);
                            final now = await NativeBridge.isHomeLauncher();
                            if (mounted) setState(() => _isHome = now);
                          },
                        ),
                      if (!Platform.isLinux)
                        _Row(
                          icon: Icons.usb_rounded,
                          title: 'USB orqali (fleshka, Smart Yasin)',
                          subtitle:
                              'Video, rasm, musiqani televizor o‘qiydigan qilib fleshkaga yozish',
                          onTap: services.showUsb,
                        ),
                      _Row(
                        icon: Icons.cable_rounded,
                        title: 'Televizorga qanday ulanadi',
                        subtitle: 'Kabel, Samsung / Artel / Yasin, pult',
                        onTap: () => _push(const HelpScreen()),
                      ),
                      _Row(
                        icon: Icons.delete_sweep_rounded,
                        title: _confirmReset
                            ? 'Yana bir marta bosing — hammasi o‘chadi'
                            : 'Ma’lumotlarni tozalash',
                        subtitle: 'Kanallar, tarix, sevimlilar va sozlamalar',
                        onTap: () async {
                          if (!_confirmReset) {
                            setState(() => _confirmReset = true);
                            return;
                          }
                          await store.clearAll();
                          if (mounted) setState(() => _confirmReset = false);
                          services.showToast('Tozalandi');
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Telefon TV 1.0 · Login, server va reklama yo‘q — hamma narsa telefoningizda.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.autofocus = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TvFocusable(
        autofocus: autofocus,
        scale: 1.02,
        radius: 18,
        onTap: onTap,
        builder: (context, f) {
          final fg = f ? Colors.black : Colors.white;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            color: f ? Colors.white : Colors.white.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(icon, color: fg, size: 30),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 15,
                            color: fg.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: fg.withValues(alpha: 0.6),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
