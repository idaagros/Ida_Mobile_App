// lib/services/grouped_scan_parser.dart
//
// For handwritten lists that are NOT a flat name+amount list, but a
// sequence of sections - a header line naming a Farm and/or Work Type
// (e.g. "कडुवाल्या वावरात निंदण" = weeding in Kaduwala's field),
// followed by the workers doing that work, then possibly another
// header, and so on.
//
// Confirmed directly: headers are identified by matching against the
// actual Farm Master / Work Type Master lists, NOT by a text pattern
// (no reliable punctuation/position signal exists) - and no farm or
// work type name coincides with any worker's name, so each line
// should cleanly fall into exactly one of the three categories.

import 'fuzzy_match.dart';
import '../localization/transliterate.dart';

class ScanWorkerEntry {
  final String rawLine;
  final int? selectedWorkerId; // null = no confident match
  final String initialAmount;
  final double matchScore;

  const ScanWorkerEntry({
    required this.rawLine,
    required this.selectedWorkerId,
    required this.initialAmount,
    required this.matchScore,
  });
}

class ScanSection {
  int? farmId;
  int? workTypeId;
  String farmLabel;
  String workTypeLabel;
  final List<ScanWorkerEntry> entries = [];
  // The header line that triggered this section, if any (the very
  // first section, before any header is seen, has none - it starts
  // as General/General per the confirmed fallback).
  String? headerLine;

  ScanSection({
    this.farmId,
    this.workTypeId,
    required this.farmLabel,
    required this.workTypeLabel,
    this.headerLine,
  });
}

class GroupedScanParser {
  // Higher bar than the 0.55 used for worker matching - misreading a
  // header as a worker (or vice versa) has a bigger downside than an
  // individual worker mismatch, since it affects every entry under
  // that section, not just one line.
  static const double _headerWordThreshold = 0.72;
  static const double _workerLineThreshold = 0.55;

  /// Splits a name into words for word-level matching against a
  /// header line - drops very short words (<3 chars) since they add
  /// false-positive risk without much matching value (e.g. "at", "in"
  /// equivalents in Marathi/English).
  static List<String> _significantWords(String text) => text
      .split(RegExp(r'[\s\(\)\-,]+'))
      .where((w) => w.trim().length >= 3)
      .toList();

  /// Best fuzzy score between any word in [lineWords] and any
  /// significant word of [candidateName] - handles multi-word Farm/
  /// Work Type names (e.g. "Badi Aakhar (Ekta Amba)") by checking
  /// each of their words independently against each line word,
  /// rather than comparing the whole phrase to the whole line (which
  /// would score poorly purely from length mismatch when the line
  /// has other words mixed in, like "in Kaduwala's field").
  static double _bestWordMatch(List<String> lineWords, String candidateName) {
    final candidateWords = _significantWords(candidateName);
    if (candidateWords.isEmpty || lineWords.isEmpty) return 0.0;
    double best = 0.0;
    for (final lw in lineWords) {
      for (final cw in candidateWords) {
        final score = FuzzyMatch.similarity(lw, cw);
        if (score > best) best = score;
      }
    }
    return best;
  }

  /// Runs the full parse: walks every OCR line in order, classifying
  /// each as a header (updates the running farm/work-type context) or
  /// a worker entry (added to whichever section is currently active).
  /// Lines that match neither confidently are dropped entirely from
  /// sections and returned separately for the person to look at -
  /// never silently guessed into a bucket.
  static ({List<ScanSection> sections, List<String> unclassified}) parse({
    required List<({String text, bool isDevanagari})> lines,
    required List<Map<String, dynamic>> farms,
    required List<Map<String, dynamic>> workTypes,
    required List<Map<String, dynamic>> workers,
    required int Function(Map<String, dynamic>) workerIdOf,
    required String Function(Map<String, dynamic>) workerNameOf,
    required int generalFarmId,
    required String generalFarmLabel,
    required int generalWorkTypeId,
    required String generalWorkTypeLabel,
  }) {
    final trailingNumber = RegExp(r'[\s\-:]*(\d+\.?\d*)\s*$');
    final sections = <ScanSection>[];
    final unclassified = <String>[];

    // Starts as General/General per the confirmed fallback - a list
    // that opens with worker names before any header line still has
    // somewhere sensible for them to land.
    ScanSection current = ScanSection(
      farmId: generalFarmId,
      workTypeId: generalWorkTypeId,
      farmLabel: generalFarmLabel,
      workTypeLabel: generalWorkTypeLabel,
    );
    sections.add(current);
    bool currentHasEntries = false;

    for (final lineEntry in lines) {
      final trimmed = lineEntry.text.trim();
      if (trimmed.isEmpty) continue;

      // Split off a trailing amount if present, same as the flat
      // parser - a header line normally has no amount, but this
      // isn't relied on as the classification signal (confirmed
      // directly: match against the masters instead).
      String namePart = trimmed;
      String? amount;
      final match = trailingNumber.firstMatch(trimmed);
      if (match != null && match.start > 0) {
        final candidateName = trimmed.substring(0, match.start).trim();
        if (candidateName.isNotEmpty) {
          namePart = candidateName;
          amount = match.group(1);
        }
      }

      final lineWords = _significantWords(namePart);

      // Word-level match against every farm and every work type.
      Map<String, dynamic>? bestFarm;
      double bestFarmScore = 0.0;
      for (final f in farms) {
        final name = (f['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final compareName =
            lineEntry.isDevanagari ? transliterateToDevanagari(name) : name;
        final score = _bestWordMatch(lineWords, compareName);
        if (score > bestFarmScore) {
          bestFarmScore = score;
          bestFarm = f;
        }
      }

      Map<String, dynamic>? bestWorkType;
      double bestWorkTypeScore = 0.0;
      for (final w in workTypes) {
        final name = (w['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final compareName =
            lineEntry.isDevanagari ? transliterateToDevanagari(name) : name;
        final score = _bestWordMatch(lineWords, compareName);
        if (score > bestWorkTypeScore) {
          bestWorkTypeScore = score;
          bestWorkType = w;
        }
      }

      final isHeaderCandidate = bestFarmScore >= _headerWordThreshold ||
          bestWorkTypeScore >= _headerWordThreshold;

      if (isHeaderCandidate) {
        // Starts a new section. Farm and/or Work Type get updated
        // from whichever matched - the other carries over from the
        // previous section (many real headers only name one of the
        // two, per the confirmed pattern), falling back to General
        // only if nothing has been set yet at all.
        final newFarmId = bestFarmScore >= _headerWordThreshold
            ? bestFarm!['id'] as int
            : current.farmId;
        final newFarmLabel = bestFarmScore >= _headerWordThreshold
            ? (bestFarm!['name'] ?? '').toString()
            : current.farmLabel;
        final newWorkTypeId = bestWorkTypeScore >= _headerWordThreshold
            ? bestWorkType!['id'] as int
            : current.workTypeId;
        final newWorkTypeLabel = bestWorkTypeScore >= _headerWordThreshold
            ? (bestWorkType!['name'] ?? '').toString()
            : current.workTypeLabel;

        // Only open a fresh section if the previous one actually has
        // entries - otherwise two header lines in a row (or a header
        // right at the very start) would leave a pointless empty
        // section behind.
        if (currentHasEntries) {
          current = ScanSection(
            farmId: newFarmId,
            farmLabel: newFarmLabel,
            workTypeId: newWorkTypeId,
            workTypeLabel: newWorkTypeLabel,
            headerLine: trimmed,
          );
          sections.add(current);
          currentHasEntries = false;
        } else {
          current.farmId = newFarmId;
          current.farmLabel = newFarmLabel;
          current.workTypeId = newWorkTypeId;
          current.workTypeLabel = newWorkTypeLabel;
          current.headerLine = trimmed;
        }
        continue;
      }

      // Not a confident header - try matching as a worker instead.
      final nameOfForMatching = lineEntry.isDevanagari
          ? (Map<String, dynamic> w) =>
              transliterateToDevanagari(workerNameOf(w))
          : workerNameOf;
      final workerMatch =
          FuzzyMatch.bestMatch(namePart, workers, nameOfForMatching);

      if (workerMatch != null && workerMatch.score >= _workerLineThreshold) {
        current.entries.add(ScanWorkerEntry(
          rawLine: trimmed,
          selectedWorkerId: workerIdOf(workerMatch.candidate),
          initialAmount: amount ?? '',
          matchScore: workerMatch.score,
        ));
        currentHasEntries = true;
      } else if (bestFarmScore > 0.4 ||
          bestWorkTypeScore > 0.4 ||
          workerMatch != null) {
        // Weak signal on more than one front - genuinely ambiguous,
        // not confidently a header OR confidently a worker. Left for
        // the person to sort out rather than guessed.
        unclassified.add(trimmed);
      } else {
        // No meaningful match anywhere - still surfaced, but as a
        // plain "unmatched worker line" the person can assign
        // manually, same as the flat scan's behaviour.
        current.entries.add(ScanWorkerEntry(
          rawLine: trimmed,
          selectedWorkerId: null,
          initialAmount: amount ?? '',
          matchScore: 0.0,
        ));
        currentHasEntries = true;
      }
    }

    // Drop any section that ended up with zero entries (e.g. a
    // trailing header line with nothing under it).
    sections.removeWhere((s) => s.entries.isEmpty);

    return (sections: sections, unclassified: unclassified);
  }
}
