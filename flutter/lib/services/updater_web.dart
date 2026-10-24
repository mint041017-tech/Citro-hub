import '../app_version.dart';

class InstalledVersion {
  final String version;
  final int versionCode;
  const InstalledVersion({required this.version, required this.versionCode});
}

class UpdateService {
  static Future<InstalledVersion> installedVersion() async {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(kCitroVersion);
    final code = match == null
        ? 0
        : int.parse(match.group(1)!) * 1000 +
              int.parse(match.group(2)!) * 100 +
              int.parse(match.group(3)!);
    return InstalledVersion(version: kCitroVersion, versionCode: code);
  }
}
