// lib/widgets/grouped_scan_review_sheet.dart
//
// Review UI for a handwritten list that GroupedScanParser split into
// sections (each with a detected Farm + Work Type header and the
// workers under it). Every section's header and every worker match
// stays fully editable before anything is created - confirming
// creates one task per section, pre-filled with its reviewed workers,
// never applied silently.

import 'package:flutter/material.dart';
import '../services/grouped_scan_parser.dart';
import 'scan_review_sheet.dart' show ScanEntry;

class ConfirmedSection {
  final int? farmId;
  final int? workTypeId;
  final List<ScanEntry> entries;
  ConfirmedSection({required this.farmId, required this.workTypeId, required this.entries});
}

class _EditableSection {
  int? farmId;
  int? workTypeId;
  String farmLabel;
  String workTypeLabel;
  final List<ScanEntry> entries;
  bool expanded;

  _EditableSection({
    required this.farmId,
    required this.workTypeId,
    required this.farmLabel,
    required this.workTypeLabel,
    required this.entries,
    this.expanded = true,
  });
}

class GroupedScanReviewSheet extends StatefulWidget {
  final List<ScanSection> sections;
  final List<String> unclassified;
  final List<Map<String, dynamic>> candidateWorkers;
  final List<Map<String, dynamic>> farms;
  final List<Map<String, dynamic>> workTypes;
  final Color idaGreen;
  final int Function(Map<String, dynamic>) workerIdOf;
  final String Function(Map<String, dynamic>) workerNameOf;
  // Same reasoning as the flat scan sheet - shows what confirming a
  // row with no OCR-read amount would actually apply, rather than
  // leaving the field looking blank/broken.
  final String? Function(Map<String, dynamic>)? fallbackRateOf;

  const GroupedScanReviewSheet({
    super.key,
    required this.sections,
    required this.unclassified,
    required this.candidateWorkers,
    required this.farms,
    required this.workTypes,
    required this.idaGreen,
    required this.workerIdOf,
    required this.workerNameOf,
    this.fallbackRateOf,
  });

  @override
  State<GroupedScanReviewSheet> createState() => _GroupedScanReviewSheetState();
}

class _GroupedScanReviewSheetState extends State<GroupedScanReviewSheet> {
  static const idaDark = Color(0xFF1E4012);
  late List<_EditableSection> sections;
  final Set<int> _claimedIds = {};

  @override
  void initState() {
    super.initState();
    sections = widget.sections.map((s) {
      final entries = s.entries.map((e) {
        if (e.selectedWorkerId != null) _claimedIds.add(e.selectedWorkerId!);
        String initialAmount = e.initialAmount;
        if (initialAmount.isEmpty && e.selectedWorkerId != null && widget.fallbackRateOf != null) {
          final worker = widget.candidateWorkers.firstWhere(
              (w) => widget.workerIdOf(w) == e.selectedWorkerId, orElse: () => {});
          if (worker.isNotEmpty) {
            initialAmount = widget.fallbackRateOf!(worker) ?? '';
          }
        }
        return ScanEntry(
          rawLine: e.rawLine,
          selectedWorkerId: e.selectedWorkerId,
          initialAmount: initialAmount,
          matchScore: e.matchScore,
        );
      }).toList();
      return _EditableSection(
        farmId: s.farmId,
        workTypeId: s.workTypeId,
        farmLabel: s.farmLabel,
        workTypeLabel: s.workTypeLabel,
        entries: entries,
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final s in sections) {
      for (final e in s.entries) e.dispose();
    }
    super.dispose();
  }

  void _changeMatch(ScanEntry entry, int? newId) {
    setState(() {
      if (entry.selectedWorkerId != null) _claimedIds.remove(entry.selectedWorkerId);
      entry.selectedWorkerId = newId;
      if (newId != null) {
        _claimedIds.add(newId);
        if (entry.amountCtrl.text.trim().isEmpty && widget.fallbackRateOf != null) {
          final worker = widget.candidateWorkers
              .firstWhere((w) => widget.workerIdOf(w) == newId, orElse: () => {});
          if (worker.isNotEmpty) {
            final fallback = widget.fallbackRateOf!(worker);
            if (fallback != null && fallback.isNotEmpty) entry.amountCtrl.text = fallback;
          }
        }
      }
    });
  }

  int get _confirmedCount =>
      sections.fold(0, (sum, s) => sum + s.entries.where((e) => e.selectedWorkerId != null).length);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
                  const Text('Review Scanned List',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: idaDark)),
                  const SizedBox(height: 2),
                  Text(
                      '${sections.length} task${sections.length == 1 ? '' : 's'} detected — check each Farm/Work Type and match before confirming',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                ...sections.map(_sectionCard),
                if (widget.unclassified.isNotEmpty) _unclassifiedCard(),
              ],
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
                onPressed: () {
                  final confirmed = sections
                      .map((s) => ConfirmedSection(farmId: s.farmId, workTypeId: s.workTypeId, entries: s.entries))
                      .toList();
                  Navigator.pop(context, confirmed);
                },
                child: Text('Confirm $_confirmedCount ${_confirmedCount == 1 ? 'worker' : 'workers'} across ${sections.length} task${sections.length == 1 ? '' : 's'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionCard(_EditableSection section) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E7D8)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => section.expanded = !section.expanded),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F2),
              borderRadius: BorderRadius.vertical(top: const Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(Icons.work_outline, size: 16, color: widget.idaGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${section.farmLabel} · ${section.workTypeLabel}  (${section.entries.length})',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Icon(section.expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ]),
          ),
        ),
        if (section.expanded)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: widget.farms.any((f) => f['id'] == section.farmId) ? section.farmId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Farm', border: OutlineInputBorder()),
                    items: widget.farms
                        .map<DropdownMenuItem<int>>((f) => DropdownMenuItem(
                            value: f['id'] as int, child: Text((f['name'] ?? '').toString(), style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      section.farmId = v;
                      section.farmLabel = widget.farms.firstWhere((f) => f['id'] == v, orElse: () => {})['name'] ?? '';
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: widget.workTypes.any((w) => w['id'] == section.workTypeId) ? section.workTypeId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true, labelText: 'Work Type', border: OutlineInputBorder()),
                    items: widget.workTypes
                        .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                            value: w['id'] as int, child: Text((w['name'] ?? '').toString(), style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() {
                      section.workTypeId = v;
                      section.workTypeLabel = widget.workTypes.firstWhere((w) => w['id'] == v, orElse: () => {})['name'] ?? '';
                    }),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              ...section.entries.map((e) => _entryRow(e)),
            ]),
          ),
      ]),
    );
  }

  Widget _entryRow(ScanEntry entry) {
    final lowConfidence = entry.matchScore < 0.55;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: entry.selectedWorkerId == null ? Colors.grey.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Detected: "${entry.rawLine}"',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        DropdownButtonFormField<int?>(
          value: entry.selectedWorkerId,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder()),
          hint: const Text('No match — skip this line', style: TextStyle(fontSize: 12)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('Skip this line', style: TextStyle(fontSize: 12, color: Colors.grey))),
            ...widget.candidateWorkers.map((w) {
              final id = widget.workerIdOf(w);
              final claimedElsewhere = _claimedIds.contains(id) && entry.selectedWorkerId != id;
              return DropdownMenuItem<int?>(
                value: id,
                enabled: !claimedElsewhere,
                child: Text(widget.workerNameOf(w) + (claimedElsewhere ? ' (already matched)' : ''),
                    style: TextStyle(fontSize: 12, color: claimedElsewhere ? Colors.grey : Colors.black87)),
              );
            }),
          ],
          onChanged: (v) => _changeMatch(entry, v),
        ),
        if (lowConfidence && entry.selectedWorkerId == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('No confident match — please pick manually',
                style: TextStyle(fontSize: 10.5, color: Colors.orange.shade700)),
          ),
        const SizedBox(height: 6),
        TextField(
          controller: entry.amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(isDense: true, labelText: 'Rate ₹', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder()),
        ),
      ]),
    );
  }

  Widget _unclassifiedCard() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text('${widget.unclassified.length} line${widget.unclassified.length == 1 ? '' : 's'} could not be classified',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
        ]),
        const SizedBox(height: 6),
        Text('These matched neither a Farm/Work Type nor a worker confidently, so they were left out entirely rather than guessed:',
            style: TextStyle(fontSize: 11.5, color: Colors.orange.shade700)),
        const SizedBox(height: 4),
        ...widget.unclassified.map((l) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• "$l"', style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900, fontStyle: FontStyle.italic)),
            )),
      ]),
    );
  }
}
