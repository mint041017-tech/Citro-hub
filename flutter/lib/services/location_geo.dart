import 'dart:convert';

import 'package:http/http.dart' as http;

/// 不依赖平台插件的定位辅助：逆地理（坐标 → 城市名）与 IP 兜底定位。
///
/// 桌面端（Windows）的系统定位经常因为「定位服务未开启 / 桌面应用无权限」而
/// 直接失败，移动端也可能因为用户拒绝授权拿不到坐标。IP 兜底至少能给出城市级
/// 位置，天气按城市展示完全够用。
class GeoLookup {
  /// 坐标逆地理：返回城市名，失败返回空串。
  static Future<String> cityFromCoords(double lat, double lon) async {
    final j = await _bigDataCloud({
      'latitude': lat.toString(),
      'longitude': lon.toString(),
      'localityLanguage': 'zh',
    });
    if (j == null) return '';
    for (final key in const ['city', 'locality', 'principalSubdivision']) {
      final value = normalizeCity('${j[key] ?? ''}');
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// IP 定位：坐标 + 城市名，失败返回 null。
  static Future<IpLocation?> fromIp() async {
    final j = await _bigDataCloud({'localityLanguage': 'zh'});
    if (j == null) return null;
    final lat = (j['latitude'] as num?)?.toDouble();
    final lon = (j['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    if (lat == 0 && lon == 0) return null;
    var city = '';
    for (final key in const ['city', 'locality', 'principalSubdivision']) {
      final value = normalizeCity('${j[key] ?? ''}');
      if (value.isNotEmpty) {
        city = value;
        break;
      }
    }
    return IpLocation(latitude: lat, longitude: lon, city: city);
  }

  /// 「惠州市」→「惠州」、「北京市」→「北京」，和手动选城市的写法保持一致。
  static String normalizeCity(String raw) {
    var name = raw.trim();
    if (name.isEmpty) return '';
    for (final suffix in const ['特别行政区', '自治州', '地区', '市', '县']) {
      if (name.length > suffix.length + 1 && name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length);
        break;
      }
    }
    return name.trim();
  }

  static Future<Map?> _bigDataCloud(Map<String, String> query) async {
    try {
      final uri = Uri.https(
        'api.bigdatacloud.net',
        '/data/reverse-geocode-client',
        query,
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }
}

class IpLocation {
  final double latitude;
  final double longitude;
  final String city;

  const IpLocation({
    required this.latitude,
    required this.longitude,
    this.city = '',
  });
}
