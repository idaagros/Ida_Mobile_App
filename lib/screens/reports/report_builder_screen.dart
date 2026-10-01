// lib/screens/reports/report_builder_screen.dart
//
// One report on the phone (Sep 2026, group E), same as the website:
// period, group by up to 3 things (in order), "Only" filters, which
// figures to show; the table shows each group, its subtotal and the
// grand total (swipe sideways for every column). Excel always has
// Summary + Every entry + About; the PDF adds every entry when ticked.
// Open with a report from ReportsHubScreen, or with reportKey
// ('dispatch', 'attendance', 'crop_cost', …) from other screens.
// API: GET /report-hub/:key?from&to&group_by&show&filters&format.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'reports_common.dart';

class ReportBuilderScreen extends StatefulWidget {
  final Map<String, dynamic>? report;
  final String? reportKey;
  const ReportBuilderScreen({super.key, this.report, this.reportKey});
  @override
  State<ReportBuilderScreen> createState() => _ReportBuilderScreenState();
}

class _ReportBuilderScreenState extends State<ReportBuilderScreen> {
  Map<String, dynamic>? rep;
  String preset = 'month';
  late String from;
  late String to;
  List<String> groupBy = [];
  final Map<String, List<String>> filters = {};
  List<String> show = [];
  bool withEntries = false;
  Map<String, dynamic>? data;
  bool loading = false;
  String? busy;
  String? wsBusy;
  String? error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final p = periodOf('month');
    from = p.$1;
    to = p.$2;
    if (widget.report != null) {
      _setReport(widget.report!);
    } else {
      _findReport();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _findReport() async {
    try {
      final d = await ReportApi.get('/report-hub');
      final list = List<Map<String, dynamic>>.from(d['reports'] ?? []);
      final r = list.where((x) => x['key'] == widget.reportKey).toList();
      if (r.isEmpty) {
        setState(() => error = 'This report is not available to you.');
      } else {
        _setReport(r.first);
      }
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  void _setReport(Map<String, dynamic> r) {
    setState(() {
      rep = r;
      groupBy = List<String>.from(r['defaultGroup'] ?? []);
      show = [for (final f in (r['figures'] as List? ?? [])) if (f['default'] == true) '${f['key']}'];
    });
    _load();
  }

  List<Map<String, dynamic>> get dims => List<Map<String, dynamic>>.from(rep?['dims'] ?? []);
  List<Map<String, dynamic>> get figures => List<Map<String, dynamic>>.from(rep?['figures'] ?? []);
  String dimLabel(String k) => (dims.firstWhere((d) => d['key'] == k, orElse: () => {'label': k})['label']).toString();

  String _query() {
    final f = <String, List<String>>{};
    filters.forEach((k, v) {
      if (v.isNotEmpty) f[k] = v;
    });
    return 'from=$from&to=$to&group_by=${groupBy.join(',')}&show=${show.join(',')}'
        '${f.isEmpty ? '' : '&filters=${Uri.encodeQueryComponent(jsonEncode(f))}'}';
  }

  void _load() {
    if (rep == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      if (from.compareTo(to) > 0) return;
      setState(() => loading = true);
      try {
        final d = await ReportApi.get('/report-hub/${rep!['key']}?${_query()}');
        if (mounted) setState(() {
          data = Map<String, dynamic>.from(d);
          error = null;
        });
      } catch (e) {
        if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
      } finally {
        if (mounted) setState(() => loading = false);
      }
    });
  }

  Future<void> _download(String kind) async {
    if (rep == null) return;
    setState(() {
      busy = kind;
      error = null;
    });
    try {
      final key = rep!['key'].toString();
      await ReportApi.download(context, '/report-hub/$key?${_query()}&format=$kind${kind == 'pdf' && withEntries ? '&entries=1' : ''}',
          '${key.replaceAll('_', '-')}_${from}_to_$to.$kind');
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  // Men / women wage sheet (workers × days, each day's wage, totals) for
  // the period picked above — attendance only. Brought back Oct 2026.
  Future<void> _wageSheet(String kind) async {
    setState(() {
      wsBusy = kind;
      error = null;
    });
    try {
      await ReportApi.download(context, '/attendance/report-gender-split?from=$from&to=$to${kind == 'pdf' ? '&format=pdf' : ''}',
          'wage-sheet-men-women_${from}_to_$to.$kind');
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => wsBusy = null);
    }
  }

  Widget _wageSheetCard() {
    final bad = from.compareTo(to) > 0;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFE3C0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Wage sheet (men / women)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Workers × days with each day\'s wage and totals, for ${niceDate(from)} – ${niceDate(to)}.',
            style: const TextStyle(fontSize: 12.5, color: rMuted)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: wsBusy != null || bad ? null : () => _wageSheet('xlsx'),
              icon: const Icon(Icons.grid_on, size: 18),
              label: Text(wsBusy == 'xlsx' ? 'Making…' : 'Excel'),
              style: OutlinedButton.styleFrom(foregroundColor: rDark, backgroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: wsBusy != null || bad ? null : () => _wageSheet('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(wsBusy == 'pdf' ? 'Making…' : 'PDF'),
              style: OutlinedButton.styleFrom(foregroundColor: rDark, backgroundColor: Colors.white, minimumSize: const Size.fromHeight(44)),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _pickPreset(String p) async {
    if (p == 'custom') {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDateRange: DateTimeRange(start: DateTime.parse(from), end: DateTime.parse(to)),
      );
      if (r == null) return;
      setState(() {
        preset = 'custom';
        from = ymd(r.start);
        to = ymd(r.end);
      });
    } else {
      final r = periodOf(p);
      setState(() {
        preset = p;
        from = r.$1;
        to = r.$2;
      });
    }
    _load();
  }

  Future<void> _addGroup() async {
    final left = dims.where((d) => !groupBy.contains(d['key'])).toList();
    final k = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 6), child: Text('Group by', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          for (final d in left) ListTile(title: Text('${d['label']}'), onTap: () => Navigator.pop(ctx, '${d['key']}')),
        ]),
      ),
    );
    if (k == null) return;
    setState(() => groupBy = [...groupBy, k]);
    _load();
  }

  Future<void> _editFilters() async {
    final options = Map<String, dynamic>.from(data?['options'] ?? {});
    final fdims = dims.where((d) => d['date'] == null && (options[d['key']] as List?)?.isNotEmpty == true).toList();
    final draft = {for (final e in filters.entries) e.key: List<String>.from(e.value)};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (ctx, scroll) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
              child: Row(children: [
                const Expanded(child: Text('Only', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () => setSheet(() => draft.clear()), child: const Text('Clear all')),
              ]),
            ),
            Expanded(
              child: ListView(controller: scroll, children: [
                for (final d in fdims)
                  ExpansionTile(
                    title: Text('${d['label']}'),
                    subtitle: Text((draft[d['key']] ?? []).isEmpty ? 'All' : '${(draft[d['key']] ?? []).length} picked'),
                    children: [
                      for (final o in (options[d['key']] as List))
                        CheckboxListTile(
                          dense: true,
                          value: (draft[d['key']] ?? []).contains('${o['value']}'),
                          title: Text('${o['label']}'),
                          onChanged: (v) => setSheet(() {
                            final list = draft[d['key'].toString()] ??= [];
                            if (v == true) {
                              list.add('${o['value']}');
                            } else {
                              list.remove('${o['value']}');
                            }
                          }),
                        ),
                    ],
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: rGreen, minimumSize: const Size.fromHeight(48)),
                child: const Text('Show'),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      filters
        ..clear()
        ..addAll(draft);
    });
    _load();
  }

  String _filterText() {
    final parts = <String>[];
    final options = Map<String, dynamic>.from(data?['options'] ?? {});
    filters.forEach((k, v) {
      if (v.isEmpty) return;
      final opts = List.from(options[k] ?? []);
      String lab(String x) => (opts.firstWhere((o) => '${o['value']}' == x, orElse: () => {'label': x})['label']).toString();
      parts.add('${dimLabel(k)}: ${v.length == 1 ? lab(v.first) : '${lab(v.first)} +${v.length - 1}'}');
    });
    return parts.isEmpty ? 'everything' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final title = rep?['title']?.toString() ?? 'Report';
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F1),
      appBar: AppBar(title: Text(title), backgroundColor: rDark, foregroundColor: Colors.white),
      body: rep == null
          ? Center(child: error != null ? Padding(padding: const EdgeInsets.all(24), child: Text(error!)) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
                children: [
                  Text('${rep!['description'] ?? ''}', style: const TextStyle(fontSize: 13, color: rMuted)),
                  const SizedBox(height: 10),
                  _card([
                    const Text('Period', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in periodPresets)
                        ChoiceChip(
                          label: Text(p.$2),
                          selected: preset == p.$1,
                          selectedColor: const Color(0xFFE3F0DA),
                          onSelected: (_) => _pickPreset(p.$1),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text('${niceDate(from)} – ${niceDate(to)}', style: const TextStyle(fontSize: 12.5, color: rMuted)),
                    const Divider(height: 22),
                    const Text('Group by (up to 3)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      for (var i = 0; i < groupBy.length; i++)
                        InputChip(
                          avatar: CircleAvatar(backgroundColor: const Color(0xFF88BA63), child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: rDark))),
                          label: Text(dimLabel(groupBy[i]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          backgroundColor: rDark,
                          deleteIconColor: Colors.white,
                          onDeleted: () {
                            setState(() => groupBy = [...groupBy]..removeAt(i));
                            _load();
                          },
                        ),
                      if (groupBy.length < 3)
                        ActionChip(label: const Text('+ Add'), onPressed: _addGroup),
                    ]),
                    const Divider(height: 22),
                    InkWell(
                      onTap: data == null ? null : _editFilters,
                      child: Row(children: [
                        const Icon(Icons.filter_alt_outlined, size: 20, color: rGreen),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Only: ${_filterText()}', style: const TextStyle(fontSize: 13.5), maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const Text('Change', style: TextStyle(fontWeight: FontWeight.w700, color: rGreen)),
                      ]),
                    ),
                    const Divider(height: 22),
                    const Text('Show', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final f in figures)
                        FilterChip(
                          label: Text('${f['label']}'),
                          selected: show.contains(f['key']),
                          selectedColor: const Color(0xFFE3F0DA),
                          onSelected: (on) {
                            setState(() {
                              final k = '${f['key']}';
                              show = [for (final x in figures) if ('${x['key']}' == k ? on : show.contains('${x['key']}')) '${x['key']}'];
                            });
                            _load();
                          },
                        ),
                    ]),
                  ]),
                  if (rep!['key'] == 'attendance') _wageSheetCard(),
                  if (error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFBE2DF), borderRadius: BorderRadius.circular(10)),
                      child: Text(error!, style: const TextStyle(color: Color(0xFF9E2419))),
                    ),
                  const SizedBox(height: 10),
                  _table(),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy != null || data == null ? null : () => _download('xlsx'),
                        icon: const Icon(Icons.grid_on, size: 18),
                        label: Text(busy == 'xlsx' ? 'Making…' : 'Excel'),
                        style: OutlinedButton.styleFrom(foregroundColor: rDark, minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy != null || data == null ? null : () => _download('pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: Text(busy == 'pdf' ? 'Making…' : 'PDF'),
                        style: FilledButton.styleFrom(backgroundColor: rGreen, minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ]),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: withEntries,
                    onChanged: (v) => setState(() => withEntries = v == true),
                    title: const Text('Add every entry to the PDF', style: TextStyle(fontSize: 14)),
                  ),
                  const Text('Excel always has every entry on its own sheet. The file opens with Open / Share (WhatsApp, email, save).',
                      style: TextStyle(fontSize: 12, color: rMuted)),
                ],
              ),
            ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: rBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _table() {
    final d = data;
    if (d == null) {
      return Padding(padding: const EdgeInsets.all(30), child: Center(child: loading ? const CircularProgressIndicator() : const Text('Nothing yet.')));
    }
    final figs = List<Map<String, dynamic>>.from(d['figures'] ?? []);
    final rows = List<Map<String, dynamic>>.from(d['rows'] ?? []);
    final gb = List<Map<String, dynamic>>.from(d['group_by'] ?? []);
    final last = gb.length - 1;
    final total = Map<String, dynamic>.from(d['total']?['values'] ?? {});
    const labelW = 170.0, colW = 104.0;
    Widget line(String label, Map values, {int level = 0, bool bold = false, Color? bg, Color fg = Colors.black87}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            SizedBox(
              width: labelW,
              child: Padding(
                padding: EdgeInsets.only(left: level * 12.0),
                child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: fg)),
              ),
            ),
            for (final f in figs)
              SizedBox(
                width: colW,
                child: Text(fmtFigure(values[f['key']], f['fmt']?.toString()), textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: fg)),
              ),
          ]),
        );
    final count = (d['entry_count'] as num?)?.toInt() ?? 0;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: rBorder)),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: loading ? 0.6 : 1,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 24 + labelW + figs.length * colW,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: const Color(0xFFFAFBF8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  SizedBox(width: labelW, child: Text(gb.map((g) => g['label']).join(' · ').isEmpty ? 'All' : gb.map((g) => g['label']).join(' · '), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: rMuted))),
                  for (final f in figs)
                    SizedBox(width: colW, child: Text('${f['label']}', textAlign: TextAlign.right, maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: rMuted))),
                ]),
              ),
              for (final r in rows)
                line('${r['label']}', Map.from(r['values'] ?? {}),
                    level: (r['level'] as num?)?.toInt() ?? 0,
                    bold: ((r['level'] as num?)?.toInt() ?? 0) < last,
                    bg: ((r['level'] as num?)?.toInt() ?? 0) < last ? const Color(0xFFF1F4EC) : null),
              line('Total · $count ${count == 1 ? 'entry' : 'entries'}', total, bold: true, bg: rDark, fg: Colors.white),
            ]),
          ),
        ),
      ),
    );
  }
}
