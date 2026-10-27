import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'platform.dart' as platform;

class MediaService {
  static final ImagePicker _picker = ImagePicker();
  static Future<void> _compressQueue = Future<void>.value();

  static Future<String?> pickImageData({
    bool camera = false,
    int maxWidth = 1400,
    int quality = 82,
  }) async {
    final bytes = await pickImageBytes(
      camera: camera,
      maxWidth: maxWidth,
      quality: quality,
    );
    if (bytes == null) return null;
    return dataUrl(bytes);
  }

  static Future<Uint8List?> pickImageBytes({
    bool camera = false,
    int maxWidth = 2400,
    int quality = 92,
  }) async {
    // image_picker 的 Windows 实现没有相机，直接复用文件选择器，
    // 保持「拍照」按钮可用，而不是抛 UnimplementedError。
    final useCamera = camera && !platform.isWindows;
    final file = await _picker.pickImage(
      source: useCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxWidth.toDouble(),
      imageQuality: quality,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  /// 原版食谱图压缩：长边压到 maxDim → 质量按 12 递减到 40 →
  /// 仍超过 350KB 就把边长乘 0.75（长边下限 640）重来，统一输出 JPEG。
  static Future<Uint8List> compressCookImage(
    Uint8List bytes, {
    int maxDim = 1600,
    int quality = 82,
    int limit = 350 * 1024,
  }) {
    // 连续选多张步骤图时串行压缩，避免多个解码 isolate 同时把峰值内存顶满。
    final task = _compressQueue.then(
      (_) => compute(_compressCookImageTask, <String, Object>{
        'bytes': bytes,
        'maxDim': maxDim,
        'quality': quality,
        'limit': limit,
      }),
    );
    _compressQueue = task.then((_) {}, onError: (_) {});
    return task;
  }

  static String dataUrl(Uint8List bytes, {String mime = 'image/jpeg'}) =>
      'data:$mime;base64,${base64Encode(bytes)}';
}

Uint8List _compressCookImageTask(Map<String, Object> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxDim = args['maxDim'] as int;
  final baseQuality = args['quality'] as int;
  final limit = args['limit'] as int;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('图片读取失败');
  final source = img.bakeOrientation(decoded);
  final sourceLong = math.max(source.width, source.height);

  var scale = math.min(1.0, maxDim / sourceLong);
  var quality = baseQuality;
  while (true) {
    final w = math.max(1, (source.width * scale).round());
    final h = math.max(1, (source.height * scale).round());
    final resized = (w == source.width && h == source.height)
        ? source
        : img.copyResize(
            source,
            width: w,
            height: h,
            interpolation: img.Interpolation.linear,
          );
    final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    if (out.length <= limit) return out;
    if (quality > 40) {
      quality = math.max(40, quality - 12);
      continue;
    }
    if (sourceLong * scale <= 640) return out;
    scale *= .75;
    quality = baseQuality;
  }
}
