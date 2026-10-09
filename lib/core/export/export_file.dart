import 'dart:typed_data';

import 'export_file_share.dart'
    if (dart.library.js_interop) 'export_file_web.dart'
    as platform;

/// True in the browser, where an export is saved to the downloads folder.
/// On Android and iOS an export opens the share sheet instead, so the file
/// can be saved, emailed or sent to Google Drive.
bool get exportSavesToDownloads => platform.exportSavesToDownloads;

/// The label for an Excel export button on this platform.
String get exportExcelLabel =>
    exportSavesToDownloads ? 'Download Excel' : 'Share Excel';

/// Exports [bytes], such as an Excel workbook, as a file called [fileName].
Future<bool> exportBytesFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) {
  return platform.exportBytesFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
  );
}
