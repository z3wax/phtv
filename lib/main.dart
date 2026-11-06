import 'dart:io';

import 'package:flutter/widgets.dart';

import 'linux_player.dart';
import 'phone/phone_shell.dart';
import 'tv/tv_app.dart';

/// Telefon ekrani: televizor alohida ulangan bo‘lsa — pult, aks holda Smart TV.
/// Ubuntu / Mac kompyuter: televizorga HDMI orqali ulanadi va o‘zi Smart TV bo‘ladi.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux) {
    // Linux’da video, jonli kanallar va musiqa mpv (media_kit) orqali.
    TvLinuxPlayer.register();
    runApp(const TvApp(onTvDisplay: false));
    return;
  }
  if (Platform.isMacOS) {
    // Mac: video macOS’ning o‘z AVFoundation’i orqali (qo‘shimcha
    // kutubxonasiz, apparat dekoderi bilan) — yengil va tejamkor.
    runApp(const TvApp(onTvDisplay: false));
    return;
  }
  runApp(const PhoneShell());
}

/// Televizor ekrani. Android (MainActivity.kt) va iPhone (AppDelegate.swift)
/// televizor ulanganda shu kirish nuqtasini ikkinchi Flutter dvigatelida
/// ishga tushiradi.
@pragma('vm:entry-point')
void tvMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TvApp(onTvDisplay: true));
}
