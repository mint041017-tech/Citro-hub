import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'location_geo.dart';

class GeoLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String city;

  /// 系统定位不可用时用 IP 兜底得到的位置：只保证城市级精度。
  final bool approximate;

  const GeoLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
    this.city = '',
    this.approximate = false,
  });
}

class LocationService {
  static const MethodChannel _channel = MethodChannel(
    'com.chimu.crew/location',
  );

  /// 先取系统定位，失败（无权限 / 服务关闭 / 超时）时退回 IP 定位。
  ///
  /// 桌面端经常拿不到系统定位（Windows 需要在系统设置里允许桌面应用访问位置），
  /// 以前直接返回 null，界面只能提示「定位失败」。IP 定位精度到城市级，
  /// 对天气场景足够。
  static Future<GeoLocation?> current() async {
    final device = await _fromDevice();
    if (device != null) return device;
    return _fromIp();
  }

  static Future<GeoLocation?> _fromDevice() async {
    try {
      if (Platform.isIOS) {
        return await _currentIos().timeout(const Duration(seconds: 20));
      }
      if (Platform.isWindows) {
        return await _currentWindows().timeout(const Duration(seconds: 20));
      }
      return await _currentAndroid().timeout(const Duration(seconds: 30));
    } catch (_) {
      return null;
    }
  }

  static Future<GeoLocation?> _fromIp() async {
    try {
      final ip = await GeoLookup.fromIp().timeout(
        const Duration(seconds: 8),
        onTimeout: () => null,
      );
      if (ip == null) return null;
      return GeoLocation(
        latitude: ip.latitude,
        longitude: ip.longitude,
        city: ip.city,
        approximate: true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Android 走原生通道：系统权限框也由原生侧处理，只回坐标。
  static Future<GeoLocation?> _currentAndroid() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'getLocation',
      );
      if (map == null) return null;
      final lat = (map['latitude'] as num?)?.toDouble();
      final lon = (map['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      // Geocoder 在部分机型/模拟器上会一直阻塞，城市名统一走 HTTP 逆地理。
      final nativeCity = GeoLookup.normalizeCity('${map['city'] ?? ''}');
      final city = nativeCity.isNotEmpty
          ? nativeCity
          : await GeoLookup.cityFromCoords(lat, lon);
      return GeoLocation(
        latitude: lat,
        longitude: lon,
        accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
        city: city,
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
      LocationPermission permission;
      try {
        permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
      } catch (_) {
        // 位置服务没运行时 checkPermission 可能直接抛错，走下面的定位尝试。
        permission = LocationPermission.denied;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = null;
      }
      // 室内 / 桌面端经常定位超时，退回系统缓存的上一次位置。
      pos ??= await Geolocator.getLastKnownPosition();
      if (pos == null) return null;

      var city = '';
      if (useHttpGeocode) {
        city = await GeoLookup.cityFromCoords(pos.latitude, pos.longitude);
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
        if (city.isEmpty) {
          city = await GeoLookup.cityFromCoords(pos.latitude, pos.longitude);
        }
      }
      return GeoLocation(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        city: GeoLookup.normalizeCity(city),
      );
    } catch (_) {
      return null;
    }
  }
}
