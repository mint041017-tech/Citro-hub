import 'dart:typed_data';

import 'image_store_stub.dart'
    if (dart.library.io) 'image_store_io.dart'
    if (dart.library.html) 'image_store_web.dart'
    as impl;

/// 网络图片的本地磁盘缓存（Web 交给浏览器 HTTP 缓存，这里只做内存/磁盘）。
///
/// 图片 URL 由服务端生成且永不覆盖，缓存可以长期命中；内存里保留同一份
/// Uint8List 实例，保证 `MemoryImage` 相等、能复用 Flutter 的图片缓存。
class ImageStore {
  static const _memoryMax = 80;
  // HyperOS / MIUI 低内存机型会频繁触发 onTrimMemory；只按条数限流时，
  // 80 张原图仍可能占几十 MB，这里再加一道总字节上限。
  static const _memoryBytesMax = 24 << 20;
  static final Map<String, Uint8List> _memory = {};
  static int _memoryBytes = 0;

  /// 同步读取内存缓存。已加载过的图可以首帧直接出图，不必再等 Future。
  static Uint8List? peek(String url) => _memory[url];

  /// 系统内存紧张时由 App 主动清空（磁盘缓存不受影响）。
  static void clearMemory() {
    _memory.clear();
    _memoryBytes = 0;
  }

  static Future<Uint8List?> load(String url) async {
    if (url.isEmpty) return null;
    final hit = _memory[url];
    if (hit != null) return hit;
    final bytes = await impl.load(url);
    if (bytes == null || bytes.isEmpty) return null;
    _putMemory(url, bytes);
    return bytes;
  }

  /// 上传成功后直接把本地压缩图塞进缓存，详情页无需再等一次下载。
  static Future<void> put(String url, Uint8List bytes) async {
    if (url.isEmpty || bytes.isEmpty) return;
    _putMemory(url, bytes);
    await impl.save(url, bytes);
  }

  static void _putMemory(String url, Uint8List bytes) {
    final old = _memory.remove(url);
    if (old != null) _memoryBytes -= old.lengthInBytes;
    _memory[url] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while ((_memory.length > _memoryMax || _memoryBytes > _memoryBytesMax) &&
        _memory.isNotEmpty) {
      final first = _memory.keys.first;
      final removed = _memory.remove(first);
      _memoryBytes -= removed?.lengthInBytes ?? 0;
    }
  }
}
