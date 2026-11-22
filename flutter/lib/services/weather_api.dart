import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 天气数据获取。
///
/// Open-Meteo 数据最全（7 天 + 24 小时），但它的 API 域名在部分网络下会被
/// 阻断（表现为 TLS 握手超时），于是再加一个 wttr.in 兜底：两者并发请求，
/// 谁先成功用谁。这样既能拿到完整数据，也不会因为单一数据源不可用就整块天气
/// 空白——「切了城市没反应」的观感就是这么来的。
class WeatherApi {
  static Future<WeatherNow> fetch({
    required double lat,
    required double lon,
    required String city,
  }) {
    return _firstSuccess([
      _openMeteo(lat: lat, lon: lon, city: city),
      _wttr(lat: lat, lon: lon, city: city),
    ]);
  }

  static Future<WeatherNow> _firstSuccess(List<Future<WeatherNow>> futures) {
    final completer = Completer<WeatherNow>();
    var pending = futures.length;
    for (final future in futures) {
      future
          .then((value) {
            if (!completer.isCompleted) completer.complete(value);
          })
          .catchError((Object error) {
            pending--;
            if (pending == 0 && !completer.isCompleted) {
              completer.completeError(error);
            }
          });
    }
    return completer.future;
  }

  static Future<WeatherNow> _openMeteo({
    required double lat,
    required double lon,
    required String city,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,wind_direction_10m',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset',
      'hourly': 'temperature_2m,weather_code,precipitation_probability',
      'timezone': 'Asia/Shanghai',
      'forecast_days': '7',
      'forecast_hours': '24',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('open-meteo ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final cur = Map<String, dynamic>.from(j['current'] as Map);
    final daily = Map<String, dynamic>.from(j['daily'] as Map);
    final hourlyRaw = j['hourly'] is Map
        ? Map<String, dynamic>.from(j['hourly'] as Map)
        : <String, dynamic>{};
    final hourlyTimes = (hourlyRaw['time'] as List?) ?? [];
    final hourly = <HourlyWeather>[];
    for (var i = 0; i < hourlyTimes.length; i++) {
      final time = DateTime.tryParse('${hourlyTimes[i]}');
      if (time == null) continue;
      hourly.add(
        HourlyWeather(
          time: time,
          code: _i((hourlyRaw['weather_code'] as List?)?[i]),
          temp: _d((hourlyRaw['temperature_2m'] as List?)?[i]),
          rain: _i((hourlyRaw['precipitation_probability'] as List?)?[i]),
        ),
      );
    }
    final dates = (daily['time'] as List?) ?? [];
    final days = <DailyWeather>[];
    for (var i = 0; i < dates.length; i++) {
      days.add(
        DailyWeather(
          date: DateTime.tryParse('${dates[i]}') ?? DateTime.now(),
          code: _i((daily['weather_code'] as List)[i]),
          max: _d((daily['temperature_2m_max'] as List)[i]),
          min: _d((daily['temperature_2m_min'] as List)[i]),
          rain: _i((daily['precipitation_probability_max'] as List?)?[i]),
          sunrise: DateTime.tryParse('${(daily['sunrise'] as List)[i]}'),
          sunset: DateTime.tryParse('${(daily['sunset'] as List)[i]}'),
        ),
      );
    }
    return WeatherNow(
      temp: _d(cur['temperature_2m']),
      feels: _d(cur['apparent_temperature']),
      humidity: _i(cur['relative_humidity_2m']),
      wind: _d(cur['wind_speed_10m']),
      windDir: _d(cur['wind_direction_10m']),
      code: _i(cur['weather_code']),
      city: city,
      updated: _clock(),
      daily: days,
      hourly: hourly,
    );
  }

  static Future<WeatherNow> _wttr({
    required double lat,
    required double lon,
    required String city,
  }) async {
    final uri = Uri.https(
      'wttr.in',
      '/${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}',
      {'format': 'j1', 'lang': 'zh'},
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('wttr ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final current = Map<String, dynamic>.from(
      (j['current_condition'] as List).first as Map,
    );
    final rawDays = (j['weather'] as List?) ?? const [];
    if (rawDays.isEmpty) throw Exception('wttr no forecast');

    final now = DateTime.now();
    final daily = <DailyWeather>[];
    for (final raw in rawDays) {
      final day = Map<String, dynamic>.from(raw as Map);
      final hours = ((day['hourly'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (hours.isEmpty) continue;
      // 取正午前后那一格代表全天；这样「今天」的天气描述和体感不会跑偏。
      final rep = hours.length > 4 ? hours[4] : hours.last;
      final astro = (day['astronomy'] as List?)?.isNotEmpty == true
          ? Map<String, dynamic>.from((day['astronomy'] as List).first as Map)
          : const <String, dynamic>{};
      final date = DateTime.tryParse('${day['date']}') ?? now;
      daily.add(
        DailyWeather(
          date: date,
          code: _wwoToWmo(_i(rep['weatherCode'])),
          max: _d(day['maxtempC']),
          min: _d(day['mintempC']),
          rain: _i(rep['chanceofrain']),
          sunrise: _parseAmPm('${astro['sunrise'] ?? ''}', date),
          sunset: _parseAmPm('${astro['sunset'] ?? ''}', date),
        ),
      );
    }

    final hourly = <HourlyWeather>[];
    for (final raw in rawDays) {
      final day = Map<String, dynamic>.from(raw as Map);
      final date = DateTime.tryParse('${day['date']}');
      if (date == null) continue;
      for (final rawHour in (day['hourly'] as List?) ?? const []) {
        final hour = Map<String, dynamic>.from(rawHour as Map);
        final time = DateTime(
          date.year,
          date.month,
          date.day,
          _i(hour['time']) ~/ 100,
        );
        // 从当前小时往后的 24 小时；3 小时一格，和首页的小时卡片对得上。
        if (time.isBefore(DateTime(now.year, now.month, now.day, now.hour))) {
          continue;
        }
        hourly.add(
          HourlyWeather(
            time: time,
            code: _wwoToWmo(_i(hour['weatherCode'])),
            temp: _d(hour['tempC']),
            rain: _i(hour['chanceofrain']),
          ),
        );
        if (hourly.length >= 24) break;
      }
      if (hourly.length >= 24) break;
    }

    return WeatherNow(
      temp: _d(current['temp_C']),
      feels: _d(current['FeelsLikeC']),
      humidity: _i(current['humidity']),
      wind: _d(current['windspeedKmph']),
      windDir: _d(current['winddirDegree']),
      code: _wwoToWmo(_i(current['weatherCode'])),
      city: city,
      updated: _clock(),
      daily: daily,
      hourly: hourly,
    );
  }

  /// World Weather Online（wttr.in 的天气代码）→ WMO 代码，
  /// 这样两套数据源都能复用同一份文案与图标表。
  static int _wwoToWmo(int code) {
    switch (code) {
      case 113:
        return 0;
      case 116:
        return 2;
      case 119:
      case 122:
        return 3;
      case 143:
      case 248:
        return 45;
      case 260:
        return 48;
      case 176:
      case 263:
      case 266:
      case 293:
        return 51;
      case 296:
        return 53;
      case 299:
      case 302:
      case 353:
        return 61;
      case 305:
      case 308:
      case 356:
      case 359:
        return 65;
      case 179:
      case 323:
      case 326:
      case 368:
        return 71;
      case 329:
      case 332:
      case 371:
        return 73;
      case 335:
      case 338:
        return 75;
      case 182:
      case 185:
      case 281:
      case 284:
      case 311:
      case 314:
      case 317:
      case 320:
      case 362:
      case 365:
        return 66;
      case 200:
      case 386:
      case 389:
      case 392:
      case 395:
        return 95;
      case 227:
      case 230:
        return 75;
      case 350:
      case 374:
      case 377:
        return 79;
      default:
        return code > 99 ? 3 : code;
    }
  }

  static DateTime? _parseAmPm(String raw, DateTime date) {
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final pm = raw.toUpperCase().contains('PM');
    if (pm && hour < 12) hour += 12;
    if (!pm && hour == 12) hour = 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static String _clock() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  static int _i(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }
}
