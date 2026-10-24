import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../app_version.dart';
import 'prefs.dart';

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class InstalledVersion {
  final String version;
  final int versionCode;
  const InstalledVersion({required this.version, required this.versionCode});
}

class UpdateInfo {
  final String version;
  final int versionCode;
  final Uri url;
  final int size;
  final List<String> notes;
  final String? publishedAt;
  final bool force;

  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.url,
    this.size = 0,
    this.notes = const [],
    this.publishedAt,
    this.force = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, {Uri? baseUri}) {
    final version = (json['version'] ?? json['versionName'] ?? '')
        .toString()
        .trim();
    if (version.isEmpty) throw const FormatException('缺少版本号');

    final rawUrl = (json['url'] ?? json['apk'] ?? json['apkUrl'] ?? '')
        .toString()
        .trim();
    if (rawUrl.isEmpty) throw const FormatException('缺少安装包地址');
    var url = Uri.parse(rawUrl);
    if (!url.hasScheme && baseUri != null) url = baseUri.resolveUri(url);
    if (url.scheme.toLowerCase() != 'https') {
      throw const FormatException('安装包地址必须使用 HTTPS');
    }

    final notes = <String>[];
    final rawNotes = json['notes'] ?? json['changelog'] ?? json['changes'];
    if (rawNotes is List) {
      for (final item in rawNotes) {
        final text = item.toString().trim();
        if (text.isNotEmpty) notes.add(text);
      }
    } else if (rawNotes is String) {
      for (final line in rawNotes.split(RegExp(r'\r?\n'))) {
        final text = line.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim();
        if (text.isNotEmpty) notes.add(text);
      }
    }

    final published = (json['publishedAt'] ?? json['date'] ?? '')
        .toString()
        .trim();
    final code =
        _asInt(json['versionCode'] ?? json['buildNumber']) ??
        versionCodeOf(version);

    return UpdateInfo(
      version: version,
      versionCode: code,
      url: url,
      size: _asInt(json['size']) ?? 0,
      notes: notes,
      publishedAt: published.isEmpty ? null : published,
      force: json['force'] == true || json['mandatory'] == true,
    );
  }

  /// 从 OBS 的 ListBucketResult 中挑出最新正式包。
  /// update.json 还没上传时作为兜底，保证新 APK 上传后即可被检查到。
  static UpdateInfo? latestFromListing(String xml, {required Uri baseUri}) {
    UpdateInfo? latest;
    final blocks = RegExp(
      r'<Contents>([\s\S]*?)</Contents>',
      caseSensitive: false,
    ).allMatches(xml);
    for (final block in blocks) {
      final body = block.group(1) ?? '';
      final key = RegExp(
        r'<Key>([^<]+)</Key>',
        caseSensitive: false,
      ).firstMatch(body)?.group(1);
      if (key == null) continue;
      final name = RegExp(
        r'^APK/Citro-v(\d+)\.(\d+)\.(\d+)-release\.apk$',
        caseSensitive: false,
      ).firstMatch(key);
      if (name == null) continue;

      final version = '${name.group(1)}.${name.group(2)}.${name.group(3)}';
      final code = versionCodeOf(version);
      final size =
          int.tryParse(
            RegExp(
                  r'<Size>(\d+)</Size>',
                  caseSensitive: false,
                ).firstMatch(body)?.group(1) ??
                '',
          ) ??
          0;
      final modified = RegExp(
        r'<LastModified>([^<]+)</LastModified>',
        caseSensitive: false,
      ).firstMatch(body)?.group(1);
      final info = UpdateInfo(
        version: version,
        versionCode: code,
        url: baseUri.resolve('/$key'),
        size: size,
        publishedAt: modified != null && modified.length >= 10
            ? modified.substring(0, 10)
            : null,
      );
      if (latest == null || info.versionCode > latest.versionCode) {
        latest = info;
      }
    }
    return latest;
  }

  bool isNewerThan(InstalledVersion installed) {
    if (versionCode > 0 && installed.versionCode > 0) {
      if (versionCode != installed.versionCode) {
        return versionCode > installed.versionCode;
      }
      return compareVersions(version, installed.version) > 0;
    }
    return compareVersions(version, installed.version) > 0;
  }

  String get fileName {
    final last = url.pathSegments.isEmpty ? '' : url.pathSegments.last;
    final cleaned = last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.toLowerCase().endsWith('.apk') && cleaned.length > 4) {
      return cleaned;
    }
    final safeVersion = version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'Citro-v$safeVersion.apk';
  }

  static int versionCodeOf(String version) {
    final match = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)')
        .firstMatch(version.trim());
    if (match == null) return 0;
    return int.parse(match.group(1)!) * 1000 +
        int.parse(match.group(2)!) * 100 +
        int.parse(match.group(3)!);
  }

  static int compareVersions(String a, String b) {
    final pa = _versionParts(a);
    final pb = _versionParts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final match = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)')
        .firstMatch(version.trim());
    if (match == null) return const [];
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

class UpdateService {
  static const String defaultManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://obs.chimu-claw.xyz/APK/update.json',
  );
  static const String _defaultListingUrl =
      'https://obs.chimu-claw.xyz/?prefix=APK/&max-keys=1000';

  final http.Client _client;
  final Uri manifestUri;
  final Uri listingUri;

  UpdateService({http.Client? client, Uri? manifestUri, Uri? listingUri})
    : _client = client ?? http.Client(),
      manifestUri = manifestUri ?? Uri.parse(defaultManifestUrl),
      listingUri = listingUri ?? Uri.parse(_defaultListingUrl);

  static Future<InstalledVersion>? _installed;

  static Future<InstalledVersion> installedVersion() =>
      _installed ??= _loadInstalledVersion();

  static void resetInstalledVersionCache() => _installed = null;

  static Future<InstalledVersion> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        return InstalledVersion(
          version: version,
          versionCode:
              int.tryParse(info.buildNumber.trim()) ??
              UpdateInfo.versionCodeOf(version),
        );
      }
    } catch (_) {}
    return InstalledVersion(
      version: kCitroVersion,
      versionCode: UpdateInfo.versionCodeOf(kCitroVersion),
    );
  }

  /// 先读 update.json（可带更新说明/强制更新），404 或格式错误时回退到
  /// OBS 的 APK 列表，避免新增一个文件之前更新功能完全不可用。
  Future<UpdateInfo?> fetchLatest() async {
    final fromManifest = await _fetchManifest();
    if (fromManifest != null) return fromManifest;
    return _fetchListing();
  }

  Future<UpdateInfo?> _fetchManifest() async {
    try {
      final res = await _client
          .get(manifestUri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      if (res.bodyBytes.length > 512 * 1024) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return null;
      return UpdateInfo.fromJson(
        Map<String, dynamic>.from(decoded),
        baseUri: manifestUri,
      );
    } catch (_) {
      return null;
    }
  }

  Future<UpdateInfo?> _fetchListing() async {
    http.Response res;
    try {
      res = await _client
          .get(listingUri, headers: const {'Accept': 'application/xml'})
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const UpdateException('检查更新超时，请稍后再试');
    } catch (_) {
      throw const UpdateException('检查更新失败，请检查网络');
    }
    if (res.statusCode != 200) {
      throw UpdateException('检查更新失败（${res.statusCode}）');
    }
    if (res.bodyBytes.length > 2 * 1024 * 1024) {
      throw const UpdateException('更新信息异常，请稍后再试');
    }
    return UpdateInfo.latestFromListing(
      utf8.decode(res.bodyBytes),
      baseUri: listingUri,
    );
  }

  void close() => _client.close();
}

class UpdateDownloader {
  final http.Client client;
  final Directory directory;

  const UpdateDownloader({required this.client, required this.directory});

  Future<File> download(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/${info.fileName}');

    if (info.size > 0 &&
        await file.exists() &&
        await file.length() == info.size) {
      onProgress?.call(info.size, info.size);
      return file;
    }

    await for (final entity in directory.list()) {
      if (entity is File && entity.path != file.path) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    final request = http.Request('GET', info.url);
    http.StreamedResponse response;
    try {
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const UpdateException('下载超时，请重试');
    } catch (_) {
      throw const UpdateException('下载失败，请检查网络');
    }
    if (response.statusCode != 200) {
      throw UpdateException('下载失败（${response.statusCode}）');
    }

    final total = response.contentLength ?? info.size;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } on TimeoutException {
      await _discard(sink, file);
      throw const UpdateException('下载超时，请重试');
    } catch (e) {
      await _discard(sink, file);
      if (e is UpdateException) rethrow;
      throw const UpdateException('下载失败，请检查网络与存储空间');
    }

    final expected = info.size > 0 ? info.size : total;
    if (expected > 0 && received != expected) {
      try {
        await file.delete();
      } catch (_) {}
      throw const UpdateException('安装包不完整，请重试');
    }
    return file;
  }

  Future<void> _discard(IOSink sink, File file) async {
    try {
      await sink.close();
    } catch (_) {}
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

enum InstallStatus { started, permission, failed }

class InstallResult {
  final InstallStatus status;
  final String? message;
  const InstallResult(this.status, [this.message]);
}

class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('com.chimu.crew/updater');

  static Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openInstallSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<InstallResult> install(String path) async {
    if (!Platform.isAndroid) {
      return const InstallResult(InstallStatus.failed, '当前平台不支持应用内安装');
    }
    try {
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': path,
      });
      return switch (result) {
        'started' => const InstallResult(InstallStatus.started),
        'permission' => const InstallResult(InstallStatus.permission),
        _ => const InstallResult(InstallStatus.failed, '无法打开系统安装程序'),
      };
    } on PlatformException catch (e) {
      return InstallResult(
        InstallStatus.failed,
        e.message == null || e.message!.isEmpty ? '安装失败，请重试' : e.message!,
      );
    } catch (_) {
      return const InstallResult(InstallStatus.failed, '当前设备不支持应用内安装');
    }
  }
}

class UpdatePrefs {
  static const Duration autoCheckInterval = Duration(minutes: 30);

  static bool get shouldAutoCheck {
    final last = Prefs.getInt(PrefKeys.updateLastCheck);
    if (last <= 0) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - last >= autoCheckInterval.inMilliseconds;
  }

  static Future<void> markChecked() => Prefs.setInt(
    PrefKeys.updateLastCheck,
    DateTime.now().millisecondsSinceEpoch,
  );

  static int get skippedVersion => Prefs.getInt(PrefKeys.updateSkippedVersion);

  static Future<void> skip(int versionCode) =>
      Prefs.setInt(PrefKeys.updateSkippedVersion, versionCode);
}

Future<Directory> updateDownloadDirectory() async {
  final tmp = await getTemporaryDirectory();
  return Directory('${tmp.path}/updates');
}
