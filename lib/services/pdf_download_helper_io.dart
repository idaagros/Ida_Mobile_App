// lib/services/pdf_download_helper_io.dart
//
// Mobile/desktop implementation: write bytes to the temp directory using
// path_provider, return the file path so the UI can offer Open/Share.
// This file is only compiled when dart:html is NOT available (i.e. not web).

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'pdf_download_helper.dart' show PdfSaveResult;

Future<PdfSaveResult> savePdfBytes(List<int> bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);
  return PdfSaveResult(isWeb: false, filePath: file.path);
}
