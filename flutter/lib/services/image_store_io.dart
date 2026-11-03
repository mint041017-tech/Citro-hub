import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Directory? _dir;
bool _pruned = false;
final Map<String, Future<Uint8List?>> _pending = {};

Future<Directory?> _cacheDir() async {
  final cached = _dir;
  if (cached != null) return cached;
  try {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}img-cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    if (!_pruned) {
      _pruned = true;
      // 缓存目录会随浏览历史无限增长；启动后空闲时做一次 LRU 清理，
      // 避免文件数过多拖慢目录遍历与随机读。
      unawaited(_prune(dir));
    }
    return dir;
  } catch (_) {
    return null;
  }
}

Future<void> _prune(Directory dir) async {
  const maxBytes = 256 << 20;
  const maxAge = Duration(days: 60);
  try {
    final entries = <(File, DateTime, int)>[];
    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        entries.add((entity, stat.modified, stat.size));
        total += stat.size;
      } catch (_) {}
    }
    if (entries.isEmpty) return;
    // 新的在前：保留最近使用/写入的，超量或过期的最先删。
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    final cutoff = DateTime.now().subtract(maxAge);
    // 总量与新鲜度都达标时直接跳过，省掉一次目录级删除遍历。
    if (total <= maxBytes && entries.last.$2.isAfter(cutoff)) return;
    var kept = 0;
    for (final (file, modified, size) in entries) {
      final expired = modified.isBefore(cutoff);
      if (!expired && kept + size <= maxBytes) {
        kept += size;
        continue;
      }
      try {
        await file.delete();
      } catch (_) {}
    }
  } catch (_) {}
}

File _fileFor(Directory dir, String url) {
  final name = sha1.convert(utf8.encode(url)).toString();
  return File('${dir.path}${Platform.pathSeparator}$name.img');
}

/// 同一张图可能被列表和详情同时请求，合并成一次下载。
Future<Uint8List?> load(String url) {
  final inflight = _pending[url];
  if (inflight != null) return inflight;
  final future = _load(url);
  _pending[url] = future;
  future.whenComplete(() => _pending.remove(url));
  return future;
}

Future<Uint8List?> _load(String url) async {
  final dir = await _cacheDir();
  if (dir == null) return null;
  final file = _fileFor(dir, url);
  try {
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
      try {
        await file.delete();
      } catch (_) {}
    }
  } catch (_) {}
  try {
    final res = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    try {
      await file.writeAsBytes(res.bodyBytes, flush: false);
    } catch (_) {}
    return res.bodyBytes;
  } catch (_) {
    return null;
  }
}

Future<void> save(String url, Uint8List bytes) async {
  final dir = await _cacheDir();
  if (dir == null) return;
  try {
    await _fileFor(dir, url).writeAsBytes(bytes, flush: false);
  } catch (_) {}
}
