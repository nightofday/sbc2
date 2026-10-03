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

/// Exports [contents] as a file called [fileName]. Returns false when the
/// file could not be saved or the share sheet could not be opened.
Future<bool> exportTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/csv',
}) {
  return platform.exportTextFile(
    fileName: fileName,
    contents: contents,
    mimeType: mimeType,
  );
}
