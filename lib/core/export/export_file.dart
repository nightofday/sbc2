import 'dart:convert';
import 'dart:typed_data';

import 'export_file_share.dart'
    if (dart.library.js_interop) 'export_file_web.dart'
    as platform;

/// True in the browser, where an export is saved to the downloads folder.
/// On Android and iOS an export opens the share sheet instead, so the file
/// can be saved, emailed or sent to Google Drive.
bool get exportSavesToDownloads => platform.exportSavesToDownloads;

/// The label for an export button on this platform.
String get exportCsvLabel =>
    exportSavesToDownloads ? 'Download CSV' : 'Share CSV';

/// The label for an Excel export button on this platform.
String get exportExcelLabel =>
    exportSavesToDownloads ? 'Download Excel' : 'Share Excel';

/// Exports [contents] as a file called [fileName]. Returns false when the
/// file could not be saved or the share sheet could not be opened.
Future<bool> exportTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/csv',
}) {
  // The byte-order mark makes Excel read the file as UTF-8, so ₱ and é
  // survive.
  return exportBytesFile(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode('\uFEFF$contents')),
    mimeType: mimeType,
  );
}

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
