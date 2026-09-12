// lib/services/ocr_helper.dart
//
// Shared on-device OCR wrapper around google_mlkit_text_recognition -
// free, runs entirely on the phone, no internet needed, no per-use
// cost. Confirmed directly: same ML Kit family as the already-working
// google_mlkit_face_detection dependency used for face login, so this
// should build the same way in this environment.
//
// Text Recognition v2 (what this package uses) is tuned for printed
// text - digital meter displays, printed labels - and is genuinely
// reliable there. It is NOT tuned for handwriting; results on
// handwritten notes are hit-or-miss depending on how neat the writing
// is. Every caller of this service must treat its output as a
// starting draft for the user to review/correct, never as a final,
// trusted value applied without confirmation.

import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrHelper {
  static final TextRecognizer _latinRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  // Marathi handwritten notes are genuine Devanagari script (confirmed
  // directly, not Romanized) - a completely different character set
  // from Latin, needing its own recognizer. ML Kit only recognizes
  // one script per TextRecognizer instance, so both run independently
  // on the same photo and results are merged, tagged by which one
  // produced them.
  //
  // NOTE: "devanagiri" below is spelled that way (with an "i") on
  // purpose - confirmed directly against the package's actual enum,
  // which misspells it that way itself (TextRecognitionScript.latin,
  // .chinese, .devanagiri, .japanese, .korean). The correct English
  // spelling is "Devanagari" - do not "fix" this to match, it will
  // fail to compile.
  static final TextRecognizer _devanagariRecognizer =
      TextRecognizer(script: TextRecognitionScript.devanagiri);

  /// Runs OCR on raw image bytes (JPEG/PNG) with BOTH the Latin and
  /// Devanagari recognizers, since a single handwritten list may mix
  /// English and Marathi names depending on who wrote which line.
  /// Each recognizer only picks up lines in its own script (the wrong
  /// recognizer generally returns nothing useful for the other
  /// script's text, rather than a plausible-looking wrong answer), so
  /// merging is safe. Each returned line is tagged with which
  /// recognizer produced it, since matching a Devanagari line against
  /// the stored (Latin-script) worker list needs an extra
  /// transliteration step that a Latin line does not.
  static Future<List<({String text, bool isDevanagari})>> recognizeLines(
      Uint8List imageBytes) async {
    String? tempPath;
    try {
      final dir = await getTemporaryDirectory();
      tempPath = '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(tempPath);
      await file.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(tempPath);
      final results = <({String text, bool isDevanagari})>[];

      final latinResult = await _latinRecognizer.processImage(inputImage);
      for (final block in latinResult.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) results.add((text: t, isDevanagari: false));
        }
      }

      final devResult = await _devanagariRecognizer.processImage(inputImage);
      for (final block in devResult.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) results.add((text: t, isDevanagari: true));
        }
      }

      return results;
    } catch (e) {
      // OCR is an assist, not a requirement - if it fails for any
      // reason (unsupported format, ML Kit model not ready yet on
      // first use, etc.) the caller should fall back to manual entry,
      // not surface a hard error.
      return [];
    } finally {
      if (tempPath != null) {
        try {
          await File(tempPath).delete();
        } catch (_) {
          // Best-effort cleanup - a leftover temp file is harmless.
        }
      }
    }
  }

  /// Meter-reading specific: takes the raw recognized lines and picks
  /// out the single most plausible numeric reading.
  ///
  /// Heuristic (confirmed reasonable for single-value digital meter
  /// displays, not multi-tariff displays with several numbers on
  /// screen at once): among all digit runs found across every line
  /// (allowing a single decimal point), take the LONGEST one - a
  /// meter reading is typically the largest number on the display,
  /// while stray digits (serial numbers fragments, tiny UI glyphs
  /// OCR misreads) tend to be shorter. Ties go to the first one found
  /// (top-to-bottom, matching how meter displays are usually framed
  /// with the reading as the prominent central number).
  static String? extractMeterReading(
      List<({String text, bool isDevanagari})> lines) {
    final digitRun = RegExp(r'\d+\.?\d*');
    String? best;
    for (final entry in lines) {
      for (final match in digitRun.allMatches(entry.text)) {
        final candidate = match.group(0)!;
        // Skip obviously-wrong single stray digits (likely noise, not
        // a meter reading) unless nothing better has been found yet.
        if (candidate.replaceAll('.', '').length < 2 && best != null) {
          continue;
        }
        if (best == null ||
            candidate.replaceAll('.', '').length >
                best!.replaceAll('.', '').length) {
          best = candidate;
        }
      }
    }
    return best;
  }

  /// For a handwritten worker list (name, optionally followed by an
  /// amount): splits each recognized line into a name part and an
  /// optional trailing number. Handles common handwritten separators
  /// (space, dash, colon) between the two. Returns one entry per
  /// non-empty line, with amount null if no number was found on that
  /// line - the caller (a review UI) fills that in manually in that
  /// case, it is never guessed.
  static List<
      ({
        String rawLine,
        String namePart,
        String? amount,
        bool isDevanagari
      })> parseNameAmountLines(List<({String text, bool isDevanagari})> lines) {
    final trailingNumber = RegExp(r'[\s\-:]*(\d+\.?\d*)\s*$');
    final entries = <({
      String rawLine,
      String namePart,
      String? amount,
      bool isDevanagari
    })>[];
    for (final lineEntry in lines) {
      final trimmed = lineEntry.text.trim();
      if (trimmed.isEmpty) continue;
      final match = trailingNumber.firstMatch(trimmed);
      if (match != null && match.start > 0) {
        final namePart = trimmed.substring(0, match.start).trim();
        final amount = match.group(1);
        if (namePart.isNotEmpty) {
          entries.add((
            rawLine: trimmed,
            namePart: namePart,
            amount: amount,
            isDevanagari: lineEntry.isDevanagari
          ));
          continue;
        }
      }
      // No trailing number found (or the whole line was just a
      // number, unlikely to be a name) - keep the raw line as the
      // name part with no amount, for manual review.
      entries.add((
        rawLine: trimmed,
        namePart: trimmed,
        amount: null,
        isDevanagari: lineEntry.isDevanagari
      ));
    }
    return entries;
  }

  static void dispose() {
    _latinRecognizer.close();
    _devanagariRecognizer.close();
  }
}
