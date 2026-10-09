import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

bool get exportSavesToDownloads => false;

Future<bool> exportBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  try {
    // Written to the app's temporary folder under its own name, so the file
    // the person saves or sends is called what the export is.
    final folder = await Directory.systemTemp.createTemp('export');
    final file = File('${folder.path}/$fileName');
    await file.writeAsBytes(bytes);

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
