// lib/widgets/scan_review_sheet.dart
//
// Shared review UI for the "scan a handwritten list" OCR flow. Never
// applies anything automatically - every row starts pre-filled with
// ML Kit's best guess (text recognition) and FuzzyMatch's best guess
// (name matching), but the person must review and confirm/correct
// each one before anything is actually added, since handwriting OCR
// is genuinely unreliable compared to printed text.

import 'package:flutter/material.dart';
import '../services/ocr_helper.dart';
import '../services/fuzzy_match.dart';

class ScanEntry {
  final String rawLine;
  int? selectedWorkerId; // null = skip this line
  final TextEditingController amountCtrl;
  double matchScore; // 0.0-1.0, how confident the auto-match was

  ScanEntry({
    required this.rawLine,
    required this.selectedWorkerId,
    required String initialAmount,
    required this.matchScore,
  }) : amountCtrl = TextEditingController(text: initialAmount);

  void dispose() => amountCtrl.dispose();
}

class ScanReviewSheet extends StatefulWidget {
  final List<({String rawLine, String namePart, String? amount})> parsedLines;
  final List<Map<String, dynamic>> candidateWorkers;
  final Color idaGreen;
  // Callers use different key names for id/name in their worker maps
  // (e.g. 'id' vs 'worker_id') - these let the sheet stay generic.
  final int Function(Map<String, dynamic>) idOf;
  final String Function(Map<String, dynamic>) nameOf;
  final String title;

  const ScanReviewSheet({
    super.key,
    required this.parsedLines,
    required this.candidateWorkers,
    required this.idaGreen,
    required this.idOf,
    required this.nameOf,
    this.title = 'Review Scanned List',
  });

  @override
  State<ScanReviewSheet> createState() => _ScanReviewSheetState();
}

class _ScanReviewSheetState extends State<ScanReviewSheet> {
  static const idaDark = Color(0xFF1E4012);
  late List<ScanEntry> entries;
  // Tracks which worker IDs are already claimed by another row in
  // this same review, so two lines can't silently both get assigned
  // to the same worker without the person noticing.
  final Set<int> _claimedIds = {};

  @override
  void initState() {
    super.initState();
    entries = widget.parsedLines.map((p) {
      final match = FuzzyMatch.bestMatch(
          p.namePart, widget.candidateWorkers, widget.nameOf);
      // Confidence bar set deliberately conservative (0.55) given how
      // unreliable handwriting OCR is - below this, default to "no
      // match" and let the person pick manually rather than risk a
      // wrong auto-assignment going unnoticed.
      final autoMatch = (match != null && match.score >= 0.55)
          ? widget.idOf(match.candidate)
          : null;
      if (autoMatch != null) _claimedIds.add(autoMatch);
      return ScanEntry(
        rawLine: p.rawLine,
        selectedWorkerId: autoMatch,
        initialAmount: p.amount ?? '',
        matchScore: match?.score ?? 0.0,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final e in entries) e.dispose();
    super.dispose();
  }

  void _changeMatch(ScanEntry entry, int? newId) {
    setState(() {
      if (entry.selectedWorkerId != null) {
        _claimedIds.remove(entry.selectedWorkerId);
      }
      entry.selectedWorkerId = newId;
      if (newId != null) _claimedIds.add(newId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, color: idaDark)),
                  const SizedBox(height: 2),
                  Text(
                      '${entries.length} line${entries.length == 1 ? '' : 's'} found — check each match before confirming',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, i) => _entryCard(entries[i]),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, -2))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: widget.idaGreen,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(context, entries),
                child: Text(
                    'Confirm ${entries.where((e) => e.selectedWorkerId != null).length} of ${entries.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _entryCard(ScanEntry entry) {
    final lowConfidence = entry.matchScore < 0.55;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: entry.selectedWorkerId == null ? Colors.grey.shade50 : const Color(0xFFF4F7F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: lowConfidence && entry.selectedWorkerId == null
                ? Colors.orange.shade200
                : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.text_snippet_outlined, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Detected: "${entry.rawLine}"',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          value: entry.selectedWorkerId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
          ),
          hint: const Text('No match — skip this line', style: TextStyle(fontSize: 13)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Skip this line', style: TextStyle(fontSize: 13, color: Colors.grey))),
            ...widget.candidateWorkers.map((w) {
              final id = widget.idOf(w);
              final alreadyClaimedElsewhere =
                  _claimedIds.contains(id) && entry.selectedWorkerId != id;
              return DropdownMenuItem<int?>(
                value: id,
                enabled: !alreadyClaimedElsewhere,
                child: Text(
                    widget.nameOf(w) + (alreadyClaimedElsewhere ? ' (already matched above)' : ''),
                    style: TextStyle(fontSize: 13, color: alreadyClaimedElsewhere ? Colors.grey : Colors.black87)),
              );
            }),
          ],
          onChanged: (v) => _changeMatch(entry, v),
        ),
        if (lowConfidence && entry.selectedWorkerId == null) ...[
          const SizedBox(height: 4),
          Text('No confident match found — please pick manually',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: entry.amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Rate ₹',
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
          ),
        ),
      ]),
    );
  }
}
