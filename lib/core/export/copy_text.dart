import 'dart:async';

import 'package:flutter/services.dart';

/// Copies [text] to the clipboard. Returns false when the platform refused
/// or did not answer, which a browser does when it withholds clipboard
/// access, so the caller can say so instead of claiming success.
Future<bool> copyText(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text))
        .timeout(const Duration(seconds: 3));
    return true;
  } catch (_) {
    return false;
  }
}
