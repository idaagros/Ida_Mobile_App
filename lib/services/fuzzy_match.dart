// lib/services/fuzzy_match.dart
//
// Small, self-contained fuzzy string matcher - written directly rather
// than pulling in a package dependency for this one narrow need
// (matching an OCR-read name against the known worker list), since a
// simple, readable implementation is easier to trust and adjust than
// an opaque third-party scoring function.

class FuzzyMatch {
  /// Levenshtein edit distance between two strings (case-insensitive).
  static int _distance(String a, String b) {
    a = a.toLowerCase();
    b = b.toLowerCase();
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1, // insertion
          prev[j] + 1, // deletion
          prev[j - 1] + cost, // substitution
        ].reduce((x, y) => x < y ? x : y);
      }
      for (int j = 0; j <= b.length; j++) prev[j] = curr[j];
    }
    return curr[b.length];
  }

  /// Similarity score from 0.0 (nothing alike) to 1.0 (identical),
  /// normalized by the longer string's length so short and long names
  /// are scored on a comparable scale.
  static double similarity(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (_distance(a, b) / maxLen);
  }

  /// Finds the best-matching candidate for [query] among [candidates],
  /// returning (candidate, score) or null if candidates is empty.
  /// Score is 0.0-1.0 similarity - callers should treat anything below
  /// roughly 0.5 as "no confident match" and let the user pick manually
  /// rather than silently accepting a weak guess.
  static ({T candidate, double score})? bestMatch<T>(
      String query, List<T> candidates, String Function(T) nameOf) {
    if (candidates.isEmpty) return null;
    T? best;
    double bestScore = -1;
    for (final c in candidates) {
      final score = similarity(query, nameOf(c));
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return (candidate: best as T, score: bestScore);
  }
}
