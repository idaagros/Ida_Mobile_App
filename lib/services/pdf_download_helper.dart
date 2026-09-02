// lib/services/pdf_download_helper.dart
//
// Saves generated PDF bytes to the right place for the current platform
// and returns a result the UI can act on (open/share on mobile & desktop,
// or "already downloaded" on web).
//
// Web has no filesystem and no path_provider implementation, so this file
// picks between two platform-specific implementations at compile time via
// conditional imports — the standard Flutter pattern for this problem.

import 'pdf_download_helper_io.dart'
    if (dart.library.html) 'pdf_download_helper_web.dart' as impl;

class PdfSaveResult {
  final bool isWeb;
  final String? filePath; // populated on mobile/desktop, null on web
  const PdfSaveResult({required this.isWeb, this.filePath});
}

/// Saves [bytes] using [filename] and returns where/how it was saved.
/// On web this triggers a browser download immediately and returns
/// isWeb: true (there's no local file path to open/share).
/// On mobile/desktop this writes to the temp directory and returns the
/// file path so the caller can offer Open/Share actions.
Future<PdfSaveResult> savePdfBytes(List<int> bytes, String filename) {
  return impl.savePdfBytes(bytes, filename);
}
