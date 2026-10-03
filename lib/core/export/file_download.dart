import 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart'
    as platform;

/// Whether this platform can save a file straight to the downloads folder.
/// True in the browser. On Android and iOS it needs a share or file plugin,
/// which the app does not include yet, so those fall back to copying.
bool get canDownloadFiles => platform.canDownloadFiles;

/// Saves [contents] as a file called [fileName]. Returns false when this
/// platform cannot save files.
bool downloadTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/csv',
}) {
  return platform.downloadTextFile(
    fileName: fileName,
    contents: contents,
    mimeType: mimeType,
  );
}
