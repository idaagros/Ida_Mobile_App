// lib/screens/factory_tractor_diesel_screen.dart
//
// Factory tractor diesel (Oct 2026 redesign, group F) — the same as the
// website's Tractor hours › Diesel tab.
//  - This month: litres, cost (₹ a litre), litres per hour worked
//    (from the hour meter readings between fill-ups) and how many
//    fill-ups were above normal (more than 10% over the average).
//  - Litres per hour for each fill-up as small bars.
//  - Fill-ups with approve / return (people who can approve tractor
//    readings), and Correct for a returned one.
//  - Add a fill-up (date, litres, cost, notes); it shows the latest hour
//    meter reading. Excel download of the period.
// API: GET /tractor/diesel-logs/summary?from&to, POST /tractor/diesel-logs,
//      PUT /tractor/diesel-logs/:id, PATCH /tractor/diesel-logs/:id/status,
//      GET /tractor/diesel-logs/xlsx

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'admin/admin_common.dart';
import 'reports/reports_common.dart' show ReportApi;

class FactoryTractorDieselScreen extends StatefulWidget {
  const FactoryTractorDieselScreen({super.key});
  @override
  State<FactoryTractorDieselScreen> createState() => _FactoryTractorDieselScreenState();
}

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');
String _rupees(dynamic v) => v == null ? '—' : '₹${_inr.format((double.tryParse('$v') ?? 0).round())}';
String _num(dynamic v, [int dp = 1]) {
  final d = double.tryParse('${v ?? ''}');
  if (d == null) return '—';
  return d.toStringAsFixed(dp);
}

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _short(dynamic s) {
  final d = DateTime.tryParse('${s ?? ''}');
  return d == null ? '$s' : DateFormat('d MMM').format(d);
}

class _FactoryTractorDieselScreenState extends State<FactoryTractorDieselScreen> {
  String _period = '3m';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _canAdd = false;
  bool _canUpdate = false; // correcting a returned fill is Update on the server
  int? _me;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _canAdd = await ApiService.canAdd('tractor');
    _canUpdate = await ApiService.canUpdate('tractor');
    _me = await myUserId();
    await _load();
  }

  (String?, String?) get _range {
    final n = DateTime.now();
    switch (_period) {
      case 'month':
        return (_ymd(DateTime(n.year, n.month, 1)), _ymd(n));
      case '3m':
        return (_ymd(DateTime(n.year, n.month - 2, 1)), _ymd(n));
      case 'year':
        final fy = n.month >= 4 ? n.year : n.year - 1;
        return ('$fy-04-01', _ymd(n));
      default:
        return (null, null);
    }
  }

  String get _query {
    final r = _range;
    return r.$1 == null ? '' : '?from=${r.$1}&to=${r.$2}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await AdminApi.get('/tractor/diesel-logs/summary$_query');
      if (!mounted) return;
      setState(() => _data = d is Map ? Map<String, dynamic>.from(d) : null);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _fills =>
      ((_data?['fills'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

  Future<void> _decide(Map<String, dynamic> f, String status) async {
    String? note;
    if (status == 'returned') {
      final ctrl = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Return the ${_short(f['log_date'])} fill-up'),
          content: TextField(controller: ctrl, autofocus: true, maxLines: 2, decoration: aInput('What needs fixing?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: aRed),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Return'),
            ),
          ],
        ),
      );
      ctrl.dispose();
      if (note == null) return;
      if (note.isEmpty) {
        if (mounted) showErr(context, 'Please say what needs fixing.');
        return;
      }
    }
    try {
      await AdminApi.patch('/tractor/diesel-logs/${f['id']}/status', {'status': status, if (note != null) 'admin_note': note});
      await _load();
      if (mounted) showOk(context, status == 'approved' ? 'Approved' : 'Returned');
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    }
  }

  Future<void> _form([Map<String, dynamic>? edit]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FillSheet(edit: edit, meterNow: _data?['meter_now'], since: _data?['hours_since_last_fill']),
    );
    if (saved == true) {
      await _load();
      if (mounted) showOk(context, edit == null ? 'Fill-up saved. It waits for approval.' : 'Corrected. It waits for approval again.');
    }
  }

  Future<void> _excel() async {
    try {
      await ReportApi.download(context, '/tractor/diesel-logs/xlsx$_query', 'factory_tractor_diesel.xlsx');
    } catch (e) {
      if (mounted) showErr(context, errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: aBg,
      appBar: adminBar('Factory tractor diesel', actions: [
        IconButton(tooltip: 'Excel', icon: const Icon(Icons.download_outlined), onPressed: _data == null ? null : _excel),
      ]),
      floatingActionButton: _canAdd
          ? FloatingActionButton.extended(
              backgroundColor: aGreen,
              foregroundColor: Colors.white,
              onPressed: () => _form(),
              icon: const Icon(Icons.local_gas_station_outlined),
              label: const Text('Add fill-up'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
          AFilterChips<String>(
            value: _period,
            onChanged: (v) {
              setState(() => _period = v);
              _load();
            },
            options: const [('month', 'This month', null), ('3m', 'Last 3 months', null), ('year', 'This year', null), ('all', 'All', null)],
          ),
          const SizedBox(height: 12),
          AErrorBox(_error),
          if (_loading && _data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (_data != null) ..._content(),
        ]),
      ),
    );
  }

  List<Widget> _content() {
    final d = _data!;
    final m = d['this_month'] is Map ? Map<String, dynamic>.from(d['this_month']) : <String, dynamic>{};
    final avg = d['average_litres_per_hour'];
    final high = d['high_limit'];
    final above = int.tryParse('${d['above_normal'] ?? 0}') ?? 0;
    final litres = double.tryParse('${m['litres'] ?? 0}') ?? 0;
    final cost = double.tryParse('${m['cost'] ?? 0}') ?? 0;
    final month = DateTime.tryParse('${m['month'] ?? ''}-01');
    final mName = month == null ? 'this month' : DateFormat('MMMM').format(month);
    final fills = _fills;
    final canApprove = d['can_approve'] == true;

    Widget tile(String label, String value, String sub, {bool warn = false}) => Expanded(
          child: ACard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            color: warn ? const Color(0xFFFFF7EA) : Colors.white,
            border: warn ? const Color(0xFFF3D7A6) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12.5, color: warn ? aAmber : aMuted)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: warn ? aRed : aText)),
              Text(sub, maxLines: 2, style: const TextStyle(fontSize: 11.5, color: aMuted)),
            ]),
          ),
        );

    final withLph = fills.where((f) => f['litres_per_hour'] != null).take(8).toList().reversed.toList();
    final maxLph = withLph.fold<double>(0, (s, f) {
      final v = double.tryParse('${f['litres_per_hour']}') ?? 0;
      return v > s ? v : s;
    });

    return [
      Row(children: [
        tile('Diesel in $mName', '${_num(litres)} L', '${m['fills'] ?? 0} fill-ups${(m['waiting'] ?? 0) != 0 ? ' · ${m['waiting']} waiting' : ''}'),
        const SizedBox(width: 10),
        tile('Cost in $mName', _rupees(cost), litres > 0 && cost > 0 ? '₹${_num(cost / litres)} a litre' : '—'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        tile('Litres per hour', avg == null ? '—' : _num(avg, 2), 'average between fill-ups'),
        const SizedBox(width: 10),
        tile('Above normal', '$above fill-up${above == 1 ? '' : 's'}', high == null ? 'needs 2 fill-ups' : 'more than ${_num(high, 2)} L/hour', warn: above > 0),
      ]),
      if (withLph.isNotEmpty) ...[
        const SizedBox(height: 12),
        ACard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Litres per hour, each fill-up', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: aText)),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final f in withLph)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(_num(f['litres_per_hour']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Container(
                        width: 22,
                        height: maxLph <= 0 ? 4.0 : 76 * ((double.tryParse('${f['litres_per_hour']}') ?? 0) / maxLph).clamp(0.05, 1.0).toDouble(),
                        decoration: BoxDecoration(
                          color: f['above_normal'] == true ? const Color(0xFFC0473A) : const Color(0xFF88BA63),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_short(f['log_date']), style: const TextStyle(fontSize: 10.5, color: aMuted)),
                    ]),
                  ),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      Text('FILL-UPS  ${fills.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .8, color: aMuted)),
      const SizedBox(height: 6),
      if (fills.isEmpty)
        const ACard(padding: EdgeInsets.all(18), child: Text('No fill-ups in this period.', style: TextStyle(color: aMuted)))
      else
        ACard(child: Column(children: [for (var i = 0; i < fills.length; i++) _fillRow(fills[i], i == 0, canApprove)])),
      if (d['meter_now'] != null) ...[
        const SizedBox(height: 10),
        Text('Latest hour meter: ${_num(d['meter_now'])} h', style: const TextStyle(fontSize: 12.5, color: aMuted)),
      ],
    ];
  }

  Widget _fillRow(Map<String, dynamic> f, bool first, bool canApprove) {
    final st = '${f['status']}';
    final mine = _me != null && int.tryParse('${f['logged_by']}') == _me;
    final lph = f['litres_per_hour'];
    final high = f['above_normal'] == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: aLine))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_short(f['log_date']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: aText)),
          const SizedBox(width: 10),
          Text('${_num(f['liters_filled'])} L', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(_rupees(f['cost']), style: const TextStyle(fontSize: 13.5, color: aMuted)),
          const Spacer(),
          if (lph != null)
            Text('${_num(lph, 2)} L/h', style: TextStyle(fontSize: 13.5, fontWeight: high ? FontWeight.w800 : FontWeight.w500, color: high ? aRed : aMuted)),
        ]),
        const SizedBox(height: 3),
        Text(
          [
            '${f['logged_by_name'] ?? ''}',
            if (f['hours_since'] != null) '${_num(f['hours_since'])} h since last',
            if (f['cost_per_litre'] != null) '₹${_num(f['cost_per_litre'])} a litre',
          ].where((x) => x.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 12.5, color: aMuted),
        ),
        if (st == 'returned' && '${f['admin_note'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Returned: ${f['admin_note']}', style: const TextStyle(fontSize: 13, color: aRed))),
        if ('${f['notes'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 3), child: Text('${f['notes']}', style: const TextStyle(fontSize: 12.5, color: aMuted))),
        const SizedBox(height: 7),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (st == 'approved') const AChip.ok('Approved') else if (st == 'returned') const AChip.bad('Returned') else const AChip.wait('Waiting'),
          if (canApprove && st == 'pending') ...[
            SizedBox(height: 34, child: FilledButton(style: aPrimary(height: 34), onPressed: () => _decide(f, 'approved'), child: const Text('Approve'))),
            SizedBox(height: 34, child: OutlinedButton(style: aSecondary(height: 34), onPressed: () => _decide(f, 'returned'), child: const Text('Return'))),
          ],
          if (st == 'returned' && (mine || canApprove) && _canUpdate)
            SizedBox(height: 34, child: OutlinedButton(style: aSecondary(height: 34), onPressed: () => _form(f), child: const Text('Correct'))),
        ]),
      ]),
    );
  }
}

class _FillSheet extends StatefulWidget {
  final Map<String, dynamic>? edit;
  final dynamic meterNow;
  final dynamic since;
  const _FillSheet({this.edit, this.meterNow, this.since});
  @override
  State<_FillSheet> createState() => _FillSheetState();
}

class _FillSheetState extends State<_FillSheet> {
  late DateTime _date;
  late final TextEditingController _litres;
  late final TextEditingController _cost;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _date = DateTime.tryParse('${e?['log_date'] ?? ''}') ?? DateTime.now();
    String v(dynamic x) => x == null ? '' : '${double.tryParse('$x') ?? x}'.replaceAll(RegExp(r'\.0$'), '');
    _litres = TextEditingController(text: v(e?['liters_filled']));
    _cost = TextEditingController(text: v(e?['cost']));
    _notes = TextEditingController(text: '${e?['notes'] ?? ''}');
  }

  @override
  void dispose() {
    _litres.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = double.tryParse(_litres.text.trim());
    if (l == null || l <= 0) {
      setState(() => _error = 'Type how many litres were filled.');
      return;
    }
    final c = _cost.text.trim().isEmpty ? null : double.tryParse(_cost.text.trim());
    if (_cost.text.trim().isNotEmpty && c == null) {
      setState(() => _error = 'The cost should be a number.');
      return;
    }
    final body = {'log_date': _ymd(_date), 'liters_filled': l, 'cost': c, 'notes': _notes.text.trim()};
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.edit == null) {
        await AdminApi.post('/tractor/diesel-logs', body);
      } else {
        await AdminApi.put('/tractor/diesel-logs/${widget.edit!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.edit == null ? 'Add a fill-up' : 'Correct the fill-up', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (widget.edit?['admin_note'] != null) ...[
              const SizedBox(height: 6),
              Text('Returned: ${widget.edit!['admin_note']}', style: const TextStyle(color: aRed, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: aInput('Date', suffix: const Icon(Icons.calendar_today_outlined, size: 18)),
                child: Text(DateFormat('d MMM yyyy').format(_date), style: const TextStyle(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: _litres, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('Litres filled', hint: 'e.g. 60')),
            const SizedBox(height: 10),
            TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: aInput('Cost (₹), optional', hint: 'e.g. 5640')),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: aInput('Notes, optional', hint: 'e.g. filled at the Bhatkuli pump')),
            if (widget.meterNow != null) ...[
              const SizedBox(height: 10),
              ANote('Latest hour meter: ${_num(widget.meterNow)} h${widget.since != null ? '. ${_num(widget.since)} hours since the last fill-up.' : '.'}', icon: Icons.speed),
            ],
            const SizedBox(height: 10),
            AErrorBox(_error),
            const SizedBox(height: 10),
            FilledButton(style: aPrimary(), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save fill-up')),
          ]),
        ),
      ),
    );
  }
}
