import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

Directory? _dir;
bool _pruned = false;

Future<Directory?> _cacheDir() async {
  final cached = _dir;
  if (cached != null) return cached;
  try {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}bg-cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    if (!_pruned) {
      _pruned = true;
      // 缓存会随时间堆积；启动后空闲时按 LRU + 总量 + 新鲜度清一次。
      unawaited(_prune(dir));
    }
    return dir;
  } catch (_) {
    return null;
  }
}

String _nameFor(String key) => sha1.convert(utf8.encode(key)).toString();

File _metaFile(Directory dir, String key) =>
    File('${dir.path}${Platform.pathSeparator}${_nameFor(key)}.meta');

File _bytesFile(Directory dir, String key) =>
    File('${dir.path}${Platform.pathSeparator}${_nameFor(key)}.bg');

Future<({int w, int h, int r, int g, int b})?> readMeta(String key) async {
  final dir = await _cacheDir();
  if (dir == null) return null;
  try {
    final file = _metaFile(dir, key);
    if (!await file.exists()) return null;
    final map = jsonDecode(await file.readAsString());
    if (map is! Map) return null;
    final w = map['w'];
    final h = map['h'];
    if (w is! int || h is! int || w <= 0 || h <= 0) return null;
    return (
      w: w,
      h: h,
      r: map['r'] is int ? map['r'] as int : 0,
      g: map['g'] is int ? map['g'] as int : 0,
      b: map['b'] is int ? map['b'] as int : 0,
    );
  } catch (_) {
    return null;
  }
}

Future<void> writeMeta(String key, int w, int h, int r, int g, int b) async {
  final dir = await _cacheDir();
  if (dir == null) return;
  try {
    await _metaFile(dir, key).writeAsString(
      jsonEncode({'w': w, 'h': h, 'r': r, 'g': g, 'b': b}),
      flush: true,
    );
  } catch (_) {
    // 系统可能清过缓存目录；置空后下次重建。
    _dir = null;
  }
}

Future<Uint8List?> readBytes(String key) async {
  final dir = await _cacheDir();
  if (dir == null) return null;
  try {
    final file = _bytesFile(dir, key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<void> writeBytes(String key, Uint8List bytes) async {
  if (bytes.isEmpty) return;
  final dir = await _cacheDir();
  if (dir == null) return;
  try {
    await _bytesFile(dir, key).writeAsBytes(bytes, flush: true);
  } catch (_) {
    _dir = null;
  }
}

Future<void> touch(String key) async {
  final dir = await _cacheDir();
  if (dir == null) return;
  try {
    final file = _metaFile(dir, key);
    if (await file.exists()) {
      await file.setLastModified(DateTime.now());
    }
  } catch (_) {}
}

/// LRU 清理：最多 48 个文件、48MB、30 天。超量或过期的从最旧的开始删。
///
/// 背景图总共只有几张（4 张时段图 + 少量卡面），正常远到不了上限；
/// 这道清理是防止用户长期换卡面后目录无限增长。
Future<void> _prune(Directory dir) async {
  const maxBytes = 48 << 20;
  const maxFiles = 48;
  const maxAge = Duration(days: 30);
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
    entries.sort((a, b) => b.$2.compareTo(a.$2));
    final cutoff = DateTime.now().subtract(maxAge);
    if (total <= maxBytes &&
        entries.length <= maxFiles &&
        entries.last.$2.isAfter(cutoff)) {
      return;
    }
    var kept = 0;
    for (var i = 0; i < entries.length; i++) {
      final (file, modified, size) = entries[i];
      final expired = modified.isBefore(cutoff) || i >= maxFiles;
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
