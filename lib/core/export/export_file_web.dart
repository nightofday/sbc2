import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get exportSavesToDownloads => true;

Future<bool> exportTextFile({
  required String fileName,
  required String contents,
  required String mimeType,
}) async {
  try {
    // The byte-order mark makes Excel read the file as UTF-8, so ₱ and é
    // survive.
    final blob = web.Blob(
      ['﻿$contents'.toJS].toJS,
      web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
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
