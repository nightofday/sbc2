import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get exportSavesToDownloads => true;

Future<bool> exportBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      // Text is UTF-8 with a byte-order mark; say so to the browser.
      web.BlobPropertyBag(
        type: mimeType.startsWith('text/')
            ? '$mimeType;charset=utf-8'
            : mimeType,
      ),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';

    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
