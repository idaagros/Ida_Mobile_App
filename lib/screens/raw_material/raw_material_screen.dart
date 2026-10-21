// lib/screens/raw_material/raw_material_screen.dart
//
// Raw material received and what is owed to each supplier, read from
// TallyPrime (same as the website's Raw material page):
//  - Tiles: received (tonnes, trucks), purchase value, paid, amount due, average rate
//  - Amount due by age (payments are matched to the oldest dues first)
//  - Things to check: a receipt number used twice, numbers missing from a
//    running series, trucks with no vehicle number, a balance that differs from Tally's
//  - Suppliers: received, rate, amount, paid, balance due; tap one for the ledger
// Tally is read every 15 minutes by the server; the Refresh button reads it now.
// API: GET /raw-material/summary, POST /raw-material/refresh.
// Web counterpart: src/pages/RawMaterial.jsx.

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'rm_common.dart';
import 'rm_party_screen.dart';

class RawMaterialScreen extends StatefulWidget {
  const RawMaterialScreen({super.key});
  @override
  State<RawMaterialScreen> createState() => _RawMaterialScreenState();
}

class _RawMaterialScreenState extends State<RawMaterialScreen> {
  bool loading = true;
  bool busy = false;
  bool isAdmin = false;
  bool showChecks = false;
  String? error;
  String? notice;
  Map<String, dynamic> data = {};
  String range = 'season';
  RmDates dates = rangeDates('season');
  String item = '';
  String search = '';
  String sort = 'balance';
  bool showOlder = false;
  bool showAcked = false;
  bool showRates = false;
  Map<String, dynamic> rates = {};
  Map<String, dynamic> stock = {};

  @override
  void initState() {
    super.initState();
    ApiService.isAdmin().then((v) {
      if (mounted) setState(() => isAdmin = v);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // 'This season' sends no dates: the server knows when the season starts.
      final q = <String, dynamic>{};
      if (range != 'season') {
        q['from'] = dates.from;
        q['to'] = dates.to;
      }
      if (item.isNotEmpty) q['item'] = item;
      final d = await RmApi.get('/raw-material/summary', query: q);
      if (!mounted) return;
      final m = Map<String, dynamic>.from(d as Map);
      // Rate board is a bonus: never let it break the main screen.
      try {
        final r = await RmApi.get('/raw-material/rates');
        rates = Map<String, dynamic>.from(r as Map);
      } catch (_) {}
      try {
        final r = await RmApi.get('/raw-material/stock');
        stock = Map<String, dynamic>.from(r as Map);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        data = m;
        final p = m['period'];
        if (range == 'season' && p is Map) dates = RmDates(p['from'].toString(), p['to'].toString());
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _refresh({bool full = false}) async {
    if (full) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Full resync'),
          content: const Text('Re-read the whole financial year from Tally? This can take a minute.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Re-read')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      busy = true;
      notice = null;
      error = null;
    });
    try {
      final r = await RmApi.post('/raw-material/refresh', full ? {'full': true} : {});
      final m = Map<String, dynamic>.from(r as Map);
      notice = m['skipped'] == true
          ? (m['reason'] ?? 'Just updated').toString()
          : 'Read from Tally: ${m['purchases']} purchases, ${m['entries']} ledger lines.';
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => busy = false);
    await _load();
  }

  // Admin: change when the season starts (screens open on "This season").
  Future<void> _changeSeason() async {
    final st = data['status'] is Map ? data['status'] as Map : const {};
    final current = parseDay(st['season_start']) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'Season starts on',
    );
    if (picked == null) return;
    try {
      await RmApi.put('/raw-material/season', {'start': isoDay(picked)});
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  List<Map<String, dynamic>> _parties() {
    final all = List<Map<String, dynamic>>.from(
        ((data['parties'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
    final q = search.trim().toLowerCase();
    // Suppliers with no purchase or payment in the period (only an older balance)
    // are tucked away; searching by name still finds them.
    final list = q.isEmpty
        ? all.where((p) => showOlder || p['active'] != false).toList()
        : all.where((p) => p['name'].toString().toLowerCase().contains(q)).toList();
    int cmp(String k, Map<String, dynamic> a, Map<String, dynamic> b) => toD(b[k]).compareTo(toD(a[k]));
    list.sort((a, b) {
      switch (sort) {
        case 'name':
          return a['name'].toString().compareTo(b['name'].toString());
        case 'qty':
          return cmp('qty_mt', a, b);
        case 'age':
          return cmp('oldest_days', a, b);
        default:
          return cmp('balance', a, b);
      }
    });
    return list;
  }

  String _rate(Map<String, dynamic> p) {
    if (p['avg_rate'] == null) return '—';
    final lo = p['rate_min'];
    final hi = p['rate_max'];
    if (lo != null && hi != null && toD(lo) != toD(hi)) return '${inr(lo)}–${toD(hi).round()}';
    return inr(p['avg_rate']);
  }

  Future<void> _open(String name) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RmPartyScreen(name: name)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] is Map ? Map<String, dynamic>.from(data['status'] as Map) : <String, dynamic>{};
    final hasData = status['last_ok_at'] != null;
    final t = data['totals'] is Map ? Map<String, dynamic>.from(data['totals'] as Map) : null;
    final items = ((data['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final parties = _parties();

    return Scaffold(
      backgroundColor: rmBg,
      appBar: AppBar(
        title: const Text('Raw material'),
        backgroundColor: rmAppBar,
        foregroundColor: Colors.white,
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh from Tally', onPressed: () => _refresh()),
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'full') _refresh(full: true);
              },
              itemBuilder: (_) => const [PopupMenuItem<String>(value: 'full', child: Text('Full resync'))],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Text(
              hasData ? 'From Tally · updated ${whenText(status['last_ok_at'])}' : 'Waiting for the first read from Tally',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            RmRangePicker(
              range: range,
              dates: dates,
              onChanged: (r, d) {
                setState(() {
                  range = r;
                  dates = d;
                });
                _load();
              },
            ),
            if (range == 'season' && isAdmin && status['season_start'] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _changeSeason,
                  child: Text('Season starts ${dmy(status['season_start'])} · change'),
                ),
              ),
            if (items.length > 1) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: rmBorder)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: item,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(value: '', child: Text('All materials')),
                      for (final i in items) DropdownMenuItem<String>(value: i['item'].toString(), child: Text(i['item'].toString())),
                    ],
                    onChanged: (v) {
                      setState(() => item = v ?? '');
                      _load();
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (error != null) RmErrorBox(error!),
            if (notice != null)
              RmCard(
                color: const Color(0xFFF3F8EE),
                borderColor: const Color(0xFFCFE3C0),
                child: Text(notice!, style: const TextStyle(fontSize: 13, color: Color(0xFF1F4A0E))),
              ),
            RmSyncBanner(status),
            if (loading && t == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (t != null && !hasData)
              const RmCard(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing has been read from Tally yet. Press refresh. If Tally cannot be reached, check that TallyPrime is open on the server with the gateway switched on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5),
                ),
              )
            else if (t != null) ..._content(t, parties),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> t, List<Map<String, dynamic>> parties) {
    final trucks = (toD(t['trucks'])).round();
    final due = toD(t['due']);
    final partiesDue = (toD(t['parties_due'])).round();
    final advance = toD(t['advance']);
    final deduction = toD(t['deduction']);
    final checks = data['checks'] is Map ? Map<String, dynamic>.from(data['checks'] as Map) : <String, dynamic>{};
    final dups = ((checks['duplicate_receipts'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final missing = ((checks['missing_receipts'] as List?) ?? const []).map((e) => e.toString()).toList();
    final acked = ((checks['acked'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final noVeh = toD(checks['no_vehicle']).round();
    final mism = toD(checks['tally_mismatch']).round();
    final alerts = <Map<String, dynamic>>[
      for (final k in const ['rate_alerts', 'deduction_alerts', 'weight_alerts'])
        ...((checks[k] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
    ]..sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
    final checkCount = dups.length + alerts.length + (missing.isNotEmpty ? 1 : 0) + (noVeh > 0 ? 1 : 0) + (mism > 0 ? 1 : 0);
    final label = rangeLabel(range, dates);
    final older = ((data['parties'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).where((p) => p['active'] == false).toList();
    final payList = ((data['parties'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) => toD(p['overdue']) > 0.004)
        .toList()
      ..sort((a, b) => toD(b['oldest_days']).compareTo(toD(a['oldest_days'])));
    final days = ((data['by_day'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return [
      RmTileGrid(tiles: [
        RmTile(label: 'Received', value: '${mt(t['qty_mt'])} MT', sub: '$trucks truck${trucks == 1 ? '' : 's'} · $label'),
        RmTile(label: 'Purchase value', value: inr(t['net']), sub: deduction > 0 ? 'after ${inr(deduction)} weighbridge etc.' : 'net of deductions'),
        RmTile(label: 'Paid', value: inr(t['paid_period']), sub: label),
        RmTile(
          dark: true,
          label: 'Due to suppliers',
          value: inr(due),
          sub: '$partiesDue supplier${partiesDue == 1 ? '' : 's'}${advance > 0 ? ' · ${inr(advance)} advance' : ''}',
        ),
      ]),
      _stockCard(),
      if (t['avg_rate'] != null)
        RmCard(
          child: Row(children: [
            const Expanded(child: Text('Average rate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Text('${inr(toD(t['avg_rate']).round())} / MT', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ),
      if (due > 0)
        RmCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('How old is the money due', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            Text('Payments are matched to the oldest purchases first.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            RmAgingBar(
              aging: Map<String, dynamic>.from((data['aging'] as Map?) ?? const {}),
              labels: Map<String, dynamic>.from((data['aging_labels'] as Map?) ?? const {}),
              total: due,
            ),
          ]),
        ),
      if (checkCount > 0 || (isAdmin && acked.isNotEmpty))
        RmCard(
          padding: EdgeInsets.zero,
          color: const Color(0xFFFFF7EA),
          borderColor: const Color(0xFFF3D7A6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: () => setState(() => showChecks = !showChecks),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFF7A4D00), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(checkCount == 0 ? 'Nothing new to check' : '$checkCount thing${checkCount == 1 ? '' : 's'} worth a look in the Tally entries',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF6A4300))),
                  ),
                  Icon(showChecks ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF7A4D00)),
                ]),
              ),
            ),
            if (showChecks)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final d in dups)
                    _checkLine('Receipt ${d['receipt']} appears ${d['count']} times (${d['parties']}, ${dm(d['date'])}). Is one of them a typing mistake?',
                        ack: [{'key': 'dup:${d['receipt']}', 'label': 'Receipt ${d['receipt']} appears ${d['count']} times (${d['parties']})'}]),
                  for (final a in alerts.take(12))
                    _checkLine('${isInfoAlert(a) ? 'ℹ' : '⚑'} ${alertText(a)}', ack: [{'key': a['key'].toString(), 'label': alertText(a)}]),
                  if (alerts.length > 12) _checkLine('…and ${alerts.length - 12} more. Mark the ones above as checked to see the rest, or open a supplier.'),
                  if (missing.isNotEmpty)
                    _checkLine('Receipt numbers missing in this period: ${missing.join(', ')}. Not entered yet, or cancelled?',
                        ack: [for (final m in missing) {'key': 'miss:$m', 'label': 'Receipt $m missing'}]),
                  if (noVeh > 0) _checkLine('$noVeh purchase${noVeh == 1 ? ' has' : 's have'} no vehicle number in this period.'),
                  if (mism > 0)
                    _checkLine("$mism supplier balance${mism == 1 ? '' : 's'} differ from Tally's own (marked ⚠ below). A recent edit may not be picked up yet: refresh. If it stays, ask an admin for a Full resync."),
                  _ackedList(acked),
                ]),
              ),
          ]),
        ),
      if (payList.isNotEmpty)
        RmCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pay list', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            Text(
              '${inr(t['overdue'])} owed to ${toD(t['overdue_parties']).round()} supplier${toD(t['overdue_parties']).round() == 1 ? '' : 's'} for more than ${toD(data['pay_days']).round()} days, oldest first.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            for (final p in payList.take(8))
              InkWell(
                onTap: () => _open(p['name'].toString()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    Expanded(child: Text(p['name'].toString(), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1E4012)))),
                    Text('${toD(p['oldest_days']).round()} d', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(width: 10),
                    Text(inr(p['overdue']), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ]),
        ),
      const RmSectionLabel('Suppliers'),
      TextField(
        decoration: InputDecoration(
          hintText: 'Find a supplier',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: rmBorder)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: rmBorder)),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final s in const [('balance', 'Most due'), ('age', 'Oldest due'), ('qty', 'Most received'), ('name', 'A–Z')])
          ChoiceChip(
            label: Text(s.$2),
            selected: sort == s.$1,
            onSelected: (_) => setState(() => sort = s.$1),
          ),
      ]),
      const SizedBox(height: 8),
      if (search.trim().isEmpty && older.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => showOlder = !showOlder),
            child: Text('${showOlder ? 'Hide' : 'Show'} ${older.length} other supplier${older.length == 1 ? '' : 's'} with only older balances (${inr(older.fold<double>(0, (s, p) => s + toD(p['balance'])))})'),
          ),
        ),
      if (parties.isEmpty)
        const RmCard(
          padding: EdgeInsets.all(20),
          child: Text('No supplier matches, or no purchases or dues in this period.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5)),
        ),
      for (final p in parties) _partyCard(p),
      if (parties.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(
            'Total of ${parties.length}: ${mt(parties.fold<double>(0, (s, p) => s + toD(p['qty_mt'])))} MT · amount ${inr(parties.fold<double>(0, (s, p) => s + toD(p['net'])))} · paid ${inr(parties.fold<double>(0, (s, p) => s + toD(p['paid_period'])))} · balance ${inr(parties.fold<double>(0, (s, p) => s + toD(p['balance'])))}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      _rateBoard(),
      if (days.isNotEmpty) ...[
        const RmSectionLabel('Received per day'),
        RmCard(child: _dayBars(days)),
      ],
    ];
  }

  // Estimated stock in the yard: received (Tally) minus factory run hours x tonnes per hour.
  Widget _stockCard() {
    if (stock.isEmpty) return const SizedBox.shrink();
    if (stock['stock_mt'] == null) {
      return const RmCard(child: Text('Factory run hours are not available, so the stock cannot be worked out.', style: TextStyle(fontSize: 13)));
    }
    final daysLeft = stock['days_left'];
    return RmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Stock in the yard (estimate)', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
          if (isAdmin)
            InkWell(
              onTap: _editStock,
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_outlined, size: 18)),
            ),
        ]),
        Text('${mt(stock['stock_mt'])} MT', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        if (daysLeft != null)
          Text('about $daysLeft days at the last 7 days\' pace (${mt(stock['use_per_day_mt'])} MT/day)', style: const TextStyle(fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(
          '${toD(stock['opening_mt']) != 0 ? '${mt(stock['opening_mt'])} opening + ' : ''}${mt(stock['received_mt'])} received − ${mt(stock['used_mt'])} used (${mt(stock['run_hours'])} run hours × ${stock['per_hour']} MT/hour) since ${dmy(stock['since'])}.'
          '${stock['last_run_date'] != null ? ' Run hours entered up to ${dmy(stock['last_run_date'])}.' : ' No run hours entered yet.'} Days without a run entry count as no use.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ]),
    );
  }

  Future<void> _editStock() async {
    final opening = TextEditingController(text: toD(stock['opening_mt']) == 0 ? '' : stock['opening_mt'].toString());
    final perHour = TextEditingController(text: stock['per_hour'].toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stock settings'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: 'Opening stock on ${dmy(stock['since'])} (MT)'),
          ),
          TextField(
            controller: perHour,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Used per run hour (MT)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await RmApi.put('/raw-material/stock', {
        'opening_mt': opening.text.trim().isEmpty ? null : double.tryParse(opening.text.trim()),
        'per_hour': perHour.text.trim().isEmpty ? null : double.tryParse(perHour.text.trim()),
      });
      if (mounted) setState(() => stock = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  // Each supplier's current rate, since when, and market moves. Nothing to enter.
  Widget _rateBoard() {
    final board = ((rates['board'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (board.isEmpty) return const SizedBox.shrink();
    final moves = ((rates['moves'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return RmCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => showRates = !showRates),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Expanded(child: Text('Rate board', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
              Text('${board.length} rates', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Icon(showRates ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
        ),
        if (showRates)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final m in moves.take(3))
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF3F8EE), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCFE3C0))),
                  child: Text(
                    'ℹ ${(m['parties'] as List).length} suppliers moved from ${inr(m['from'])} to ${inr(m['to'])} per MT between ${dm(m['first'])} and ${dm(m['last'])}.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              for (final b in board)
                InkWell(
                  onTap: () => _open(b['party'].toString()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${b['party']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1E4012)))),
                        Text('${inr(b['rate'])}${b['latest_differs'] != null ? ' ⚑' : ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                      ]),
                      Text(
                        '${b['item']} · since ${dm(b['since'])} (${toD(b['trucks_at_rate']).round()} loads)${b['last_change'] != null ? ' · was ${inr((b['last_change'] as Map)['from'])} until ${dm((b['last_change'] as Map)['date'])}' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  // One line of the "things worth a look" card; an admin also gets a tick that
  // marks it as checked (it then stops showing).
  Widget _checkLine(String text, {List<Map<String, String>>? ack}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('•  $text', style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A3A14)))),
          if (isAdmin && ack != null)
            InkWell(
              onTap: () => _markChecked(ack),
              child: const Padding(padding: EdgeInsets.fromLTRB(10, 0, 2, 0), child: Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF2C5E17))),
            ),
        ]),
      );

  Future<void> _markChecked(List<Map<String, String>> items) async {
    try {
      await RmApi.post('/raw-material/ack', {'items': items});
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _undoChecked(String key) async {
    try {
      await RmApi.post('/raw-material/unack', {'key': key});
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget _ackedList(List<Map<String, dynamic>> acked) {
    if (!isAdmin || acked.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => showAcked = !showAcked),
          child: Text('${showAcked ? 'Hide' : 'Show'} ${acked.length} marked as checked',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF6A4300))),
        ),
        if (showAcked)
          for (final k in acked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(child: Text('✓ ${k['label'] ?? k['key']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                InkWell(
                  onTap: () => _undoChecked(k['key'].toString()),
                  child: const Padding(padding: EdgeInsets.only(left: 8), child: Text('Undo', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline))),
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _partyCard(Map<String, dynamic> p) {
    final balance = toD(p['balance']);
    final trucks = toD(p['trucks']).round();
    final diff = p['tally_diff'];
    final flagged = diff != null && toD(diff).abs() >= 1;
    final age = toD(p['oldest_days']).round();
    final paid = toD(p['paid_period']);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(p['name'].toString()),
      child: RmCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${p['name']}${flagged ? ' ⚠' : ''}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E4012))),
            ),
            Text(
              balance < -0.004 ? '${inr(-balance)} adv.' : inr(balance),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: balance < -0.004 ? const Color(0xFF2C5E17) : const Color(0xFF1E3313)),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
          const SizedBox(height: 3),
          Text(
            trucks > 0
                ? '$trucks truck${trucks == 1 ? '' : 's'} · ${mt(p['qty_mt'])} MT · ${_rate(p)}/MT · ${inr(p['net'])}${paid > 0 ? ' · paid ${inr(paid)}' : ''}'
                : 'No purchase in this period${paid > 0 ? ' · paid ${inr(paid)}' : ''}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (balance > 0.004)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(age == 0 ? 'Due since today' : 'Oldest due $age day${age == 1 ? '' : 's'} ago',
                  style: TextStyle(fontSize: 12, color: age > 60 ? const Color(0xFF9E2419) : age > 30 ? const Color(0xFF7A4D00) : Colors.grey.shade600)),
            ),
        ]),
      ),
    );
  }

  Widget _dayBars(List<Map<String, dynamic>> days) {
    var max = 0.001;
    for (final d in days) {
      if (toD(d['qty_mt']) > max) max = toD(d['qty_mt']);
    }
    return SizedBox(
      height: 150,
      // reverse: the newest day sits at the right edge, older days are a swipe away.
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        children: [
          for (final d in days.reversed)
            SizedBox(
              width: 44,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(mt(d['qty_mt']).replaceAll(RegExp(r'\.00$'), ''), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                const SizedBox(height: 2),
                Container(
                  width: 26,
                  height: (toD(d['qty_mt']) / max * 90).clamp(3.0, 90.0).toDouble(),
                  decoration: const BoxDecoration(color: Color(0xFF659442), borderRadius: BorderRadius.vertical(top: Radius.circular(5))),
                ),
                const SizedBox(height: 4),
                Text(dm(d['date']), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
              ]),
            ),
        ],
      ),
    );
  }
}
