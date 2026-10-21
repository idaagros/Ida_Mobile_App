// lib/screens/raw_material/rm_party_screen.dart
//
// One supplier's ledger, from TallyPrime (same as the website's supplier
// page): every receipt (truck, weight, rate, the Rs 50 weighbridge
// deduction) as an amount to pay, every payment made, and the running
// balance. "Share" sends a plain-text statement (WhatsApp etc.).
//  - Tiles: amount to pay (or paid in advance), opening, purchases, paid, closing
//  - Still unpaid: receipts not yet covered by payments, oldest first
//  - Ledger with running balance
// API: GET /raw-material/party?name=…&from=…&to=…
// Web counterpart: src/pages/RawMaterialParty.jsx.

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'rm_common.dart';
import 'rm_statement_pdf.dart';

class RmPartyScreen extends StatefulWidget {
  final String name;
  const RmPartyScreen({super.key, required this.name});
  @override
  State<RmPartyScreen> createState() => _RmPartyScreenState();
}

class _RmPartyScreenState extends State<RmPartyScreen> {
  bool loading = true;
  bool showPending = true;
  String? error;
  Map<String, dynamic> data = {};
  String range = 'season';
  RmDates dates = rangeDates('season');
  String? fyFrom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // 'This season' sends no dates: the server knows when the season starts.
      final d = await RmApi.get('/raw-material/party',
          query: range == 'season' ? {'name': widget.name} : {'name': widget.name, 'from': dates.from, 'to': dates.to});
      if (!mounted) return;
      final m = Map<String, dynamic>.from(d as Map);
      setState(() {
        data = m;
        if (m['fy'] is Map) fyFrom = (m['fy'] as Map)['from']?.toString();
        final p = m['period'];
        if (range == 'season' && p is Map) dates = RmDates(p['from'].toString(), p['to'].toString());
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> _lines() =>
      ((data['lines'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  double _closing(List<Map<String, dynamic>> lines) => lines.isEmpty ? toD(data['opening_at_from']) : toD(lines.last['balance']);

  // A plain-text statement for WhatsApp / SMS.
  String _statement() {
    final lines = _lines();
    final b = StringBuffer();
    b.writeln('IDA AgriCo: statement for ${data['party']}');
    final period = data['period'] is Map ? data['period'] as Map : const {};
    b.writeln('${dmy(period['from'])} to ${dmy(period['to'])}');
    b.writeln('');
    b.writeln('Opening balance: ${inr(data['opening_at_from'])}');
    final recent = lines.length > 25 ? lines.sublist(lines.length - 25) : lines;
    if (lines.length > recent.length) b.writeln('(last ${recent.length} of ${lines.length} entries)');
    for (final l in recent) {
      final r = l['receipt'];
      if (r is Map) {
        final rate = r['rate_per_mt'] == null ? '' : ' x ${inr(r['rate_per_mt'])}';
        final ded = toD(r['deduction']);
        b.writeln('${dm(l['date'])}  ${r['label'] ?? 'Purchase'}${r['vehicle'] != null ? ' ${r['vehicle']}' : ''}  ${mt(r['qty_mt'])} MT${toD(r['cut_mt']) > 0 ? ' (${mt(r['gross_mt'])} − ${mt(r['cut_mt'])} cut)' : ''}$rate = ${inr(l['credit'])}${ded > 0 ? ' (after ${inr(ded)} deduction)' : ''}');
      } else if (toD(l['debit']) > 0) {
        b.writeln('${dm(l['date'])}  Paid ${inr(l['debit'])}');
      } else {
        b.writeln('${dm(l['date'])}  ${l['voucher_type'] ?? 'Entry'} ${inr(l['credit'])}');
      }
    }
    b.writeln('');
    final bal = toD(data['balance']);
    b.writeln(bal < -0.004 ? 'Paid in advance: ${inr(-bal)}' : 'Amount to pay today: ${inr(bal)}');
    return b.toString();
  }

  Future<void> _sharePdf() async {
    try {
      final f = await buildStatementPdf(data);
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/pdf')], subject: 'Statement: ${widget.name}');
    } catch (e) {
      if (mounted) setState(() => error = 'Could not make the PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] is Map ? Map<String, dynamic>.from(data['status'] as Map) : <String, dynamic>{};
    final lines = _lines();
    final loaded = data.isNotEmpty;
    return Scaffold(
      backgroundColor: rmBg,
      appBar: AppBar(
        title: Text(widget.name, overflow: TextOverflow.ellipsis),
        backgroundColor: rmAppBar,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Statement as PDF',
            onPressed: loaded ? _sharePdf : null,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share statement',
            onPressed: loaded ? () => Share.share(_statement(), subject: 'Statement: ${widget.name}') : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            if (loaded)
              Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(
                  status['last_ok_at'] != null ? 'From Tally · updated ${whenText(status['last_ok_at'])}' : 'Waiting for the first read from Tally',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                RmTallyChip(diff: data['tally_diff'], tally: data['tally_closing']),
              ]),
            const SizedBox(height: 10),
            RmRangePicker(
              range: range,
              dates: dates,
              onChanged: (r, d) {
                setState(() {
                  range = r;
                  dates = r == 'fy' ? rangeDates('fy', fyFrom: fyFrom) : d;
                });
                _load();
              },
            ),
            const SizedBox(height: 10),
            if (error != null) RmErrorBox(error!),
            if (loaded) RmSyncBanner(status),
            if (loading && !loaded)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (loaded) ..._content(lines),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(List<Map<String, dynamic>> lines) {
    final balance = toD(data['balance']);
    final due = balance > 0.004;
    final oldest = toD(data['oldest_days']).round();
    final period = data['period'] is Map ? data['period'] as Map : const {};
    final label = rangeLabel(range, dates);
    final closing = _closing(lines);
    final pending = ((data['pending'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return [
      RmTileGrid(tiles: [
        RmTile(
          dark: true,
          label: balance < -0.004 ? 'Paid in advance' : 'Amount to pay',
          value: inr(balance.abs()),
          sub: due
              ? (oldest > 0 ? 'oldest due $oldest day${oldest == 1 ? '' : 's'} ago' : 'all received today')
              : balance < -0.004
                  ? 'adjusts against next purchases'
                  : 'nothing due',
        ),
        RmTile(label: 'Opening', value: inr(data['opening_at_from']), sub: 'on ${dmy(period['from'])}'),
        RmTile(label: 'Purchases', value: inr(data['period_purchases']), sub: '${mt(data['period_qty_mt'])} MT · $label'),
        RmTile(label: 'Paid', value: inr(data['period_paid']), sub: label),
      ]),
      RmCard(
        child: Row(children: [
          Expanded(child: Text('Closing on ${dmy(period['to'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Text(inr(closing), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      ),
      if (due)
        RmCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Still unpaid', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
              InkWell(
                onTap: () => setState(() => showPending = !showPending),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(showPending ? 'Hide' : 'Show ${pending.length}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C5E17))),
                ),
              ),
            ]),
            Text('Payments are matched to the oldest receipts first.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            RmAgingBar(
              aging: Map<String, dynamic>.from((data['aging'] as Map?) ?? const {}),
              labels: Map<String, dynamic>.from((data['aging_labels'] as Map?) ?? const {}),
              total: balance,
            ),
            if (showPending)
              for (final b in pending)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(
                      child: Text('${b['label']}  ·  ${dm(b['date'])}  ·  ${toD(b['days']).round() == 0 ? 'today' : '${toD(b['days']).round()} d'}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text(inr(b['left']), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
          ]),
        ),
      RmSectionLabel('Ledger · ${lines.length} entr${lines.length == 1 ? 'y' : 'ies'}'),
      RmCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          _row(
            title: 'Opening balance',
            subtitle: dmy(period['from']),
            amount: '',
            balance: inr(data['opening_at_from']),
            tint: const Color(0xFFF6F9F2),
          ),
          for (final l in lines) _lineRow(l),
          if (lines.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('No entries in this period.', style: TextStyle(fontSize: 13.5))),
        ]),
      ),
    ];
  }

  Widget _lineRow(Map<String, dynamic> l) {
    final r = l['receipt'];
    final debit = toD(l['debit']);
    final credit = toD(l['credit']);
    String title;
    String subtitle;
    if (r is Map) {
      title = (r['label'] ?? 'Voucher ${l['voucher_no']}').toString();
      final ded = toD(r['deduction']);
      final parts = <String>[
        dm(l['date']),
        if (r['vehicle'] != null) r['vehicle'].toString(),
        if (r['item'] != null) r['item'].toString(),
        '${mt(r['qty_mt'])} MT${toD(r['cut_mt']) > 0 ? ' (${mt(r['gross_mt'])} − ${mt(r['cut_mt'])} cut)' : ''} × ${inr(r['rate_per_mt'])}',
        if (ded != 0) '${ded > 0 ? '−' : '+'}${inr(ded.abs())}',
        if (r['receipt_date'] != null && r['receipt_date'].toString() != l['date'].toString()) 'received ${dm(r['receipt_date'])}',
        for (final a in (r['alerts'] as List? ?? const [])) '${(a as Map)['acked'] == true ? '✓' : isInfoAlert(a) ? 'ℹ' : '⚑'} ${alertShort(a)}',
      ];
      subtitle = parts.join(' · ');
    } else {
      title = l['kind'] == 'payment' ? 'Payment' : (l['voucher_type'] ?? 'Entry').toString();
      final n = (l['narration'] ?? '').toString();
      subtitle = '${dm(l['date'])}${l['voucher_no'] != null ? ' · #${l['voucher_no']}' : ''}${n.isNotEmpty ? ' · $n' : ''}';
    }
    return _row(
      title: title,
      subtitle: subtitle,
      amount: debit > 0 ? '− ${inr(debit)}' : '+ ${inr(credit)}',
      amountColor: debit > 0 ? const Color(0xFF2C5E17) : null,
      balance: inr(l['balance']),
    );
  }

  Widget _row({
    required String title,
    required String subtitle,
    required String amount,
    required String balance,
    Color? amountColor,
    Color? tint,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tint,
        border: const Border(top: BorderSide(color: rmBorder)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          if (amount.isNotEmpty) Text(amount, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: amountColor)),
        ]),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          Text('balance $balance', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}
