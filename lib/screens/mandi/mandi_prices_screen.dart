// lib/screens/mandi/mandi_prices_screen.dart
//
// Mandi prices — overview (Sep 2026 redesign, group D), same as the
// website's Mandi prices page:
//  - What your harvest is worth today: harvest of crops still running or
//    finished in the last 6 months × the best market's price (sales
//    aren't recorded yet, so sold produce still counts).
//  - Where to sell today: per crop the best market and price, the
//    average, day change, MSP in force and "above / below", last 30 days;
//    "Markets" opens every market's price (older than 7 days = grey).
//  - My price alerts. MSPs filled in by the app wait for a Confirm
//    (banner for people who manage mandi prices).
// API: GET /mandi/overview, /mandi/alerts.
// Web counterpart: src/pages/MandiPrices.jsx.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'mandi_alerts.dart';
import 'mandi_common.dart';
import 'mandi_commodity_screen.dart';
import 'mandi_settings_screen.dart';

class MandiPricesScreen extends StatefulWidget {
  const MandiPricesScreen({super.key});
  @override
  State<MandiPricesScreen> createState() => _MandiPricesScreenState();
}

class _MandiPricesScreenState extends State<MandiPricesScreen> {
  bool loading = true;
  String? error;
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> commodities = [];
  List<Map<String, dynamic>> alerts = [];
  bool canManage = false;
  final Set<int> open = {};

  @override
  void initState() {
    super.initState();
    _loadPerms();
    _load();
  }

  Future<void> _loadPerms() async {
    final admin = await ApiService.isAdmin();
    final add = await ApiService.canAdd('mandi_prices');
    final upd = await ApiService.canUpdate('mandi_prices');
    if (mounted) setState(() => canManage = admin || add || upd);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await MandiApi.get('/mandi/overview');
      setState(() {
        data = Map<String, dynamic>.from(d ?? {});
        commodities = List<Map<String, dynamic>>.from(d['commodities'] ?? []);
      });
      _loadAlerts();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final a = await MandiApi.get('/mandi/alerts');
      if (mounted) setState(() => alerts = List<Map<String, dynamic>>.from(a));
    } catch (_) {
      // The overview still works without the alerts card.
    }
  }

  Future<void> _openCommodity(int id, String title) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MandiCommodityScreen(commodityId: id, title: title)));
    _load();
  }

  Future<void> _openSetup([int tab = 0]) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MandiSettingsScreen(initialTab: tab)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final latest = commodities
        .map((c) => (c['where'] is Map ? c['where']['latest_date'] : null)?.toString() ?? '')
        .fold<String>('', (m, d) => d.compareTo(m) > 0 ? d : m);
    final held = commodities.where((c) => c['harvest'] is Map).toList();
    final total = data['harvest_total'] is Map ? Map<String, dynamic>.from(data['harvest_total']) : null;
    final toCheck = toD(data['msp_to_check'])?.round() ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F1),
      appBar: AppBar(
        title: const Text('Mandi prices'),
        backgroundColor: mandiDark,
        foregroundColor: Colors.white,
        actions: [
          if (canManage) IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Setup', onPressed: () => _openSetup()),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Text('₹ per quintal at the markets you follow${latest.isNotEmpty ? ' · latest prices ${dayMonth(latest)}' : ''}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            const SizedBox(height: 10),
            if (error != null) ErrorBox(error!),
            if (canManage && toCheck > 0)
              InkWell(
                onTap: () => _openSetup(2),
                child: MandiCard(
                  color: const Color(0xFFFFF7EA),
                  borderColor: const Color(0xFFF3D7A6),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFF7A4D00)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('$toCheck MSPs were filled in from the government announcement. Tap to check and confirm them.',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF6A4300))),
                    ),
                    const Icon(Icons.chevron_right, color: Color(0xFF7A4D00)),
                  ]),
                ),
              ),
            if (held.isNotEmpty && total != null) _worth(held, total),
            MyAlertsCard(
              alerts: alerts,
              onTap: (a) => _openCommodity(int.tryParse(a['commodity_id'].toString()) ?? 0, (a['commodity_name'] ?? '').toString()),
            ),
            if (loading && commodities.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (commodities.isEmpty && error == null)
              _empty()
            else ...[
              const SectionLabel('Where to sell today'),
              ...commodities.map(_card),
              Text('Grey = no price in the last ${data['fresh_days'] ?? 7} days; not counted for best today.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _worth(List<Map<String, dynamic>> held, Map<String, dynamic> total) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF1E3313), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Your harvest is worth today', style: TextStyle(fontSize: 13, color: Color(0xFFC9D7BD), fontWeight: FontWeight.w600)),
        Text(rupees(total['value_best']), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
        Text('${qtlText(total['qtl'])} at the best market for each crop', style: const TextStyle(fontSize: 12.5, color: Color(0xFFC9D7BD))),
        const SizedBox(height: 8),
        for (final c in held)
          Builder(builder: (_) {
            final h = Map<String, dynamic>.from(c['harvest']);
            final kg = toD(h['kg']) ?? 0;
            final best = c['where'] is Map ? c['where']['best'] : null;
            return InkWell(
              onTap: () => _openCommodity(c['id'] as int, '${c['display_name']}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      kg > 0
                          ? '${c['display_name']} ${qtlText(h['qtl'])}${best is Map ? ' · ${marketName(best)}' : ''}'
                          : '${c['display_name']}: no harvest yet',
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (kg > 0) Text(rupees(h['value_best']), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
              ),
            );
          }),
        const SizedBox(height: 6),
        Text('Crops still running or finished in the last ${total['hold_months'] ?? 6} months. Sales aren\'t recorded yet, so sold produce still counts.',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF9FB393))),
      ]),
    );
  }

  Widget _empty() => MandiCard(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          const Icon(Icons.show_chart, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('No crops are followed yet', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            canManage ? 'Open Setup (top right) to add your crops.' : 'Ask an admin to set up mandi prices.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ]),
      );

  Widget _card(Map<String, dynamic> c) {
    final id = c['id'] as int;
    final where = c['where'] is Map ? Map<String, dynamic>.from(c['where']) : <String, dynamic>{};
    final markets = List<Map<String, dynamic>>.from(where['markets'] ?? []);
    final best = where['best'] is Map ? Map<String, dynamic>.from(where['best']) : null;
    final latest = c['latest'] as Map<String, dynamic>?;
    final spark = List<Map<String, dynamic>>.from(c['spark'] ?? []);
    final msp = c['msp_now'] is Map ? c['msp_now'] as Map : null;
    final gap = mspGap(where['average'], msp);
    final fresh = markets.where((m) => m['fresh'] == true).length;
    final display = (c['display_name'] ?? '').toString();
    final isOpen = open.contains(id);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openCommodity(id, display),
      child: MandiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(display, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: mandiDark))),
            if (latest != null) ChangeChip(value: latest['change_1d_pct'], label: ' day'),
          ]),
          const SizedBox(height: 4),
          if (best == null)
            Text(latest == null ? 'No prices in the last 60 days — off-season, or history not loaded yet.' : 'No market reported in the last week.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600))
          else
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(rupees(best['modal']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: mandiDark)),
              const SizedBox(width: 8),
              Flexible(
                child: Text('best · ${marketName(best)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mandiGreen), overflow: TextOverflow.ellipsis),
              ),
            ]),
          Row(children: [
            Expanded(
              child: Text('Average ${rupees(where['average'])} · $fresh market${fresh == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            ),
            if (spark.length > 1) SizedBox(width: 90, height: 28, child: _sparkline(spark)),
          ]),
          if (msp != null)
            Text('MSP ${rupees(msp['msp_price'])}${gap != null ? ' · ${gap.text}' : ''}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: gap != null && gap.below ? const Color(0xFF9E2419) : mandiGreen))
          else if ((toD(c['msp_to_check']) ?? 0) > 0)
            Text('MSP filled in — to check', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (c['usual_peak'] is Map)
            Text('Usually highest ${c['usual_peak']['label']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (markets.isNotEmpty) ...[
            const SizedBox(height: 2),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 34), foregroundColor: mandiGreen),
              onPressed: () => setState(() => isOpen ? open.remove(id) : open.add(id)),
              icon: Icon(isOpen ? Icons.expand_less : Icons.expand_more, size: 18),
              label: Text(isOpen ? 'Hide markets' : 'All ${markets.length} markets'),
            ),
          ],
          if (isOpen)
            for (final m in markets)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: m['best'] == true ? const Color(0xFFEEF5E8) : null,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text('${marketName(m)}${m['best'] == true ? '  · best' : ''}',
                        style: TextStyle(fontSize: 13.5, fontWeight: m['best'] == true ? FontWeight.w700 : FontWeight.w500, color: m['fresh'] == true ? mandiDark : Colors.grey.shade500)),
                  ),
                  if (m['on_latest'] != true)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(dayMonth(m['date']), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                    ),
                  Text(rupees(m['modal']),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: m['fresh'] == true ? mandiDark : Colors.grey.shade500)),
                ]),
              ),
        ]),
      ),
    );
  }

  Widget _sparkline(List<Map<String, dynamic>> spark) {
    final vals = spark.map((p) => toD(p['modal']) ?? 0).toList();
    final minV = vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.reduce((a, b) => a > b ? a : b);
    final pad = (maxV - minV) == 0 ? 1.0 : (maxV - minV) * 0.1;
    return LineChart(LineChartData(
      minY: minV - pad,
      maxY: maxV + pad,
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i])],
          isCurved: true,
          color: const Color(0xFF4A7A2B),
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}
