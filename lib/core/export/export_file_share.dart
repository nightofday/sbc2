import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

bool get exportSavesToDownloads => false;

Future<bool> exportTextFile({
  required String fileName,
  required String contents,
  required String mimeType,
}) async {
  try {
    // Written to the app's temporary folder under its own name, so the file
    // the person saves or sends is called what the export is.
    final folder = await Directory.systemTemp.createTemp('export');
    final file = File('${folder.path}/$fileName');
    // The byte-order mark makes Excel read the file as UTF-8, so ₱ and é
    // survive.
    await file.writeAsBytes(utf8.encode('﻿$contents'));

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: fileName)],
        subject: fileName,
        title: fileName,
        // Required on iPad, where the share sheet is a popover.
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  } catch (_) {
    return false;
  }
}
