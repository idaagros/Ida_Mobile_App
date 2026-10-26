// lib/screens/factory/pellet_production_screen.dart
//
// Pellets made (run hours x tonnes per hour), pellets dispatched and pellet stock.
// Nothing is typed daily. If the supervisor's run entries and the machine hour meter differ by more than 1 hour a day,
// the meter is used and the day is shown in orange. Admins set the opening stock and the tonnes-per-hour rate here.
// Server: /pellet (routes/pellet.js). Web: pages/PelletProduction.jsx.

import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/api_service.dart';

const Color _green = Color(0xFF3B7A28);
const Color _dark = Color(0xFF1E4012);
const Color _amber = Color(0xFF8A5A00);
const Color _amberBg = Color(0xFFFDF0D5);

String _t1(num? v) => v == null ? '–' : v.toStringAsFixed(1);
String _t2(num? v) => v == null ? '–' : v.toStringAsFixed(2);
String _dmy(String s) {
  final p = s.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : s;
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _src = {
  'runs': 'Run entries',
  'meter': 'Machine meter',
  'runs_estimated': 'Estimated (meter not read yet)',
  'closed': 'Plant closed',
  'none': 'No run',
};
const _flagText = {
  'meter_differs': 'Run entries and machine meter differ by more than 1 hour. The meter was used. Please check the supervisor’s entry.',
  'no_run_entry': 'Meter shows running but no run was entered. The meter was used.',
};

class PelletProductionScreen extends StatefulWidget {
  const PelletProductionScreen({super.key});
  @override
  State<PelletProductionScreen> createState() => _PelletProductionScreenState();
}

class _PelletProductionScreenState extends State<PelletProductionScreen> {
  Map<String, dynamic>? _d;
  String _range = 'month';
  late String _from;
  late String _to;
  bool _busy = false;
  bool _admin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = _iso(DateTime(n.year, n.month, 1));
    _to = _iso(n);
    ApiService.isAdmin().then((v) {
      if (mounted) setState(() => _admin = v);
    });
    _load();
  }

  void _pick(String k) {
    final n = DateTime.now();
    setState(() {
      _range = k;
      if (k == 'week') {
        _from = _iso(n.subtract(const Duration(days: 6)));
        _to = _iso(n);
      } else if (k == 'month') {
        _from = _iso(DateTime(n.year, n.month, 1));
        _to = _iso(n);
      } else if (k == 'last') {
        _from = _iso(DateTime(n.year, n.month - 1, 1));
        _to = _iso(DateTime(n.year, n.month, 0));
      } else if (k == 'season') {
        final s = (_d?['stock'] as Map?)?['since'];
        if (s != null) _from = '$s';
        _to = _iso(n);
      }
    });
    _load();
  }

  Future<void> _pickDate(bool isFrom) async {
    final cur = DateTime.tryParse(isFrom ? _from : _to) ?? DateTime.now();
    final r = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)));
    if (r == null) return;
    setState(() {
      _range = 'custom';
      if (isFrom) {
        _from = _iso(r);
        if (_from.compareTo(_to) > 0) _to = _from;
      } else {
        _to = _iso(r);
        if (_to.compareTo(_from) < 0) _from = _to;
      }
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.json('GET', '/pellet/overview', query: {'from': _from, 'to': _to});
      if (r is! Map || r['stock'] == null) throw ApiException('The server did not answer. Check that server.js has the /api/pellet line and restart it.');
      if (mounted) setState(() => _d = Map<String, dynamic>.from(r));
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    final st = Map<String, dynamic>.from(_d!['stock'] as Map);
    final op = TextEditingController(text: '${st['opening_mt'] ?? ''}'.replaceAll(RegExp(r'\.0+$'), ''));
    final rate = TextEditingController(text: '${_d!['rate_now'] ?? ''}');
    String rateFrom = _iso(DateTime.now());
    final rates = ((_d!['rates'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Opening stock and rate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Text('Opening pellet stock (tonnes) on ${_dmy('${st['since']}')}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(controller: op, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                  onPressed: () async {
                    final v = op.text.trim().replaceAll(',', '');
                    if (v.isNotEmpty && double.tryParse(v) == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Type the opening stock as a number of tonnes.')));
                      return;
                    }
                    await _saveSettings({'opening_mt': v.isEmpty ? '' : double.parse(v)}, ctx);
                  },
                  child: const Text('Save opening stock'),
                ),
              ),
              const Divider(height: 28),
              const Text('Tonnes per run hour', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(width: 90, child: TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true))),
                const SizedBox(width: 10),
                const Text('from'),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final r = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(rateFrom) ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (r != null) setM(() => rateFrom = _iso(r));
                  },
                  child: Text(_dmy(rateFrom)),
                ),
              ]),
              const SizedBox(height: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
                onPressed: () async {
                  final v = double.tryParse(rate.text.trim());
                  if (v == null || v <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Type tonnes per hour, for example 1.5')));
                    return;
                  }
                  await _saveSettings({'rate': v, 'rate_from': rateFrom}, ctx);
                },
                child: const Text('Save rate'),
              ),
              const SizedBox(height: 8),
              if (rates.isEmpty) const Text('No rate saved yet – 1.5 t/h is used for every day.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              for (final r in rates)
                Row(children: [
                  Expanded(child: Text('${_dmy('${r['from']}')} onward: ${r['tph']} t/h', style: const TextStyle(fontSize: 13))),
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (c) => AlertDialog(
                          title: const Text('Remove this rate?'),
                          content: Text('The rate that starts on ${_dmy('${r['from']}')} will be removed. The one before it applies again.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        await Api.json('DELETE', '/pellet/rate/${r['from']}');
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                      } catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(Api.errorText(e))));
                      }
                    },
                    child: const Text('remove', style: TextStyle(color: Colors.red)),
                  ),
                ]),
              const Text('Earlier days keep the rate they were made at.', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _saveSettings(Map<String, dynamic> body, BuildContext ctx) async {
    try {
      await Api.json('PUT', '/pellet/settings', body: body);
      if (ctx.mounted) Navigator.pop(ctx);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved.')));
      _load();
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(Api.errorText(e))));
    }
  }

  Widget _tile(String label, String value, String sub, {bool warn = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: warn ? const Color(0xFFE0A13A) : const Color(0xFFCFDDC3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final totals = d == null ? null : Map<String, dynamic>.from(d['totals'] as Map);
    final st = d == null ? null : Map<String, dynamic>.from(d['stock'] as Map);
    final days = d == null ? <Map<String, dynamic>>[] : (d['days'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
    final flagged = days.where((x) => x['flag'] != null).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F3),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Pellet production', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_admin && d != null) IconButton(tooltip: 'Opening stock and rate', icon: const Icon(Icons.tune), onPressed: _settings),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _busy ? null : _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(14), children: [
          Wrap(spacing: 8, children: [
            for (final e in const [['week', 'Last 7 days'], ['month', 'This month'], ['last', 'Last month'], ['season', 'This season']])
              ChoiceChip(label: Text(e[1]), selected: _range == e[0], onSelected: (_) => _pick(e[0])),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _pickDate(true), child: Text(_dmy(_from)))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to')),
            Expanded(child: OutlinedButton(onPressed: () => _pickDate(false), child: Text(_dmy(_to)))),
          ]),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: Color(0xFF8A1C1C))),
            ),
          if (d != null && totals != null && st != null) ...[
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _tile('Pellets made', '${_t1(totals['made_mt'] as num?)} t', '${_t1(totals['hours'] as num?)} run hours · ${totals['run_days']} days'),
                _tile('Dispatched', '${_t1(totals['dispatched_mt'] as num?)} t', '${totals['trucks']} trucks'),
                _tile('Pellet stock now', '${_t1(st['stock_mt'] as num?)} t', st['negative'] == true ? 'Below zero – check opening stock' : 'since ${_dmy('${st['since']}')}', warn: st['negative'] == true),
                _tile('Making per day (14 d)', '${_t1(st['made_per_day_mt'] as num?)} t', (st['flagged_days'] ?? 0) > 0 ? '${st['flagged_days']} day(s) to check this season' : 'Looks consistent', warn: (st['flagged_days'] ?? 0) > 0),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCFDDC3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Stock since ${_dmy('${st['since']}')}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (st['season_custom'] != true) const Text('Season start not set – using 1 April (set it in Raw material).', style: TextStyle(color: _amber, fontSize: 12)),
                const SizedBox(height: 4),
                Text('Opening ${_t1(st['opening_mt'] as num?)} t + made ${_t1(st['made_mt'] as num?)} t − dispatched ${_t1(st['dispatched_mt'] as num?)} t = ${_t1(st['stock_mt'] as num?)} t'),
                Text('Rate now: ${d['rate_now']} t per run hour', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                if (_admin) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _settings, child: const Text('Opening stock and rate'))),
              ]),
            ),
            if (flagged.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _amberBg, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${flagged.length} day(s) in this period to check', style: const TextStyle(fontWeight: FontWeight.w800, color: _amber)),
                  for (final f in flagged.take(6)) Text('${_dmy('${f['date']}')}: run entries ${_t2(f['run_hours'] as num?)} h, meter ${_t2(f['meter_hours'] as num?)} h – meter used', style: const TextStyle(fontSize: 13)),
                  if (flagged.length > 6) Text('and ${flagged.length - 6} more', style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            for (final x in days)
              Opacity(
                opacity: x['future'] == true ? 0.4 : 1,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: x['flag'] != null ? const Color(0xFFE0A13A) : const Color(0xFFE3EBDC))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(_dmy('${x['date']}'), style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text('${_t1(x['tonnes'] as num?)} t made', style: const TextStyle(fontWeight: FontWeight.w800, color: _dark)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '${_t2(x['hours'] as num?)} h × ${x['tph']} t/h · ${_src['${x['source']}'] ?? x['source']}'
                      '${(x['dispatched_mt'] ?? 0) > 0 ? ' · dispatched ${_t1(x['dispatched_mt'] as num?)} t' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    if (x['source'] != 'closed' && (x['run_hours'] != null) && (x['meter_hours'] != null))
                      Text('Run entries ${_t2(x['run_hours'] as num?)} h · meter ${_t2(x['meter_hours'] as num?)} h', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    if (x['flag'] != null) Text(_flagText['${x['flag']}'] ?? '', style: const TextStyle(fontSize: 12, color: _amber)),
                  ]),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}
