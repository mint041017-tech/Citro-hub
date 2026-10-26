import 'dart:typed_data';

/// Web 端交给浏览器 HTTP 缓存（服务端已设置 immutable），不再自己存一份。
Future<Uint8List?> load(String url) async => null;

Future<void> save(String url, Uint8List bytes) async {}
