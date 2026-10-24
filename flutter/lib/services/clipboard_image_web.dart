import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> copyImageToClipboard(Uint8List bytes) async {
  try {
    if (!web.ClipboardItem.supports('image/png')) return false;
    final blob = web.Blob(
      <web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final item = web.ClipboardItem(
      <String, web.Blob>{'image/png': blob}.jsify()! as JSObject,
    );
    await web.window.navigator.clipboard
        .write(<web.ClipboardItem>[item].toJS)
        .toDart;
    return true;
  } catch (_) {
    return false;
  }
}
