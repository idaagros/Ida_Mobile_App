// lib/services/pdf_download_helper_web.dart
//
// Web implementation: there's no filesystem, so trigger a direct browser
// download via a Blob + temporary anchor element. This file is only
// compiled when dart.library.html is available (i.e. web builds).

import 'dart:html' as html;
import 'pdf_download_helper.dart' show PdfSaveResult;

Future<PdfSaveResult> savePdfBytes(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
  return const PdfSaveResult(isWeb: true);
}
