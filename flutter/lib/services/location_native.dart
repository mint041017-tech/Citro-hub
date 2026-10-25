import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class GeoLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String city;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
    this.city = '',
  });
}

class LocationService {
  static const MethodChannel _channel = MethodChannel(
    'com.chimu.crew/location',
  );

  static Future<GeoLocation?> current() async {
    if (Platform.isIOS) {
      try {
        return await _currentIos().timeout(const Duration(seconds: 20));
      } catch (_) {
        return null;
      }
    }
    if (Platform.isWindows) {
      try {
        return await _currentWindows().timeout(const Duration(seconds: 20));
      } catch (_) {
        return null;
      }
    }
    try {
      final map = await _channel
          .invokeMapMethod<String, dynamic>('getLocation')
          .timeout(const Duration(seconds: 30));
      if (map == null) return null;
      final lat = (map['latitude'] as num?)?.toDouble();
      final lon = (map['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return GeoLocation(
        latitude: lat,
        longitude: lon,
        accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
        city: (map['city'] as String?)?.trim() ?? '',
      );
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// iOS 使用系统 CLLocationManager（经 geolocator）与 CLGeocoder（经 geocoding），
  /// 避免再维护一套 Swift MethodChannel；Android 保留现有原生通道。
  static Future<GeoLocation?> _currentIos() async {
    return _currentWithGeolocator(useHttpGeocode: false);
  }

  /// Windows 走 geolocator_windows（系统位置服务）；geocoding 没有 Windows
  /// 实现，逆地理改用与 Web 相同的 BigDataCloud 接口。
  static Future<GeoLocation?> _currentWindows() async {
    return _currentWithGeolocator(useHttpGeocode: true);
  }

  static Future<GeoLocation?> _currentWithGeolocator({
    required bool useHttpGeocode,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      var city = '';
      if (useHttpGeocode) {
        city = await _reverseCity(pos.latitude, pos.longitude);
      } else {
        try {
          final places = await Geocoding(locale: const Locale('zh', 'CN'))
              .placemarkFromCoordinates(pos.latitude, pos.longitude);
          if (places.isNotEmpty) {
            final p = places.first;
            city = p.locality?.trim().isNotEmpty == true
                ? p.locality!.trim()
                : (p.subAdministrativeArea?.trim().isNotEmpty == true
                      ? p.subAdministrativeArea!.trim()
                      : (p.administrativeArea?.trim() ?? ''));
          }
        } catch (_) {}
      }
      return GeoLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        city: city,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String> _reverseCity(double lat, double lon) async {
    try {
      final uri = Uri.https(
        'api.bigdatacloud.net',
        '/data/reverse-geocode-client',
        {
          'latitude': lat.toString(),
          'longitude': lon.toString(),
          'localityLanguage': 'zh',
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return '';
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) return '';
      for (final key in const ['city', 'locality', 'principalSubdivision']) {
        final value = j[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return '';
  }
}
