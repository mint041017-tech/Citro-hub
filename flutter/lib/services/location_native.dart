import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 12),
      );
      var city = '';
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
}
