// lib/screens/raw_material/rm_pay_screen.dart
//
// Pay a supplier: say it ("from CC account to Khalid Kutar transferred twelve thousand three hundred"),
// check the card, tap "Enter in Tally" – the app makes the Payment voucher in TallyPrime.
//  - Nothing is entered until you tap the button.
//  - The card shows what the supplier is owed and warns about anything unusual
//    (more than due, same amount again, already paid today, odd date, big/small amount...).
//  - If Tally is closed the entry waits and goes in by itself when Tally is open again.
//  - Admins only (and only the admins ticked in the menu, if you restrict it).
// API: /tally-payments (routes/tallyPayments.js).  Web counterpart: src/pages/RawMaterialPay.jsx.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../widgets/voice_allocation_sheet.dart';
import 'rm_common.dart';

class RmPayScreen extends StatefulWidget {
  const RmPayScreen({super.key});
  @override
  State<RmPayScreen> createState() => _RmPayScreenState();
}

class _RmPayScreenState extends State<RmPayScreen> {
  List<String> banks = [];
  List<String> suppliers = [];
  List<Map<String, dynamic>> recent = [];
  String? bank;
  String? supplier;
  List<String> supplierChoices = []; // other likely suppliers when the match is not certain
  bool supplierSure = true;
  final amountCtrl = TextEditingController();
  final narrCtrl = TextEditingController();
  final typeCtrl = TextEditingController();
  DateTime date = DateTime.now();
  String heard = '';
  Map<String, dynamic>? dues;
  List<Map<String, dynamic>> warns = [];
  String? error;
  String? notice;
  bool loading = true;
  bool busy = false;
  bool forbidden = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    amountCtrl.dispose();
    narrCtrl.dispose();
    typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final o = Map<String, dynamic>.from(await RmApi.get('/tally-payments/options') as Map);
      banks = (o['banks'] as List).map((e) => e.toString()).toList();
      suppliers = (o['suppliers'] as List).map((e) => e.toString()).toList();
      await _loadRecent();
    } on RmApiException catch (e) {
      if (e.status == 403) {
        forbidden = true;
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadRecent() async {
    try {
      final r = await RmApi.get('/tally-payments', query: {'limit': '15'});
      recent = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
  }

  double get _amount => double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
  bool get _ready => bank != null && supplier != null && _amount > 0 && !busy;

  // ── what was said ──────────────────────────────────────────────────
  Future<void> _speak() async {
    final res = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VoiceAllocationSheet(
        dateStr: isoDay(DateTime.now()),
        idaGreen: rmGreen,
        endpoint: '/tally-payments/parse',
        title: 'Say the payment',
        hint: 'Say the account, the supplier and the amount. Example: "From CC account to Khalid Kutar transferred twelve thousand three hundred". '
            'You can add a date: "yesterday" or "20 Oct".',
      ),
    );
    if (res == null || !mounted) return;
    _applyParsed(Map<String, dynamic>.from(res));
  }

  Future<void> _typed() async {
    final t = typeCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = Map<String, dynamic>.from(await RmApi.post('/tally-payments/parse', {'transcript': t}) as Map);
      _applyParsed(r);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  void _applyParsed(Map<String, dynamic> r) {
    final b = r['bank'] is Map ? Map<String, dynamic>.from(r['bank'] as Map) : <String, dynamic>{};
    final s = r['supplier'] is Map ? Map<String, dynamic>.from(r['supplier'] as Map) : <String, dynamic>{};
    setState(() {
      heard = (r['heard'] ?? '').toString();
      bank = b['ledger']?.toString();
      supplier = s['ledger']?.toString();
      supplierSure = s['sure'] == true;
      supplierChoices = ((s['candidates'] as List?) ?? const []).map((e) => e.toString()).toList();
      final a = r['amount'];
      amountCtrl.text = a == null ? '' : (toD(a) == toD(a).roundToDouble() ? toD(a).round().toString() : toD(a).toStringAsFixed(2));
      narrCtrl.text = (r['narration'] ?? '').toString();
      final d = DateTime.tryParse((r['date'] ?? '').toString());
      if (d != null) date = d;
      dues = r['dues'] is Map ? Map<String, dynamic>.from(r['dues'] as Map) : null;
      warns = ((r['warnings'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      notice = null;
      error = null;
    });
  }

  // ── keep the dues card and warnings in step with the card ──────────
  void _recheckSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _recheck);
  }

  Future<void> _recheck() async {
    if (supplier == null) {
      setState(() {
        dues = null;
        warns = [];
      });
      return;
    }
    try {
      final r = Map<String, dynamic>.from(await RmApi.post('/tally-payments/check', {
        'supplier': supplier,
        'amount': _amount,
        'date': isoDay(date),
      }) as Map);
      if (!mounted) return;
      setState(() {
        dues = r['dues'] is Map ? Map<String, dynamic>.from(r['dues'] as Map) : null;
        warns = ((r['warnings'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _pickSupplier() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SupplierPicker(all: suppliers, first: supplierChoices),
    );
    if (picked == null) return;
    setState(() {
      supplier = picked;
      supplierSure = true;
      if (narrCtrl.text.trim().isEmpty || narrCtrl.text.startsWith('Kutar payment to')) {
        narrCtrl.text = 'Kutar payment to ${_short(picked)}';
      }
    });
    _recheck();
  }

  String _short(String ledger) {
    const filler = {'kutarwale', 'kutarwala', 'kutar', 'kastakar', 'dadhi', 'bhai', 'bhau', 'seth', 'sheth', 'ji', 'sir'};
    final parts = ledger.split(RegExp(r'\s+')).where((w) => !filler.contains(w.toLowerCase())).toList();
    return parts.isEmpty ? ledger : parts.join(' ');
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime.now().subtract(const Duration(days: 120)),
      lastDate: DateTime.now(),
    );
    if (p == null) return;
    setState(() => date = p);
    _recheck();
  }

  // ── enter it ───────────────────────────────────────────────────────
  Future<void> _submit() async {
    final strong = warns.where((w) => w['level'] == 'warn').toList();
    if (strong.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Please check'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final w in strong) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('• ${w['text']}')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Go back')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enter anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final r = Map<String, dynamic>.from(await RmApi.post('/tally-payments', {
        'bank': bank,
        'supplier': supplier,
        'amount': _amount,
        'date': isoDay(date),
        'narration': narrCtrl.text.trim(),
        'spoken': heard,
      }) as Map);
      final st = r['status'];
      if (!mounted) return;
      setState(() {
        if (st == 'posted') {
          notice = 'Entered in Tally: ${inr(_amount)} to ${_short(supplier!)}.';
        } else if (st == 'queued') {
          notice = 'Tally is not open. The payment of ${inr(_amount)} is saved and will go into Tally by itself when Tally is open.';
        } else {
          error = 'Tally did not accept it: ${r['message'] ?? 'unknown reason'}. It is listed below; check the details and try again.';
        }
        if (st != 'failed') _clear();
      });
      await _loadRecent();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  void _clear() {
    bank = null;
    supplier = null;
    supplierChoices = [];
    supplierSure = true;
    amountCtrl.clear();
    narrCtrl.clear();
    typeCtrl.clear();
    heard = '';
    dues = null;
    warns = [];
    date = DateTime.now();
  }

  Future<void> _act(Map<String, dynamic> row, String what) async {
    setState(() => busy = true);
    try {
      await RmApi.post('/tally-payments/${row['id']}/$what');
      await _loadRecent();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
  }

  // ── who may enter payments ─────────────────────────────────────────
  Future<void> _access() async {
    try {
      final a = Map<String, dynamic>.from(await RmApi.get('/tally-payments/access/list') as Map);
      final admins = (a['admins'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ticked = <int>{...((a['ticked'] as List?) ?? const []).map((e) => (e as num).toInt())};
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(builder: (c, setD) {
          return AlertDialog(
            title: const Text('Who can enter payments'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Tick the admins who may enter supplier payments. If nobody is ticked, every admin can.', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final u in admins)
                  CheckboxListTile(
                    dense: true,
                    value: ticked.contains((u['id'] as num).toInt()),
                    title: Text('${u['name']}'),
                    onChanged: (v) => setD(() => v == true ? ticked.add((u['id'] as num).toInt()) : ticked.remove((u['id'] as num).toInt())),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
            ],
          );
        }),
      );
      if (ok == true) {
        await RmApi.put('/tally-payments/access/list', {'ids': ticked.toList()});
        if (mounted) setState(() => notice = 'Saved.');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  // ── screen ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rmBg,
      appBar: AppBar(
        title: const Text('Pay supplier'),
        backgroundColor: rmAppBar,
        foregroundColor: Colors.white,
        actions: [
          if (!forbidden && !loading)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'access') _access();
              },
              itemBuilder: (_) => const [PopupMenuItem<String>(value: 'access', child: Text('Who can enter payments'))],
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : forbidden
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Only admins who are allowed to enter supplier payments can use this screen.', style: TextStyle(fontSize: 15)),
                )
              : RefreshIndicator(onRefresh: () async { await _loadRecent(); if (mounted) setState(() {}); }, child: _body()),
    );
  }

  Widget _body() {
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 28), children: [
      if (error != null) RmErrorBox(error!),
      if (notice != null)
        RmCard(
          color: const Color(0xFFF3F8EE),
          borderColor: const Color(0xFFCFE3C0),
          child: Text(notice!, style: const TextStyle(fontSize: 13.5, color: Color(0xFF1F4A0E), fontWeight: FontWeight.w600)),
        ),
      if (!kIsWeb)
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: rmGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: busy ? null : _speak,
            icon: const Icon(Icons.mic, color: Colors.white),
            label: const Text('Say the payment', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: typeCtrl,
            decoration: InputDecoration(
              hintText: 'or type: cc to Khalid 12300',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: rmBorder)),
            ),
            onSubmitted: (_) => _typed(),
          ),
        ),
        IconButton(onPressed: busy ? null : _typed, icon: const Icon(Icons.arrow_forward)),
      ]),
      if (heard.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Heard: "$heard"', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ),
      const RmSectionLabel('Check and enter'),
      RmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('From account'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: bank == null ? const Color(0xFFE08A3C) : rmBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: banks.contains(bank) ? bank : null,
                hint: const Text('Choose the bank account'),
                items: [for (final b in banks) DropdownMenuItem<String>(value: b, child: Text(b))],
                onChanged: (v) => setState(() => bank = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _label('Supplier'),
          InkWell(
            onTap: _pickSupplier,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: supplier == null || !supplierSure ? const Color(0xFFE08A3C) : rmBorder),
              ),
              child: Row(children: [
                Expanded(child: Text(supplier ?? 'Choose the supplier', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: supplier == null ? Colors.grey.shade600 : const Color(0xFF1E4012)))),
                const Icon(Icons.search, size: 20),
              ]),
            ),
          ),
          if (supplier != null && !supplierSure)
            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Not sure this is the right supplier. Tap to choose.', style: TextStyle(fontSize: 12, color: Color(0xFF7A4D00)))),
          if (!supplierSure && supplierChoices.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final c in supplierChoices.where((c) => c != supplier))
                  ActionChip(
                    label: Text(c, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() {
                        supplier = c;
                        supplierSure = true;
                        narrCtrl.text = 'Kutar payment to ${_short(c)}';
                      });
                      _recheck();
                    },
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Amount (₹)'),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  onChanged: (_) {
                    setState(() {});
                    _recheckSoon();
                  },
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Date'),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: Colors.white),
                  onPressed: _pickDate,
                  child: Text(dmy(isoDay(date))),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          _label('Narration'),
          TextField(
            controller: narrCtrl,
            maxLength: 250,
            decoration: InputDecoration(isDense: true, filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), counterText: ''),
          ),
        ]),
      ),
      if (dues != null) _duesCard(dues!),
      for (final w in warns)
        RmCard(
          color: w['level'] == 'warn' ? const Color(0xFFFFF7EA) : const Color(0xFFF3F8EE),
          borderColor: w['level'] == 'warn' ? const Color(0xFFF3D7A6) : const Color(0xFFCFE3C0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(w['level'] == 'warn' ? Icons.warning_amber_rounded : Icons.info_outline, size: 20, color: w['level'] == 'warn' ? const Color(0xFF7A4D00) : rmGreen),
            const SizedBox(width: 8),
            Expanded(child: Text('${w['text']}', style: const TextStyle(fontSize: 13))),
          ]),
        ),
      SizedBox(
        height: 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: rmAppBar, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: _ready ? _submit : null,
          child: Text(busy ? 'Please wait…' : 'Enter in Tally', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('Nothing is entered until you tap the button.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Color(0xFF5F6A58))),
      ),
      if (recent.isNotEmpty) ...[
        const RmSectionLabel('Recent entries'),
        for (final r in recent) _recentRow(r),
      ],
    ]);
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF5F6A58))));

  Widget _duesCard(Map<String, dynamic> d) {
    final bal = toD(d['balance']);
    final slips = toD(d['slips_since_payment']).round();
    final last = (d['last_payments'] as List?) ?? const [];
    return RmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(bal < -0.004 ? 'Paid in advance' : 'Due to this supplier', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          Text(inr(bal.abs()), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: rmDark)),
        ]),
        const SizedBox(height: 4),
        Text(
          '$slips weigh slip${slips == 1 ? '' : 's'} since the last payment · ${mt(d['qty_since_payment'])} MT · ${inr(d['net_since_payment'])}'
          '${d['last_payment_date'] != null ? ' · last paid ${dmy(d['last_payment_date'])}' : ''}',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
        ),
        if (last.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Earlier: ${last.take(3).map((e) => '${dm((e as Map)['date'])} ${inr(e['amount'])}').join(' · ')}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
      ]),
    );
  }

  Widget _recentRow(Map<String, dynamic> r) {
    final st = (r['status'] ?? '').toString();
    final color = st == 'posted' ? rmGreen : st == 'queued' ? const Color(0xFF7A4D00) : st == 'cancelled' ? Colors.grey : const Color(0xFF9E2419);
    final label = st == 'posted' ? 'In Tally' : st == 'queued' ? 'Waiting for Tally' : st == 'cancelled' ? 'Cancelled' : 'Not accepted';
    return RmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${r['supplier']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          Text(inr(r['amount']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 2),
        Text('${dmy(r['voucher_date'])} · ${r['bank_ledger']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ),
          const Spacer(),
          if (st == 'queued' || st == 'failed') ...[
            TextButton(onPressed: busy ? null : () => _act(r, 'retry'), child: const Text('Try now')),
            TextButton(onPressed: busy ? null : () => _act(r, 'cancel'), child: const Text('Cancel')),
          ],
        ]),
        if (st == 'failed' && r['message'] != null) Text('${r['message']}', style: const TextStyle(fontSize: 12, color: Color(0xFF9E2419))),
      ]),
    );
  }
}

// Searchable list of the suppliers (likely ones first).
class _SupplierPicker extends StatefulWidget {
  final List<String> all;
  final List<String> first;
  const _SupplierPicker({required this.all, required this.first});
  @override
  State<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<_SupplierPicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final lower = q.trim().toLowerCase();
    final rest = widget.all.where((s) => !widget.first.contains(s)).toList();
    final list = lower.isEmpty ? [...widget.first, ...rest] : widget.all.where((s) => s.toLowerCase().contains(lower)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Find a supplier', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => ListTile(title: Text(list[i]), onTap: () => Navigator.pop(context, list[i])),
            ),
          ),
        ]),
      ),
    );
  }
}
