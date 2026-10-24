import 'dart:convert';

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
  static Future<GeoLocation?> current() async {
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
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      var city = '';
      try {
        final uri = Uri.https(
          'api.bigdatacloud.net',
          '/data/reverse-geocode-client',
          {
            'latitude': position.latitude.toString(),
            'longitude': position.longitude.toString(),
            'localityLanguage': 'zh',
          },
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final j = jsonDecode(utf8.decode(res.bodyBytes));
          if (j is Map) {
            for (final key in const [
              'city',
              'locality',
              'principalSubdivision',
            ]) {
              final value = j[key]?.toString().trim() ?? '';
              if (value.isNotEmpty) {
                city = value;
                break;
              }
            }
          }
        }
      } catch (_) {
        // 逆地理失败不影响定位与天气，城市保持为空。
      }
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
}
