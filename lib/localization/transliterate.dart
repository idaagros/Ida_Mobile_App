// lib/localization/transliterate.dart
//
// Roman → Devanagari phonetic TRANSLITERATION (not translation) —
// e.g. "Amar" → "अमर", "Weeding" → "विडींग". Purely for DISPLAY when
// the app is in Marathi; the underlying stored data (worker names,
// farm names, work types) is never modified anywhere by this.
//
// This is a rule-based, offline, no-network, no-cost converter — not
// a lookup against a dictionary or an AI transliteration service.
// That means it's instant and free, but it's a heuristic: it works
// well for common Indian names and simple English words, but won't
// always be perfect (English spelling is ambiguous about things like
// dental vs retroflex consonants, or long vs short vowels). Treat it
// as "close enough to read", not an authoritative spelling.
//
// Usage: wrap any display-only Text value with `tl(context, value)`.
// Never wrap values that get sent back to the server, used for
// search-matching, or compared against stored data — only what's
// shown on screen.

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════
// MANUAL CORRECTIONS — start here.
//
// If a name/word comes out wrong (or just not how you'd naturally
// spell it), add it below as `'exact english spelling': 'correct
// devanagari'`. This is checked FIRST, before the general phonetic
// algorithm, and matched case-insensitively but exactly (so it only
// affects that specific word — safe, won't change anything else).
//
// Workflow: switch the app to Marathi, look at a name, and if it's
// off, come here and add/edit a line. No other file needs touching.
//
// Multi-word values (e.g. "Arun Katekar") work too — either add the
// whole phrase as one entry, or add each word separately (the
// algorithm splits on whitespace and checks each word against this
// map individually, so per-word entries cover every combination).
const Map<String, String> _overrides = {
  // 'weeding': 'खुरपणी',        // example: use the actual Marathi word
  // 'harvesting': 'कापणी',      // instead of a phonetic guess
  // 'katekar': 'कातेकर',        // example: fix a surname's spelling
};
// ═══════════════════════════════════════════════════════════════════

/// Transliterates [text] to Devanagari if the app's current language is
/// Marathi; otherwise returns [text] unchanged. Safe to call on null by
/// passing '' — always returns a String.
String tl(BuildContext context, String? text) {
  if (text == null || text.isEmpty) return text ?? '';
  final isMarathi = Localizations.localeOf(context).languageCode == 'mr';
  if (!isMarathi) return text;
  return _transliterateWord(text);
}

/// Same underlying phonetic conversion as tl() above, but WITHOUT the
/// BuildContext/current-locale check - always converts, regardless of
/// what language the UI is currently displayed in. For matching a
/// handwritten Devanagari name against a Latin-script stored name
/// (OCR use case), not for display. Same accuracy caveats as tl()
/// apply: a phonetic heuristic, not a dictionary lookup.
String transliterateToDevanagari(String? text) {
  if (text == null || text.isEmpty) return text ?? '';
  return _transliterateWord(text);
}

// Longest-match-first tables. Order within each list matters — longer
// sequences must come before their prefixes (e.g. "chh" before "ch"
// before "c") or the shorter one would always win.
const List<_Rule> _vowelRules = [
  _Rule('aa', 'आ', 'ा'),
  _Rule('ee', 'ई', 'ी'),
  _Rule('ii', 'ई', 'ी'),
  _Rule('oo', 'ऊ', 'ू'),
  _Rule('ai', 'ऐ', 'ै'),
  _Rule('au', 'औ', 'ौ'),
  _Rule('a', 'अ', ''), // inherent vowel — matra is empty (implicit)
  _Rule('i', 'इ', 'ि'),
  _Rule('u', 'उ', 'ु'),
  _Rule('e', 'ए', 'े'),
  _Rule('o', 'ओ', 'ो'),
];

const List<_Rule> _consonantRules = [
  _Rule('chh', 'छ', null),
  _Rule('sh', 'श', null),
  _Rule('ch', 'च', null),
  _Rule('th', 'थ', null),
  _Rule('dh', 'ध', null),
  _Rule('bh', 'भ', null),
  _Rule('ph', 'फ', null),
  _Rule('kh', 'ख', null),
  _Rule('gh', 'घ', null),
  _Rule('jh', 'झ', null),
  _Rule('ng', 'ङ', null),
  _Rule('ny', 'ञ', null),
  _Rule('ks', 'क्ष', null),
  _Rule('k', 'क', null),
  _Rule('g', 'ग', null),
  _Rule('c', 'क', null),
  _Rule('j', 'ज', null),
  _Rule('t', 'त', null),
  _Rule('d', 'द', null),
  _Rule('n', 'न', null),
  _Rule('p', 'प', null),
  _Rule('b', 'ब', null),
  _Rule('f', 'फ', null),
  _Rule('m', 'म', null),
  _Rule('y', 'य', null),
  _Rule('r', 'र', null),
  _Rule('l', 'ल', null),
  _Rule('v', 'व', null),
  _Rule('w', 'व', null),
  _Rule('s', 'स', null),
  _Rule('h', 'ह', null),
  _Rule('x', 'क्ष', null),
  _Rule('z', 'झ', null),
  _Rule('q', 'क', null),
];

class _Rule {
  final String roman;
  final String
      independent; // standalone vowel glyph, or the consonant base glyph
  final String?
      matra; // dependent vowel sign (vowels only); null for consonants
  const _Rule(this.roman, this.independent, this.matra);
}

const String _virama = '्'; // halant — cancels a consonant's inherent 'a'

String _transliterateWord(String input) {
  // Check the whole phrase first (handles multi-word overrides like
  // "Arun Katekar" added as a single entry).
  final wholePhraseOverride = _overrides[input.trim().toLowerCase()];
  if (wholePhraseOverride != null) return wholePhraseOverride;

  final buffer = StringBuffer();
  // Process word-by-word so spacing/punctuation passes through untouched.
  final words = input.split(RegExp(r'(\s+)'));
  for (final chunk in words) {
    if (chunk.trim().isEmpty) {
      buffer.write(chunk);
      continue;
    }
    buffer.write(_transliterateSingleWord(chunk));
  }
  return buffer.toString();
}

String _transliterateSingleWord(String word) {
  // Per-word override — checked before the algorithm, exact
  // case-insensitive match only (so it never affects other words).
  final override = _overrides[word.toLowerCase()];
  if (override != null) return override;

  final lower = word.toLowerCase();
  final out = StringBuffer();
  int i = 0;
  bool pendingConsonant = false; // true if the last glyph written is a
  // consonant still carrying its (uncancelled) inherent 'a'

  while (i < lower.length) {
    final ch = lower[i];
    // Pass through anything non-alphabetic untouched (numbers,
    // punctuation, apostrophes in names, etc.) — also breaks any
    // pending consonant's inherent vowel state.
    if (!RegExp(r'[a-z]').hasMatch(ch)) {
      out.write(word[i]);
      pendingConsonant = false;
      i++;
      continue;
    }

    final vowelMatch = _longestMatch(lower, i, _vowelRules);
    if (vowelMatch != null) {
      if (pendingConsonant) {
        // Vowel follows a consonant — attach as a matra (or nothing,
        // for the inherent 'a').
        out.write(vowelMatch.matra ?? '');
      } else {
        // Vowel at word start or after another vowel — standalone glyph.
        out.write(vowelMatch.independent);
      }
      pendingConsonant = false;
      i += vowelMatch.roman.length;
      continue;
    }

    final consMatch = _longestMatch(lower, i, _consonantRules);
    if (consMatch != null) {
      if (pendingConsonant) {
        // Two consonants in a row with no vowel between them — cancel
        // the previous one's inherent 'a' with a virama to form a
        // conjunct, e.g. "rm" in "Amar" → wait, "Amar" is a-m-a-r (a
        // vowel separates them) so this only fires for genuine
        // clusters like "nd", "rt", "sk".
        out.write(_virama);
      }
      out.write(consMatch.independent);
      pendingConsonant = true;
      i += consMatch.roman.length;
      continue;
    }

    // Shouldn't normally happen (a-z always matches something above),
    // but fall back to passing the character through rather than
    // dropping it.
    out.write(word[i]);
    pendingConsonant = false;
    i++;
  }

  return out.toString();
}

_Rule? _longestMatch(String lower, int index, List<_Rule> rules) {
  for (final rule in rules) {
    if (index + rule.roman.length <= lower.length &&
        lower.substring(index, index + rule.roman.length) == rule.roman) {
      return rule;
    }
  }
  return null;
}
