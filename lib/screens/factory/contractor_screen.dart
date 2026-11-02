// lib/screens/factory/contractor_screen.dart — Contractor payment (Nov 2026)
//
// The operator is paid per tonne of pellets MADE. The rate (with a "from date"), the start date and the advances are typed here;
// the screen shows what has been earned, the advances and what is due. Pellets made come from Pellet production (factory run
// hours x tonnes per hour, includes the run open now); the screen re-reads itself every 15 minutes. A check compares pellets
// made with pellets sold in Tally (Sales ledger) and dispatched (Outward register): warnings only.
// Who: admins, and users ticked for "Contractor payment" in Users & permissions (View, Add = advances, Edit = settings / rate, Delete).
// API: /contractor (routes/contractor.js).  Web counterpart: src/pages/Contractor.jsx.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_model.dart';
import '../../services/api_client.dart';

const _kKey = 'contractor';
const _green = Color(0xFF1E4012);
const _line = Color(0xFFE0E7D8);

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _group(String digits) {
  // Indian grouping: 12,34,567
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String _rs(dynamic v) {
  if (v == null) return '–';
  final x = _d(v).round();
  return '${x < 0 ? '-' : ''}₹${_group(x.abs().toString())}';
}

String _nf(dynamic v, [int dec = 2]) {
  if (v == null) return '–';
  final x = _d(v);
  if (x == x.roundToDouble()) return x.round().toString();
  return x.toStringAsFixed(dec).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

String _dmy(dynamic iso) {
  final s = '${iso ?? ''}';
  return s.length >= 10 ? '${s.substring(8, 10)}-${s.substring(5, 7)}-${s.substring(0, 4)}' : s;
}

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _monthName(String m) => m.length >= 7 ? '${_months[(int.tryParse(m.substring(5, 7)) ?? 1) - 1]} ${m.substring(0, 4)}' : m;

class ContractorScreen extends StatefulWidget {
  const ContractorScreen({super.key});
  @override
  State<ContractorScreen> createState() => _ContractorScreenState();
}

class _ContractorScreenState extends State<ContractorScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _msg;
  bool _busy = false;
  bool _mayAdd = false, _mayEdit = false, _mayDelete = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _perms();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _perms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final admin = prefs.getBool('is_admin') ?? (prefs.getString('role') == 'admin');
      final perms = parsePermissions(jsonDecode(prefs.getString('permissions') ?? '[]'));
      if (mounted) {
        setState(() {
          _mayAdd = admin || hasAddAccess(perms, _kKey);
          _mayEdit = admin || hasUpdateAccess(perms, _kKey);
          _mayDelete = admin || hasDeleteAccess(perms, _kKey);
        });
      }
    } catch (_) {}
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await Api.json('GET', '/contractor/overview');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(r as Map);
        if (!silent) _error = null;
      });
    } catch (e) {
      if (!silent && mounted) setState(() => _error = Api.errorText(e));
    }
  }

  Future<bool> _run(Future<dynamic> Function() fn, [String? ok]) async {
    setState(() {
      _busy = true;
      _error = null;
      _msg = null;
    });
    try {
      final r = await fn();
      if (!mounted) return true;
      setState(() {
        if (r is Map && r['rates'] != null) _data = Map<String, dynamic>.from(r);
        if (ok != null) _msg = ok;
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = Api.errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _form(String title, List<_CFld> fields, String button, {String? top}) {
    return showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CForm(title: title, fields: fields, button: button, top: top),
    );
  }

  Future<void> _advance([Map<String, dynamic>? a]) async {
    final r = await _form(a == null ? 'New advance' : 'Edit advance', [
      _CFld('date', 'Date', date: true, initial: a == null ? _iso(DateTime.now()) : '${a['date']}'),
      _CFld('amount', 'Amount given (₹)', number: true, initial: a == null ? '' : _nf(a['amount'])),
      _CFld('note', 'Note (optional)', initial: a == null ? '' : '${a['note'] ?? ''}'),
    ], a == null ? 'Add advance' : 'Save');
    if (r == null) return;
    final body = {'date': r['date'], 'amount': double.tryParse(r['amount'] ?? '') ?? 0, 'note': r['note'] ?? ''};
    if (a == null) {
      await _run(() => Api.json('POST', '/contractor/advances', body: body), 'Advance added.');
    } else {
      await _run(() => Api.json('PUT', '/contractor/advances/${a['id']}', body: body), 'Saved.');
    }
  }

  Future<void> _rate() async {
    final d = _data ?? {};
    final r = await _form('Rate per tonne', [
      _CFld('rate', 'Rate (₹ per tonne of pellets made)', number: true, initial: d['rate_now'] == null ? '' : _nf(d['rate_now'])),
      _CFld('from_date', 'Applies from', date: true, initial: '${d['start_date'] ?? _iso(DateTime.now())}'),
    ], 'Save rate', top: 'Days before the "applies from" date keep their old rate.');
    if (r == null) return;
    await _run(() => Api.json('POST', '/contractor/rates', body: {'from_date': r['from_date'], 'rate': double.tryParse(r['rate'] ?? '') ?? 0}), 'Rate saved.');
  }

  Future<void> _settings() async {
    final d = _data ?? {};
    final r = await _form('Settings', [
      _CFld('name', 'Operator name', initial: '${d['name'] ?? ''}'),
      _CFld('start_date', 'Contract started on', date: true, initial: '${d['start_date'] ?? ''}'),
      _CFld('opening_pellets_mt', 'Pellets in hand on that date (tonnes)', number: true, initial: _nf(d['opening_pellets_mt'])),
      _CFld('sales_ledger', 'Tally sales ledger', initial: '${d['sales_ledger'] ?? 'Sales'}'),
    ], 'Save', top: 'Earnings are counted from the start date. The sales ledger is used only to check against Tally sales (Factory books has its list).');
    if (r == null) return;
    await _run(
        () => Api.json('PUT', '/contractor/settings', body: {
              'name': r['name'],
              'start_date': r['start_date'],
              'opening_pellets_mt': double.tryParse(r['opening_pellets_mt'] ?? '') ?? 0,
              'sales_ledger': r['sales_ledger'],
            }),
        'Saved.');
  }

  Future<bool> _confirm(String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return ok == true;
  }

  Widget _card({required Widget child, Color? border, EdgeInsets? pad}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: pad ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: border ?? _line)),
        child: child,
      );

  Widget _stat(String l, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
        ),
      );

  Widget _kv(String l, String v, {Color? color}) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          Text(v, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ]),
      );

  Widget _head(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Contractor payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (_mayEdit && d != null) IconButton(icon: const Icon(Icons.currency_rupee), tooltip: 'Rate', onPressed: _rate),
          if (_mayEdit && d != null) IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Settings', onPressed: _settings),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load()),
        ],
      ),
      floatingActionButton: (_mayAdd && d != null && d['ready'] == true)
          ? FloatingActionButton.extended(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              onPressed: _busy ? null : () => _advance(),
              icon: const Icon(Icons.add),
              label: const Text('Advance'))
          : null,
      body: d == null
          ? Center(
              child: _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center))
                  : const CircularProgressIndicator(color: _green))
          : RefreshIndicator(onRefresh: () => _load(), child: _body(d)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final ready = d['ready'] == true;
    final warnings = ((d['warnings'] as List?) ?? const []).map((e) => '$e').toList();
    final months = ((d['months'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final advs = ((d['advances'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final days = ((d['days'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final rates = ((d['rates'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final chk = d['check'] is Map ? Map<String, dynamic>.from(d['check'] as Map) : <String, dynamic>{};
    final due = _d(d['due']);
    final owed = due >= 0;
    final sub = '${d['name'] ?? ''}${d['rate_now'] != null ? ' · ₹${_nf(d['rate_now'])} per tonne made' : ''}${d['start_date'] != null ? ' · from ${_dmy(d['start_date'])}' : ''}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: [
        Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 10),
        if (_error != null) _card(border: const Color(0xFFE7B4B0), child: Text(_error!, style: const TextStyle(color: Color(0xFFB71C1C)))),
        if (_msg != null) _card(border: const Color(0xFFCFE3C0), child: Text(_msg!, style: const TextStyle(color: Color(0xFF1F4A0E)))),
        if (!ready)
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Set up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text('${d['need'] ?? ''}'),
            const SizedBox(height: 10),
            if (_mayEdit)
              Wrap(spacing: 8, children: [
                ElevatedButton(onPressed: _settings, style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white), child: const Text('Settings')),
                OutlinedButton(onPressed: _rate, child: const Text('Enter rate')),
              ])
            else
              const Text('Ask an admin to complete the set-up.', style: TextStyle(color: Colors.grey)),
          ]))
        else ...[
          if (d['live'] == true)
            _card(
                border: const Color(0xFFCFE3C0),
                pad: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: const Text('Plant running now. Figures include today\'s run so far and refresh every 15 minutes.', style: TextStyle(color: Color(0xFF1F4A0E), fontSize: 13))),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: owed ? const Color(0xFF2E7D32) : const Color(0xFFC62828), width: 1.5)),
            child: Column(children: [
              Text(owed ? 'Due to the operator' : 'Paid more than earned (to be adjusted)', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(_rs(due.abs()), style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: owed ? const Color(0xFF1F4A0E) : const Color(0xFFC62828)))),
              Text('earned ${_rs(d['earned'])} − advances ${_rs(d['advances_total'])}', style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
            ]),
          ),
          Row(children: [_stat('Pellets made', '${_nf(d['made_t'])} t'), _stat('Earned', _rs(d['earned']))]),
          const SizedBox(height: 8),
          Row(children: [_stat('Advances', _rs(d['advances_total'])), _stat('Avg per tonne', d['avg_per_tonne'] == null ? '–' : _rs(d['avg_per_tonne']))]),
          const SizedBox(height: 12),
          _card(
              border: warnings.isNotEmpty ? const Color(0xFFECD9A4) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _head('Check against sales'),
                Wrap(runSpacing: 8, children: [
                  _kv('In hand at start', '${_nf(chk['opening_mt'])} t'),
                  _kv('Made', '${_nf(chk['made_mt'])} t'),
                  _kv('Sold (Tally)', chk['sold_ok'] == true ? '${_nf(chk['sold_mt'])} t' : '–'),
                  _kv('Dispatched (outward)', '${_nf(chk['dispatched_mt'])} t'),
                  _kv('Should remain', chk['sold_ok'] == true ? '${_nf(chk['remaining_mt'])} t' : '–', color: chk['sold_ok'] == true && _d(chk['remaining_mt']) < 0 ? const Color(0xFFC62828) : null),
                ]),
                const SizedBox(height: 4),
                const Text('Should remain = in hand at start + made − sold', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                if (chk['tally_read_to'] != null)
                  Text('Tally read up to ${_dmy(chk['tally_read_to'])} (sales ledger "${d['sales_ledger']}"). "Read Tally now" in Factory books (web) refreshes it.', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                const SizedBox(height: 8),
                if (warnings.isEmpty)
                  const Text('✓ Nothing unusual: made, sold and dispatched agree.', style: TextStyle(color: Color(0xFF1F4A0E), fontSize: 13))
                else
                  for (final w in warnings)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFFFF8E6), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFECD9A4))),
                      child: Text('⚠ $w', style: const TextStyle(color: Color(0xFF6B4A00), fontSize: 13)),
                    ),
              ])),
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _head('Month by month'),
            for (final m in months)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_monthName('${m['month']}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${_nf(m['tonnes'], 1)} t · advances ${_rs(m['advances'])}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                      ])),
                  Expanded(
                      flex: 2,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(_rs(m['balance']), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('earned ${_rs(m['earned'])}', style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                      ])),
                ]),
              ),
          ])),
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _head('Advances'),
            if (advs.isEmpty) const Text('No advances yet.', style: TextStyle(color: Colors.grey)),
            for (final a in advs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_rs(a['amount'])}  ·  ${_dmy(a['date'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if ('${a['note'] ?? ''}'.isNotEmpty) Text('${a['note']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ])),
                  if (_mayEdit) IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 19), onPressed: () => _advance(a)),
                  if (_mayDelete)
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 19, color: Colors.red),
                        onPressed: () async {
                          if (await _confirm('Delete this advance of ${_rs(a['amount'])}?')) {
                            await _run(() => Api.json('DELETE', '/contractor/advances/${a['id']}'), 'Advance deleted.');
                          }
                        }),
                ]),
              ),
          ])),
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _head('Recent days'),
            for (final x in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(flex: 3, child: Text('${_dmy(x['date'])}${x['live'] == true ? '  ● running' : ''}', style: TextStyle(fontSize: 13, color: x['live'] == true ? const Color(0xFF2E7D32) : null))),
                  Expanded(flex: 2, child: Text('${_nf(x['hours'], 1)} h', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 2, child: Text('${_nf(x['tonnes'])} t', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 3, child: Text(_rs(x['amount']), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ]),
              ),
          ])),
          _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _head('Rate history'),
            for (final r in rates)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text('from ${_dmy(r['from_date'])}')),
                  Text('₹${_nf(r['rate'])} / t', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (_mayDelete && rates.length > 1)
                    IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 19, color: Colors.red),
                        onPressed: () async {
                          if (await _confirm('Delete this rate? Those days will use the earlier rate.')) {
                            await _run(() => Api.json('DELETE', '/contractor/rates/${r['id']}'), 'Rate deleted.');
                          }
                        }),
                ]),
              ),
          ])),
        ],
      ],
    );
  }
}

class _CFld {
  final String key, label;
  final bool number, date;
  final String initial;
  _CFld(this.key, this.label, {this.number = false, this.date = false, this.initial = ''});
}

class _CForm extends StatefulWidget {
  final String title, button;
  final String? top;
  final List<_CFld> fields;
  const _CForm({required this.title, required this.fields, required this.button, this.top});
  @override
  State<_CForm> createState() => _CFormState();
}

class _CFormState extends State<_CForm> {
  late final Map<String, TextEditingController> _c = {for (final f in widget.fields) f.key: TextEditingController(text: f.initial)};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(_CFld f) async {
    final cur = DateTime.tryParse(_c[f.key]!.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 366)));
    if (p != null) setState(() => _c[f.key]!.text = _iso(p));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          if (widget.top != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(widget.top!, style: const TextStyle(color: Colors.grey, fontSize: 12.5))),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _c[f.key],
                readOnly: f.date,
                onTap: f.date ? () => _pick(f) : null,
                keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                decoration: InputDecoration(
                    labelText: f.label, border: const OutlineInputBorder(), isDense: true, suffixIcon: f.date ? const Icon(Icons.calendar_today, size: 18) : null),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(context, {for (final e in _c.entries) e.key: e.value.text.trim()}),
              child: Text(widget.button),
            ),
          ),
        ]),
      ),
    );
  }
}
