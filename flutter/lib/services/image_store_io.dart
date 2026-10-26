import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

Directory? _dir;
final Map<String, Future<Uint8List?>> _pending = {};

Future<Directory?> _cacheDir() async {
  final cached = _dir;
  if (cached != null) return cached;
  try {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}img-cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  } catch (_) {
    return null;
  }
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
