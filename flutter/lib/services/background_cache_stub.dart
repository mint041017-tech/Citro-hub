import 'dart:typed_data';

/// Web 端没有 path_provider / dart:io：背景图交给浏览器 HTTP 缓存，
/// 内存缓存仍由 `_CitroBlendImageState` 负责。
Future<({int w, int h, int r, int g, int b})?> readMeta(String key) async =>
    null;

Future<Uint8List?> readBytes(String key) async => null;

Future<void> writeMeta(String key, int w, int h, int r, int g, int b) async {}

Future<void> writeBytes(String key, Uint8List bytes) async {}

Future<void> touch(String key) async {}
