import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'store.dart';

class City {
  const City(this.name, this.lat, this.lon);
  final String name;
  final double lat, lon;
}

const cities = [
  City('Toshkent', 41.3111, 69.2797),
  City('Samarqand', 39.6542, 66.9597),
  City('Buxoro', 39.7747, 64.4286),
  City('Andijon', 40.7821, 72.3442),
  City('Farg‘ona', 40.3864, 71.7864),
  City('Namangan', 40.9983, 71.6726),
  City('Qarshi', 38.8606, 65.7891),
  City('Nukus', 42.4531, 59.6103),
  City('Termiz', 37.2242, 67.2783),
  City('Urganch', 41.5500, 60.6333),
  City('Navoiy', 40.0844, 65.3792),
  City('Jizzax', 40.1158, 67.8422),
  City('Guliston', 40.4897, 68.7842),
];

class HourWeather {
  const HourWeather(this.hour, this.temp, this.code);
  final int hour;
  final double temp;
  final int code;
}

class Weather {
  const Weather({
    required this.city,
    required this.temp,
    required this.code,
    required this.max,
    required this.min,
    required this.hours,
  });
  final String city;
  final double temp, max, min;
  final int code;
  final List<HourWeather> hours;
}

String weatherText(int code) => switch (code) {
  0 => 'Ochiq osmon',
  1 || 2 => 'Qisman bulutli',
  3 => 'Bulutli',
  45 || 48 => 'Tuman',
  >= 51 && <= 57 => 'Mayda yomg‘ir',
  >= 61 && <= 67 || >= 80 && <= 82 => 'Yomg‘ir',
  >= 71 && <= 77 || 85 || 86 => 'Qor',
  >= 95 => 'Momaqaldiroq',
  _ => 'Bulutli',
};

IconData weatherIcon(int code) => switch (code) {
  0 => Icons.wb_sunny_rounded,
  1 || 2 => Icons.wb_cloudy_rounded,
  3 || 45 || 48 => Icons.cloud_rounded,
  >= 51 && <= 57 => Icons.grain_rounded,
  >= 61 && <= 67 || >= 80 && <= 82 => Icons.water_drop_rounded,
  >= 71 && <= 77 || 85 || 86 => Icons.ac_unit_rounded,
  >= 95 => Icons.thunderstorm_rounded,
  _ => Icons.cloud_rounded,
};

/// Ob-havo: Open-Meteo (bepul, kalitsiz). Har 30 daqiqada yangilanadi.
class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  final weather = ValueNotifier<Weather?>(null);
  Timer? _timer;
  int? _city;

  void start() {
    TvStore.instance.settings.addListener(_onSettings);
    _onSettings();
    _timer ??= Timer.periodic(const Duration(minutes: 30), (_) => refresh());
  }

  void stop() {
    TvStore.instance.settings.removeListener(_onSettings);
    _timer?.cancel();
    _timer = null;
  }

  void _onSettings() {
    final c = TvStore.instance.settings.value.city;
    if (c != _city) {
      _city = c;
      refresh();
    }
  }

  Future<void> refresh() async {
    final city = cities[(_city ?? 0).clamp(0, cities.length - 1)];
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${city.lat}'
      '&longitude=${city.lon}&current=temperature_2m,weather_code'
      '&hourly=temperature_2m,weather_code'
      '&daily=temperature_2m_max,temperature_2m_min'
      '&timezone=auto&forecast_days=2',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final res = await (await client.getUrl(
        url,
      )).close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;
      final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
      final cur = j['current'] as Map;
      final hourly = j['hourly'] as Map;
      final daily = j['daily'] as Map;
      final now = DateTime.parse(cur['time'] as String);
      final times = (hourly['time'] as List).cast<String>();
      final temps = (hourly['temperature_2m'] as List);
      final codes = (hourly['weather_code'] as List);
      final hours = <HourWeather>[];
      for (var i = 0; i < times.length && hours.length < 6; i++) {
        final t = DateTime.parse(times[i]);
        if (t.isBefore(now.subtract(const Duration(minutes: 59)))) continue;
        hours.add(
          HourWeather(
            t.hour,
            (temps[i] as num).toDouble(),
            (codes[i] as num).toInt(),
          ),
        );
      }
      weather.value = Weather(
        city: city.name,
        temp: (cur['temperature_2m'] as num).toDouble(),
        code: (cur['weather_code'] as num).toInt(),
        max: ((daily['temperature_2m_max'] as List).first as num).toDouble(),
        min: ((daily['temperature_2m_min'] as List).first as num).toDouble(),
        hours: hours,
      );
    } catch (_) {
      // Internet yo‘q — eski ma’lumot qoladi.
    } finally {
      client.close(force: true);
    }
  }
}
