// Faqat ko‘rinishni tekshirish uchun: ilovadagi qora pult (Ubuntu oynasida).
import 'package:flutter/material.dart';
import 'package:telefon_tv/phone/remote_screen.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const Center(
        child: SizedBox(
          width: 390,
          height: 844,
          child: RemoteScreen(host: '127.0.0.1', port: 8765, local: true),
        ),
      ),
    ),
  );
}
