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
  /// 浏览器定位需要 HTTPS + 用户授权，失败很常见；失败后同样退回 IP 定位。
  static Future<GeoLocation?> current() async {
    final device = await _fromDevice();
    if (device != null) return device;
    return _fromIp();
  }

  static Future<GeoLocation?> _fromDevice() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final city = await GeoLookup.cityFromCoords(
        position.latitude,
        position.longitude,
      );
      return GeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        city: city,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<GeoLocation?> _fromIp() async {
    try {
      final ip = await GeoLookup.fromIp();
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
}
