import 'dart:typed_data';

import 'background_cache_stub.dart'
    if (dart.library.io) 'background_cache_io.dart' as impl;

/// 首页背景图的磁盘缓存。
///
/// 只存两样东西：
/// - 元数据（宽高 + 底部提取色）：下次启动跳过解码，直接算出卡片区起点；
/// - 网络图的原始字节：下次启动不再走网络，直接 MemoryImage 上屏。
///
/// 键是资源地址（assets/... 或 https://...），文件名取 sha1。
/// Web 端走 [background_cache_stub.dart]，交给浏览器 HTTP 缓存。
class BackgroundCache {
  const BackgroundCache._();

  /// 返回 (宽, 高, 红, 绿, 蓝)；未命中或文件损坏时返回 null。
  static Future<({int w, int h, int r, int g, int b})?> readMeta(
    String key,
  ) => impl.readMeta(key);

  static Future<Uint8List?> readBytes(String key) => impl.readBytes(key);

  static Future<void> writeMeta(
    String key,
    int w,
    int h,
    int r,
    int g,
    int b,
  ) => impl.writeMeta(key, w, h, r, g, b);

  static Future<void> writeBytes(String key, Uint8List bytes) =>
      impl.writeBytes(key, bytes);

  /// 命中时刷新一次修改时间，作为 LRU 清理依据。
  static Future<void> touch(String key) => impl.touch(key);
}
