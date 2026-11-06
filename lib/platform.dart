import 'dart:io';

/// Kompyuter (Ubuntu, Mac): televizorga HDMI orqali ulanadi va o‘zi Smart TV
/// bo‘ladi; telefon — pult (Wi-Fi yoki USB kabel orqali).
bool get isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;
