// lib/screens/review/review_queue_screen.dart
//
// Review submissions on the phone (Sep 2026) - the same checks as the
// website's Review submissions page (/admin/review):
//   - the photo the person took, full size on tap
//   - a plain-words verdict: normal, or "look closely" when the use per day
//     is more than 30% off the average of the last 30 entries (or the meter
//     went down, or more than 24 h a day)
//   - the entry before, the usual per day and range, a small chart and the
//     last 5 entries
//   - factory runs: the day on a 24-hour bar, the stops, compared with the
//     usual run and the machine hour meter
//   - maintenance "done": on time / early / late against the interval
// Approve & next opens the next entry. Return needs a reason; maintenance
// is approved or rejected. The older tabbed screen (AdminReviewScreen) is
// still in the menu for anything this one doesn't cover.
//
// API: GET /review/queue (?status=done for the last 14 days),
//      PATCH <module status path> { status, admin_note }

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../agronomy/agronomy_common.dart' show AgriApi;
import '../admin_review_screen.dart';
import 'review_text.dart';

const Color _green = Color(0xFF3B7A28);
const Color _dark = Color(0xFF1E3313);
const Color _bg = Color(0xFFF4F7F2);
const Color _border = Color(0xFFE0E7D8);
const Color _muted = Color(0xFF5F6A58);

// ── Queue ──────────────────────────────────────────────────────────────
class ReviewQueueScreen extends StatefulWidget {
  // module: 'electricity', 'factory', ... or 'maintenance' to open filtered.
  // openKey: 'module:id' to open that entry straight away, or
  // openDate: 'YYYY-MM-DD' to open that module's entry for the day.
  final String? module;
  final String? openKey;
  final String? openDate;
  const ReviewQueueScreen({super.key, this.module, this.openKey, this.openDate});

  @override
  State<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends State<ReviewQueueScreen> {
  bool _done = false;
  String _filter = 'all';
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _openedFirst = false;

  @override
  void initState() {
    super.initState();
    if (widget.module != null) _filter = widget.module!;
    _load();
  }

  int _loadNo = 0;

  Future<void> _load() async {
    final no = ++_loadNo;
    setState(() => _error = null);
    try {
      final d = await AgriApi.get(_done ? '/review/queue?status=done' : '/review/queue');
      if (no != _loadNo) return; // a newer load (e.g. tab switch) is on its way
      final list = ((d is Map ? d['items'] : d) as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => reviewModules.containsKey(e['module']))
          .toList();
      if (!mounted) return;
      setState(() => _items = list);
      if (!_openedFirst && (widget.openKey != null || widget.openDate != null)) {
        _openedFirst = true;
        final shown = _shown;
        var i = widget.openKey != null ? shown.indexWhere((e) => e['key'] == widget.openKey) : -1;
        if (i < 0 && widget.openDate != null) {
          final d = widget.openDate!;
          final day = d.length >= 10 ? d.substring(0, 10) : d;
          i = shown.indexWhere((e) => '${e['date']}'.startsWith(day));
        }
        if (i >= 0) _open(i);
      }
    } catch (e) {
      if (!mounted || no != _loadNo) return;
      setState(() {
        _error = e.toString();
        _items ??= [];
      });
    }
  }

  bool _match(Map it) {
    if (_filter == 'all') return true;
    if (_filter == 'maintenance') return it['kind'] == 'maintenance';
    return it['module'] == _filter;
  }

  List<Map<String, dynamic>> get _shown {
    final all = (_items ?? []).where(_match).toList();
    if (_done) return all;
    // look closely first, the server already sorts by date inside each
    return [...all.where((e) => e['look'] == true), ...all.where((e) => e['look'] != true)];
  }

  Future<void> _open(int index) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => ReviewEntryScreen(items: _shown, index: index, decided: _done)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    final counts = <String, int>{};
    for (final it in items) {
      final k = it['kind'] == 'maintenance' ? 'maintenance' : it['module'] as String;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final filters = <MapEntry<String, String>>[
      const MapEntry('all', 'All'),
      for (final k in ['electricity', 'tractor', 'machine', 'machine_pf', 'factory'])
        if ((counts[k] ?? 0) > 0 || _filter == k) MapEntry(k, reviewModules[k]!.label),
      if ((counts['maintenance'] ?? 0) > 0 || _filter == 'maintenance') const MapEntry('maintenance', 'Maintenance'),
    ];
    final shown = _shown;
    final look = _done ? <Map<String, dynamic>>[] : shown.where((e) => e['look'] == true).toList();
    final normal = _done ? shown : shown.where((e) => e['look'] != true).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Review submissions'),
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        elevation: 0.5,
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'old') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminReviewScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'old', child: Text('Older review screen (all records)')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text('Waiting${!_done && _items != null ? ' (${items.length})' : ''}')),
                const ButtonSegment(value: true, label: Text('Decided (14 days)')),
              ],
              selected: {_done},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() {
                  _done = s.first;
                  _items = null;
                });
                _load();
              },
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.key == 'all' ? 'All (${items.length})' : '${f.value} (${counts[f.key] ?? 0})'),
                      selected: _filter == f.key,
                      onSelected: (_) => setState(() => _filter = f.key),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        const Divider(height: 1, color: _border),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _items == null
                ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      if (_error != null) _ErrorBox(_error!),
                      if (shown.isEmpty && _error == null) _empty(),
                      if (look.isNotEmpty) ...[
                        _groupHead('LOOK CLOSELY', look.length, const Color(0xFF9E2419)),
                        for (final it in look) _row(it, shown.indexOf(it)),
                        const SizedBox(height: 10),
                      ],
                      if (normal.isNotEmpty) ...[
                        _groupHead(_done ? 'DECIDED' : 'LOOKS NORMAL', normal.length, _muted),
                        for (final it in normal) _row(it, shown.indexOf(it)),
                      ],
                    ],
                  ),
          ),
        ),
      ]),
    );
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Color(0xFFE3F0DA), shape: BoxShape.circle),
            child: const Icon(Icons.check, color: Color(0xFF2C5E17)),
          ),
          const SizedBox(height: 10),
          Text(_done ? 'Nothing decided in the last 14 days.' : 'Nothing is waiting.',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _groupHead(String t, int n, Color c) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text('$t · $n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: c)),
      );

  Widget _row(Map<String, dynamic> it, int index) {
    final m = reviewModules[it['module']]!;
    final ch = chipFor(it);
    final st = '${it['status'] ?? 'pending'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(index),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: it['look'] == true && !_done ? rToneColors[RTone.bad]!.border : _border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFEEF4E8), borderRadius: BorderRadius.circular(10)),
                child: Icon(m.icon, color: _green, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${m.label} · ${shortDate(it['date'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: _dark)),
                  const SizedBox(height: 2),
                  Text(valueText(it), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                  if ((it['submitted_by'] ?? '').toString().isNotEmpty)
                    Text('by ${it['submitted_by']}', style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _Chip(ch.text, ch.tone),
                if (_done) ...[const SizedBox(height: 4), _StatusChip(st)],
                if (it['photo_url'] != null) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.photo_camera_outlined, size: 15, color: _muted),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── One entry ──────────────────────────────────────────────────────────
class ReviewEntryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int index;
  final bool decided;
  const ReviewEntryScreen({super.key, required this.items, required this.index, this.decided = false});

  @override
  State<ReviewEntryScreen> createState() => _ReviewEntryScreenState();
}

class _ReviewEntryScreenState extends State<ReviewEntryScreen> {
  late List<Map<String, dynamic>> _items;
  late int _i;
  bool _busy = false;
  bool _changed = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _i = widget.index;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _it => _i >= 0 && _i < _items.length ? _items[_i] : null;

  void _go(int i) {
    setState(() => _i = i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _decide(String status, [String? note]) async {
    final it = _it!;
    final m = reviewModules[it['module']]!;
    setState(() => _busy = true);
    try {
      await AgriApi.patch(m.decidePath(it['id']), {
        'status': status,
        if (!m.maint && note != null && note.isNotEmpty) 'admin_note': note,
      });
      _changed = true;
      if (!mounted) return;
      final word = status == 'approved' ? 'approved' : status == 'rejected' ? 'rejected' : 'returned';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${m.label}, ${shortDate(it['date'])}: $word'),
        duration: const Duration(seconds: 2),
      ));
      setState(() {
        _items.removeAt(_i);
        if (_i >= _items.length) _i = _items.length - 1;
        _busy = false;
      });
      if (_items.isEmpty) {
        Navigator.pop(context, true);
      } else if (_scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFF9E2419)));
    }
  }

  Future<void> _returnSheet() async {
    final it = _it!;
    final reasons = returnReasons[it['kind'] == 'run' ? 'run' : 'reading']!;
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _ReturnSheet(reasons: reasons),
    );
    if (note != null && note.trim().isNotEmpty) _decide('returned', note.trim());
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject this job?'),
        content: Text('"${_it!['activity']}" will not count as done, and the next due stays as it was.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB0342A)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok == true) _decide('rejected');
  }

  @override
  Widget build(BuildContext context) {
    final it = _it;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _dark,
          elevation: 0.5,
          leading: BackButton(onPressed: () => Navigator.pop(context, _changed)),
          title: it == null
              ? const Text('Review')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(reviewModules[it['module']]!.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text('${dayName(it['date'])}${(it['submitted_by'] ?? '').toString().isNotEmpty ? ' · by ${it['submitted_by']}' : ''}',
                      style: const TextStyle(fontSize: 12.5, color: _muted)),
                ]),
          actions: [
            if (_items.length > 1) ...[
              Center(child: Text('${_i + 1} of ${_items.length}', style: const TextStyle(fontSize: 12.5, color: _muted))),
              IconButton(tooltip: 'Previous', icon: const Icon(Icons.chevron_left), onPressed: _i > 0 ? () => _go(_i - 1) : null),
              IconButton(tooltip: 'Next', icon: const Icon(Icons.chevron_right), onPressed: _i < _items.length - 1 ? () => _go(_i + 1) : null),
            ],
          ],
        ),
        body: it == null
            ? const Center(child: Text('Nothing left to review.'))
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  if (widget.decided) _DecidedNote(it),
                  if (it['kind'] == 'run')
                    _RunDetail(it)
                  else if (it['kind'] == 'maintenance')
                    _MaintDetail(it)
                  else
                    _ReadingDetail(it),
                ],
              ),
        bottomNavigationBar: it == null || widget.decided
            ? null
            : SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF9E2419),
                          side: const BorderSide(color: Color(0xFFF0C4BE)),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _busy ? null : (reviewModules[it['module']]!.maint ? _reject : _returnSheet),
                        icon: Icon(reviewModules[it['module']]!.maint ? Icons.close : Icons.undo),
                        label: Text(reviewModules[it['module']]!.maint ? 'Reject' : 'Return'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(48)),
                        onPressed: _busy ? null : () => _decide('approved'),
                        icon: const Icon(Icons.check),
                        label: Text(_busy ? 'Saving…' : (_items.length > 1 ? 'Approve & next' : 'Approve')),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }
}

// ── Detail: meter readings and power factor ────────────────────────────
class _ReadingDetail extends StatelessWidget {
  final Map<String, dynamic> it;
  const _ReadingDetail(this.it);

  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(it['check'] ?? {});
    final pf = it['module'] == 'machine_pf';
    final dp = toInt(it['dp']);
    final udp = toInt(it['used_dp']);
    final hours = it['used_unit'] == 'h';
    final history = (c['history'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final last5 = (c['last5'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final prev = c['prev'] == null ? null : Map<String, dynamic>.from(c['prev']);
    final extras = Map<String, dynamic>.from(it['extras'] ?? {});

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Photo(it['photo_url']?.toString()),
      const SizedBox(height: 14),
      Text('Entered ${pf ? 'power factor' : 'reading'}', style: const TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
      Text.rich(TextSpan(children: [
        TextSpan(text: nfmt(it['value'], dp), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _dark)),
        TextSpan(text: '  ${it['unit'] ?? ''}', style: const TextStyle(fontSize: 16, color: _muted)),
      ])),
      if (it['photo_url'] != null)
        const Text('Check this number against the meter in the photo.', style: TextStyle(fontSize: 13, color: _muted)),
      const SizedBox(height: 12),
      _VerdictBox(it),
      const SizedBox(height: 10),
      _Card(children: [
        if (prev != null)
          _KV(pf ? 'Entry before' : 'Reading before', nfmt(prev['value'], dp),
              sub: '${dayName(prev['date'])} · ${prev['status'] == 'approved' ? 'approved' : 'waiting too'}'),
        if (!pf && c['used'] != null)
          _KV('${hours ? 'Hours run' : 'Units used'} since then', nfmt(c['used'], udp),
              sub: 'over ${toInt(c['gap_days'])} day${toInt(c['gap_days']) == 1 ? '' : 's'}'),
        if (!pf && c['usual'] != null)
          _KV('Usual ${hours ? 'hours' : 'units'} a day', nfmt(c['usual'], udp), sub: 'average of the last ${history.length} entries'),
        if (!pf && c['range_lo'] != null)
          _KV('Usual range', '${nfmt(c['range_lo'], udp)} – ${nfmt(c['range_hi'], udp)}', sub: '±30% of the average'),
        if (pf && c['usual'] != null) _KV('Usual power factor', nfmt(c['usual'], 3), sub: 'average of the last ${history.length} entries'),
        if (extras.isNotEmpty)
          _KV('Other registers', extras.entries.map((e) => '${_regName(e.key)} ${nfmt(e.value, 1)}').join(' · ')),
        if ((it['notes'] ?? '').toString().isNotEmpty) _KV('Notes', '${it['notes']}', plain: true),
      ]),
      if (history.length > 1) ...[
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Text(pf ? 'Power factor, last ${history.length} entries' : '${hours ? 'Hours a day' : 'Units per day'}, last ${history.length} entries',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          Text(pf ? 'dashed = 0.99' : 'shaded = usual', style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
        const SizedBox(height: 6),
        _Card(padding: const EdgeInsets.fromLTRB(8, 10, 8, 6), children: [
          SizedBox(
            height: 150,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparkPainter(
                points: history.map((h) => toNum(pf ? h['value'] : h['per_day']) ?? 0).toList(),
                current: toNum(pf ? it['value'] : c['per_day']),
                lo: pf ? null : toNum(c['range_lo']),
                hi: pf ? null : toNum(c['range_hi']),
                avg: pf ? null : toNum(c['usual']),
                limit: pf ? (toNum(c['limit']) ?? 0.99) : null,
                fmt: (v) => nfmt(v, pf ? 3 : udp),
                firstLabel: shortDate(history.first['date']),
              ),
            ),
          ),
        ]),
      ],
      if (last5.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Last ${last5.length} entries', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 6),
        _Card(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          _tableRow(['Date', pf ? 'PF' : 'Reading', if (!pf) (hours ? 'Hours' : 'Units'), 'Status'], head: true),
          for (final r in last5)
            _tableRow([
              shortDate(r['date']),
              nfmt(r['value'], dp),
              if (!pf) (r['used'] != null ? nfmt(r['used'], udp) : '—'),
              '${r['status'] ?? 'pending'}',
            ]),
        ]),
      ],
    ]);
  }

  static String _regName(String k) => k
      .replaceAll(RegExp(r'_reading$'), '')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'kva md', caseSensitive: false), 'kVA MD')
      .replaceAll(RegExp(r'^rkvah', caseSensitive: false), 'RkVAh')
      .replaceAll(RegExp(r'^kvah', caseSensitive: false), 'kVAh');

  Widget _tableRow(List<String> cells, {bool head = false}) {
    final style = TextStyle(fontSize: head ? 11.5 : 13, fontWeight: head ? FontWeight.w600 : FontWeight.w400, color: head ? _muted : _dark);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: head ? null : const Border(top: BorderSide(color: Color(0xFFEEF1EA)))),
      child: Row(children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: 3,
            child: i == cells.length - 1 && !head
                ? Align(alignment: Alignment.centerRight, child: _StatusChip(cells[i]))
                : Text(cells[i], textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: style),
          ),
      ]),
    );
  }
}

// ── Detail: factory run ────────────────────────────────────────────────
class _RunDetail extends StatelessWidget {
  final Map<String, dynamic> it;
  const _RunDetail(this.it);

  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(it['check'] ?? {});
    final u = Map<String, dynamic>.from(c['usual'] ?? {});
    final flags = (c['flags'] as List?) ?? const [];
    final stops = (it['downtimes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final dayRuns = (it['day_runs'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ran = toNum(it['ran_minutes']) ?? 0;
    final down = toNum(it['down_minutes']) ?? 0;
    final on = ran + down > 0 ? ran / (ran + down) : 1.0;
    final usualOn = toNum(u['while_on']);
    final cross = c['cross'] == null ? null : Map<String, dynamic>.from(c['cross']);
    final compared = toInt(c['runs_compared']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${it['start']} – ${it['end']}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _dark)),
      Text('ran ${hm(ran)} · stopped ${hm(down)}', style: const TextStyle(fontSize: 14, color: _muted)),
      const SizedBox(height: 12),
      _VerdictBox(it),
      const SizedBox(height: 14),
      const Text('The day on a 24-hour bar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      SizedBox(
        height: 60,
        child: CustomPaint(
          size: Size.infinite,
          painter: _DayBarPainter([
            ...dayRuns.map((r) => _BarRun(r['start'], r['end'], r['downtimes'] as List? ?? [], false)),
            _BarRun(it['start'], it['end'], stops, true),
          ]),
        ),
      ),
      Text(
        'Dark green = this run, orange = stopped.${dayRuns.isNotEmpty ? ' Other runs that day: ${dayRuns.map((r) => '${r['start']}–${r['end']}').join(', ')}.' : ''}',
        style: const TextStyle(fontSize: 12, color: _muted),
      ),
      const SizedBox(height: 14),
      const Text('Stops in this run', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      if (stops.isEmpty) const Text('No stops — it ran the whole time.', style: TextStyle(fontSize: 13.5, color: _muted)),
      for (final d in stops)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: const Color(0xFFFDF3E9), borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            Text('${_t5(d['start_time'])} – ${_t5(d['end_time'])}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(width: 8),
            Flexible(
              child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFFBE0C6), borderRadius: BorderRadius.circular(20)),
                  child: Text(stopReasonLabel[d['reason_type']] ?? 'Other',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF8A3B05))),
                ),
                if ((d['reason_note'] ?? '').toString().isNotEmpty)
                  Text('${d['reason_note']}', style: const TextStyle(fontSize: 12.5, color: _muted)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(hm(d['duration_mins'] ?? (_toMin(d['end_time']) - _toMin(d['start_time']))),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
        ),
      if ((it['notes'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${it['notes']}', style: const TextStyle(fontSize: 13.5))),
      const SizedBox(height: 14),
      Text('Compared with the last $compared runs', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      if (compared == 0)
        const Text('No earlier runs to compare with.', style: TextStyle(fontSize: 13.5, color: _muted))
      else
        _Card(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          _cmp('', 'This run', 'Usual', head: true),
          _cmp('Ran', hm(ran), hm(u['ran']), bad: flags.contains('ran_low')),
          _cmp('Stopped', hm(down), hm(u['down']), bad: flags.contains('stopped_high')),
          _cmp('Number of stops', '${stops.length}', _stripZero(nfmt(u['stops'], 1))),
          _cmp('Running while on', '${(on * 100).round()}%', usualOn != null ? '${(usualOn * 100).round()}%' : '—',
              bad: usualOn != null && on < usualOn * 0.7),
        ]),
      if (cross != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cross['matches'] == true ? Colors.white : const Color(0xFFFFFAFA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cross['matches'] == true ? _border : const Color(0xFFF0C4BE)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Same day, machine hour meter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Machine hour meter: ${nfmt(cross['machine_hours'], 1)} h for ${shortDate(it['date'])}. All runs that day add up to ${nfmt(cross['run_hours'], 1)} h.',
                style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 4),
            Text(
              cross['matches'] == true ? 'These match.' : 'They differ by ${nfmt((toNum(cross['diff']) ?? 0).abs(), 1)} h — one of them may be wrong.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cross['matches'] == true ? const Color(0xFF2C5E17) : const Color(0xFF9E2419)),
            ),
          ]),
        ),
      ],
    ]);
  }

  static String _stripZero(String s) => s.replaceAll(RegExp(r'\.0$'), '');

  Widget _cmp(String label, String mine, String usual, {bool head = false, bool bad = false}) {
    final base = TextStyle(fontSize: head ? 12 : 14, color: head ? _muted : _dark, fontWeight: head ? FontWeight.w600 : FontWeight.w400);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: head ? null : const Border(top: BorderSide(color: Color(0xFFEEF1EA)))),
      child: Row(children: [
        Expanded(flex: 5, child: Text(label, style: base)),
        Expanded(
          flex: 3,
          child: Text(mine,
              textAlign: TextAlign.right,
              style: base.copyWith(fontWeight: head ? FontWeight.w600 : FontWeight.w700, color: bad ? const Color(0xFF9E2419) : base.color)),
        ),
        Expanded(flex: 3, child: Text(usual, textAlign: TextAlign.right, style: base.copyWith(color: _muted))),
      ]),
    );
  }
}

// ── Detail: maintenance "done" ─────────────────────────────────────────
class _MaintDetail extends StatelessWidget {
  final Map<String, dynamic> it;
  const _MaintDetail(this.it);

  @override
  Widget build(BuildContext context) {
    final c = Map<String, dynamic>.from(it['check'] ?? {});
    final prev = c['prev'] == null ? null : Map<String, dynamic>.from(c['prev']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Job marked done', style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
      Text('${it['activity'] ?? ''}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _dark)),
      const SizedBox(height: 12),
      _VerdictBox(it),
      const SizedBox(height: 10),
      _Card(children: [
        _KV('Done on', dayName(it['date']), sub: (it['submitted_by'] ?? '').toString().isNotEmpty ? 'by ${it['submitted_by']}' : null),
        _KV('Hour meter when done', '${nfmt(it['hours_at'], 1)} h'),
        if (prev != null) _KV('Last done before', '${nfmt(prev['hours'], 1)} h', sub: dayName(prev['date'])),
        if (c['since'] != null) _KV('Hours since then', '${nfmt(c['since'], 1)} h'),
        _KV('Due every', '${nfmt(c['interval'])} h'),
        _KV('Next due if approved', '${nfmt(c['next_due'], 1)} h'),
        if ((it['notes'] ?? '').toString().isNotEmpty) _KV('What was done', '${it['notes']}', plain: true),
      ]),
      if (it['photo_url'] != null) ...[const SizedBox(height: 12), _Photo(it['photo_url'].toString())],
    ]);
  }
}

// ── Small pieces ───────────────────────────────────────────────────────
String _t5(dynamic t) {
  final s = '${t ?? ''}';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

int _toMin(dynamic t) {
  final p = _t5(t).split(':');
  return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

class _Photo extends StatelessWidget {
  final String? url;
  const _Photo(this.url);

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: 150,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7EA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7C78D)),
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.photo_camera_outlined, color: Color(0xFF7A4D00)),
          SizedBox(height: 6),
          Text('No photo was added', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF7A4D00))),
          SizedBox(height: 2),
          Text("The number can't be checked against the meter. You can return it and ask for a photo.",
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Color(0xFF7A4D00))),
        ]),
      );
    }
    final src = url!.startsWith('http') ? url! : '${AppConfig.apiHost}$url';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoFull(src))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          Container(
            height: 240,
            width: double.infinity,
            color: const Color(0xFFEEF1EA),
            child: Image.network(
              src,
              fit: BoxFit.cover,
              loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              errorBuilder: (_, __, ___) => const Center(
                  child: Text('The photo could not be loaded.', style: TextStyle(color: _muted))),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.zoom_in, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PhotoFull extends StatelessWidget {
  final String src;
  const _PhotoFull(this.src);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Photo')),
        body: InteractiveViewer(
          maxScale: 6,
          child: Center(child: Image.network(src, fit: BoxFit.contain)),
        ),
      );
}

class _VerdictBox extends StatelessWidget {
  final Map<String, dynamic> it;
  const _VerdictBox(this.it);

  @override
  Widget build(BuildContext context) {
    final v = verdictFor(it);
    final col = rToneColors[v.tone]!;
    final icon = {
      RTone.ok: Icons.check_circle_outline,
      RTone.warn: Icons.info_outline,
      RTone.bad: Icons.warning_amber_rounded,
      RTone.todo: Icons.help_outline,
    }[v.tone]!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: col.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: col.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: col.fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: col.fg)),
            if (v.text.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(v.text, style: const TextStyle(fontSize: 13.5, color: _dark)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _DecidedNote extends StatelessWidget {
  final Map<String, dynamic> it;
  const _DecidedNote(this.it);

  @override
  Widget build(BuildContext context) {
    final note = (it['admin_note'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        _StatusChip('${it['status'] ?? ''}'),
        if (note.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(child: Text('"$note"', style: const TextStyle(fontSize: 13.5, color: Color(0xFF8F2018)))),
        ],
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const _Card({required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool plain;
  const _KV(this.label, this.value, {this.sub, this.plain = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13.5)),
              if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: Text(value,
                textAlign: plain ? TextAlign.left : TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: plain ? FontWeight.w400 : FontWeight.w700, color: _dark)),
          ),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final RTone tone;
  const _Chip(this.text, this.tone);

  @override
  Widget build(BuildContext context) {
    final c = rToneColors[tone]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.fg)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'approved':
        return const _Chip('Approved', RTone.ok);
      case 'returned':
        return const _Chip('Returned', RTone.bad);
      case 'rejected':
        return const _Chip('Rejected', RTone.bad);
    }
    return const _Chip('Waiting', RTone.warn);
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox(this.text);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFBE2DF), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(color: Color(0xFF9E2419))),
      );
}

// Return with a reason: quick chips + text; a reason is required.
class _ReturnSheet extends StatefulWidget {
  final List<String> reasons;
  const _ReturnSheet({required this.reasons});

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Return with a reason', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
        const SizedBox(height: 4),
        const Text('The person who entered it sees this and corrects the entry.', style: TextStyle(fontSize: 13, color: _muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in widget.reasons)
            ActionChip(
              label: Text(r),
              onPressed: () => setState(() {
                _ctrl.text = r;
                _ctrl.selection = TextSelection.collapsed(offset: r.length);
              }),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          maxLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'What needs to be corrected?'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB0342A), minimumSize: const Size.fromHeight(48)),
          onPressed: _ctrl.text.trim().isEmpty ? null : () => Navigator.pop(context, _ctrl.text.trim()),
          icon: const Icon(Icons.undo),
          label: const Text('Return'),
        ),
      ]),
    );
  }
}

// ── Painters ───────────────────────────────────────────────────────────
class _SparkPainter extends CustomPainter {
  final List<double> points;
  final double? current, lo, hi, avg, limit;
  final String Function(double) fmt;
  final String firstLabel;
  _SparkPainter({
    required this.points,
    required this.current,
    required this.lo,
    required this.hi,
    required this.avg,
    required this.limit,
    required this.fmt,
    required this.firstLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final all = [...points, if (current != null) current!, if (lo != null) lo!, if (hi != null) hi!, if (limit != null) limit!];
    var mn = all.reduce((a, b) => a < b ? a : b);
    var mx = all.reduce((a, b) => a > b ? a : b);
    if (limit != null) {
      mn = mn < limit! - 0.01 ? mn : limit! - 0.01;
      mx = mx > 1 ? mx : 1;
    } else {
      mn = mn < 0 ? mn : 0;
    }
    var pad = (mx - mn) * 0.08;
    if (pad == 0) pad = 1;
    mx += pad;
    if (limit != null) mn -= pad * 0.2;
    const l = 4.0, r = 4.0, t = 14.0, b = 16.0;
    final n = points.length + (current != null ? 1 : 0);
    double x(int i) => l + (n <= 1 ? 0 : i / (n - 1) * (size.width - l - r));
    double y(double v) => t + (1 - (v - mn) / (mx - mn)) * (size.height - t - b);

    if (lo != null && hi != null) {
      canvas.drawRect(Rect.fromLTRB(l, y(hi!), size.width - r, y(lo!)), Paint()..color = const Color(0xFFEEF5E8));
      _text(canvas, 'usual ${fmt(lo!)} – ${fmt(hi!)}', Offset(l + 2, (y(hi!) - 14).clamp(0.0, size.height)), const Color(0xFF2C5E17));
    }
    if (limit != null) _dash(canvas, y(limit!), size, const Color(0xFFD0611C));
    if (avg != null) _dash(canvas, y(avg!), size, const Color(0xFF8FBF6B));

    final line = Paint()
      ..color = const Color(0xFF4A7A2B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(x(0), y(points[0]));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(points[i]));
    }
    canvas.drawPath(path, line);

    if (current != null) {
      final out = (hi != null && current! > hi!) || (lo != null && current! < lo!) || (limit != null && current! < limit!);
      final col = out ? const Color(0xFFB0342A) : const Color(0xFF1E3313);
      final cx = x(n - 1), cy = y(current!);
      canvas.drawLine(Offset(x(points.length - 1), y(points.last)), Offset(cx, cy),
          Paint()
            ..color = out ? const Color(0xFFB0342A) : const Color(0xFF4A7A2B)
            ..strokeWidth = 2);
      canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = col);
      _text(canvas, fmt(current!), Offset(cx - 4, (cy - 20).clamp(0.0, size.height)), col, alignRight: true, bold: true);
    }
    _text(canvas, firstLabel, Offset(l, size.height - 13), const Color(0xFF6B7563));
  }

  void _dash(Canvas c, double yy, Size s, Color col) {
    final p = Paint()
      ..color = col
      ..strokeWidth = 1;
    for (double xx = 4; xx < s.width - 4; xx += 8) {
      c.drawLine(Offset(xx, yy), Offset(xx + 4, yy), p);
    }
  }

  void _text(Canvas c, String s, Offset at, Color col, {bool alignRight = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 11, color: col, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, alignRight ? Offset(at.dx - tp.width, at.dy) : at);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.points != points || old.current != current;
}

class _BarRun {
  final dynamic start, end;
  final List stops;
  final bool me;
  _BarRun(this.start, this.end, this.stops, this.me);
}

class _DayBarPainter extends CustomPainter {
  final List<_BarRun> runs;
  _DayBarPainter(this.runs);

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 40.0;
    final w = size.width;
    double px(int m) => m / 1440 * w;
    final rr = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, barH), const Radius.circular(10));
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFF1F3EE));
    canvas.save();
    canvas.clipRRect(rr);
    // A span that passes midnight (e.g. 20:00-06:00) is drawn as two pieces.
    void span(int s, int e, Paint p) {
      if (e >= s) {
        canvas.drawRect(Rect.fromLTRB(px(s), 0, px(e), barH), p);
      } else {
        canvas.drawRect(Rect.fromLTRB(px(s), 0, w, barH), p);
        canvas.drawRect(Rect.fromLTRB(0, 0, px(e), barH), p);
      }
    }
    for (final r in runs) {
      span(_toMin(r.start), _toMin(r.end), Paint()..color = r.me ? const Color(0xFF4A7A2B) : const Color(0xFFA9CF8C));
      for (final d in r.stops) {
        final m = d as Map;
        span(_toMin(m['start_time']), _toMin(m['end_time']), Paint()..color = const Color(0xFFE0802E));
      }
    }
    canvas.restore();
    canvas.drawRRect(rr, Paint()
      ..color = _border
      ..style = PaintingStyle.stroke);
    for (final h in [0, 6, 12, 18, 24]) {
      final tp = TextPainter(
        text: TextSpan(text: h.toString().padLeft(2, '0'), style: const TextStyle(fontSize: 10.5, color: Color(0xFF6B7563))),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (h / 24 * w - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(x, barH + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _DayBarPainter old) => true;
}
