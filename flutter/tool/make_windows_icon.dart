import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 从 assets/images/logo.webp 生成 Windows 多尺寸 ICO。
/// 用法：dart run tool/make_windows_icon.dart
void main() {
  final source = img.decodeImage(
    File('assets/images/logo.webp').readAsBytesSync(),
  );
  if (source == null) {
    stderr.writeln('无法读取 assets/images/logo.webp');
    exit(1);
  }
  const sizes = <int>[16, 24, 32, 48, 64, 128, 256];
  final frames = <_IcoFrame>[];
  for (final size in sizes) {
    final resized = img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    frames.add(_IcoFrame(size, Uint8List.fromList(img.encodePng(resized))));
  }
  final out = File('windows/runner/resources/app_icon.ico');
  out.writeAsBytesSync(_buildIco(frames));
  stdout.writeln('已生成 ${out.path} (${sizes.join(' / ')})');
}

class _IcoFrame {
  final int size;
  final Uint8List png;
  const _IcoFrame(this.size, this.png);
}

Uint8List _buildIco(List<_IcoFrame> frames) {
  const headerSize = 6;
  const entrySize = 16;
  var offset = headerSize + entrySize * frames.length;
  final header = ByteData(headerSize + entrySize * frames.length);
  header.setUint16(0, 0, Endian.little);
  header.setUint16(2, 1, Endian.little);
  header.setUint16(4, frames.length, Endian.little);
  for (var i = 0; i < frames.length; i++) {
    final frame = frames[i];
    final base = headerSize + i * entrySize;
    header.setUint8(base, frame.size >= 256 ? 0 : frame.size);
    header.setUint8(base + 1, frame.size >= 256 ? 0 : frame.size);
    header.setUint8(base + 2, 0);
    header.setUint8(base + 3, 0);
    header.setUint16(base + 4, 1, Endian.little);
    header.setUint16(base + 6, 32, Endian.little);
    header.setUint32(base + 8, frame.png.length, Endian.little);
    header.setUint32(base + 12, offset, Endian.little);
    offset += frame.png.length;
  }
  final builder = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final frame in frames) {
    builder.add(frame.png);
  }
  return builder.toBytes();
}
