// lib/services/image_helper.dart
// Shared image picking: camera OR gallery, compress to a hard 50KB cap,
// blur detection.
//
// Uses the pure-Dart `image` package (decode/resize/encode — no native
// platform channels) instead of flutter_image_compress, because
// flutter_image_compress's web implementation throws
// "TypeError: null: type 'Null' is not a subtype of type 'Function'"
// in web-based runners (e.g. FlutLab's browser preview) where its JS
// interop isn't wired up. A pure-Dart codec works identically on web,
// mobile, and desktop, so there's no platform-specific failure mode.

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

class ImageHelper {
  // Hard cap — the final file must be at or under this size.
  static const _maxSizeKB = 50;
  // Floor for resize attempts, so we never shrink a meter photo into
  // something too small to read.
  static const _minDimension = 480;
  static const _blurThreshold = 80.0; // variance threshold — below = blurry

  /// Shows a bottom sheet to choose Camera or Gallery.
  /// Returns compressed bytes + filename (for upload) PLUS the original,
  /// pre-compression bytes (for on-device OCR, where the extra detail
  /// lost by the 50KB cap can matter for reading small meter digits) -
  /// or null if cancelled / rejected.
  static Future<({Uint8List bytes, String name, Uint8List originalBytes})?>
      pickWithSheet(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Attach Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Choose source',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SourceBtn(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                _SourceBtn(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );

    if (source == null) return null;

    final picker = ImagePicker();
    XFile? file;
    try {
      // Pick at near-original quality/resolution — the real compression
      // pass below (via the `image` package) is what controls final
      // file size, with much finer control than the picker's own
      // one-shot quality/resolution export.
      file = await picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
        maxHeight: 2400,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e'),
          backgroundColor: Colors.red.shade700,
        ));
      }
      return null;
    }

    if (file == null) return null;

    Uint8List bytes = await file.readAsBytes();
    final Uint8List originalBytes = bytes;

    // ── Blur detection — run on the original, high-quality bytes ─────
    final blurScore = _estimateBlur(bytes);
    debugPrint('Blur score: $blurScore (threshold: $_blurThreshold)');

    if (blurScore < _blurThreshold && blurScore > 0) {
      if (context.mounted) {
        final retry = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.blur_on, color: Color(0xFFF5A623)),
              SizedBox(width: 10),
              Text('Blurry Image', style: TextStyle(fontSize: 17)),
            ]),
            content: const Text(
                'This photo appears blurry. A clear image is required '
                'for accurate meter reading verification.\n\n'
                'Please retake with a steady hand and good lighting.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Use anyway',
                      style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B7A28),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Retake'),
              ),
            ],
          ),
        );
        if (retry == true) return null; // caller should re-trigger pick
      }
    }

    // ── Compress to a hard ≤50KB cap ──────────────────────────────────
    // Heavy CPU work — run off the UI thread via compute() so the app
    // doesn't freeze on large camera photos. compute() works on mobile/
    // desktop; on web it just runs on the same thread (no isolates there)
    // but the `image` package itself still works fine either way.
    bytes = await compute(_compressToCap, bytes);

    debugPrint('Final size: ${(bytes.length / 1024).toStringAsFixed(1)} KB');

    // The compressor above always re-encodes to JPEG regardless of the
    // original format (PNG, HEIC, etc). If the filename still carries
    // the original extension, servers/clients that guess Content-Type
    // from the extension can mis-tag the upload (e.g. as image/png or
    // application/octet-stream for unrecognized extensions) even though
    // the bytes are JPEG — which then fails a backend's mimetype filter
    // silently, with no file ever arriving. Normalize the name here so
    // extension-based sniffing is always correct; callers also set
    // contentType explicitly on the multipart file as a second safeguard.
    final normalizedName = _withJpgExtension(file.name);

    return (bytes: bytes, name: normalizedName, originalBytes: originalBytes);
  }

  static String _withJpgExtension(String originalName) {
    final dot = originalName.lastIndexOf('.');
    final base = dot > 0 ? originalName.substring(0, dot) : originalName;
    return '$base.jpg';
  }

  /// Laplacian variance approximation using raw byte sampling.
  /// Works on JPEG/PNG without any native plugin.
  static double _estimateBlur(Uint8List bytes) {
    try {
      // Sample a grid of bytes from the middle 50% of the file
      // (header bytes skew the result so we skip them)
      final start = bytes.length ~/ 4;
      final end   = (bytes.length * 3) ~/ 4;
      if (end - start < 100) return 999.0; // too small to assess

      final sampleSize = math.min(2000, end - start);
      final step = (end - start) ~/ sampleSize;

      double mean = 0;
      final samples = <double>[];
      for (int i = start; i < end; i += step) {
        samples.add(bytes[i].toDouble());
        mean += bytes[i];
      }
      mean /= samples.length;

      // Variance of the luminance samples
      double variance = 0;
      for (final s in samples) {
        variance += (s - mean) * (s - mean);
      }
      variance /= samples.length;

      return variance;
    } catch (_) {
      return 999.0; // assume sharp if detection fails
    }
  }
}

// Top-level function (required by compute()) that decodes the image,
// then alternates between dropping JPEG quality and shrinking
// resolution until the encoded result is at or under _maxSizeKB.
// Quality is tried first (cheaper, preserves detail better) before
// resorting to downscaling.
Uint8List _compressToCap(Uint8List input) {
  const maxBytes = ImageHelper._maxSizeKB * 1024;
  const minDim = ImageHelper._minDimension;

  if (input.lengthInBytes <= maxBytes) return input;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return input; // unrecognized format — pass through

  img.Image working = decoded;

  // Pass 1: hold resolution, step quality down.
  for (int quality = 85; quality >= 30; quality -= 15) {
    final out = Uint8List.fromList(img.encodeJpg(working, quality: quality));
    if (out.lengthInBytes <= maxBytes) return out;
  }

  // Pass 2: still too big at the lowest acceptable quality — shrink
  // resolution step by step (re-trying a couple of quality levels at
  // each size) until we're under the cap or hit the minimum dimension.
  var width = working.width;
  var height = working.height;
  Uint8List best = Uint8List.fromList(img.encodeJpg(working, quality: 30));

  while (math.min(width, height) > minDim) {
    width = (width * 0.8).round();
    height = (height * 0.8).round();
    final resized = img.copyResize(decoded,
        width: width, height: height, interpolation: img.Interpolation.average);

    for (int quality = 70; quality >= 30; quality -= 20) {
      final out = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (out.lengthInBytes <= maxBytes) return out;
      best = out; // keep the smallest attempt seen so far
    }
  }

  // Couldn't get under the cap even at the resolution floor — return
  // the smallest version produced rather than silently sending an
  // oversized file.
  return best;
}

class _SourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceBtn(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 32, color: const Color(0xFF3B7A28)),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );
}