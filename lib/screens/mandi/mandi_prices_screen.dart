// lib/screens/mandi/mandi_prices_screen.dart
//
// Mandi Price Tracker — overview. One card per tracked commodity: latest
// average modal price across the active Amravati-district markets,
// day/week change, best market that day and a 30-day sparkline. Tap a
// card for markets / trend / best time to sell.
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
  List<Map<String, dynamic>> commodities = [];
  List<Map<String, dynamic>> alerts = [];
  bool canManage = false;

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
      final data = await MandiApi.get('/mandi/overview');
      setState(() => commodities = List<Map<String, dynamic>>.from(data['commodities'] ?? []));
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
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => MandiCommodityScreen(commodityId: id, title: title)));
    _loadAlerts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      appBar: AppBar(
        title: const Text('Mandi Prices'),
        backgroundColor: mandiDark,
        foregroundColor: Colors.white,
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const MandiSettingsScreen()));
                _load();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              'Agmarknet modal prices (₹/quintal), averaged across the active markets in Amravati district.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            MyAlertsCard(
              alerts: alerts,
              onTap: (a) => _openCommodity(
                  int.tryParse(a['commodity_id'].toString()) ?? 0, (a['commodity_name'] ?? '').toString()),
            ),
            if (error != null) ErrorBox(error!),
            if (loading && commodities.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (commodities.isEmpty && error == null)
              _empty()
            else
              ...commodities.map(_card),
          ],
        ),
      ),
    );
  }

  Widget _empty() => MandiCard(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          const Icon(Icons.show_chart, size: 36, color: Colors.grey),
          const SizedBox(height: 8),
          const Text('No commodities are being tracked yet', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            canManage ? 'Open Settings (top right) to add your crops.' : 'Ask an admin to set up the mandi price tracker.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ]),
      );

  Widget _card(Map<String, dynamic> c) {
    final latest = c['latest'] as Map<String, dynamic>?;
    final spark = List<Map<String, dynamic>>.from(c['spark'] ?? []);
    final best = c['best_market'] as Map<String, dynamic>?;
    final stale = toD(c['stale_days']);
    final display = (c['display_name'] ?? '').toString();
    final agName = (c['agmarknet_name'] ?? '').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openCommodity(c['id'] as int, display),
      child: MandiCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(display, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: mandiDark)),
                if (display != agName)
                  Text(agName, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ),
            if (latest != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(rupees(latest['modal']),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: mandiDark)),
                Text('per quintal', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
          ]),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No prices in the last 60 days — may be off-season, or history not loaded yet.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )
          else ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ChangeChip(value: latest['change_1d_pct'], label: ' day'),
              ChangeChip(value: latest['change_7d_pct'], label: ' week'),
              Text('${shortDate(latest['date'])} · ${latest['markets']} markets',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
            if (spark.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(height: 44, child: _sparkline(spark)),
            ],
            const SizedBox(height: 6),
            Row(children: [
              if (best != null)
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Best: ', style: TextStyle(color: Colors.grey.shade600)),
                      TextSpan(text: marketName(best), style: const TextStyle(fontWeight: FontWeight.w600, color: mandiDark)),
                      TextSpan(text: '  ${rupees(best['modal'])}', style: TextStyle(color: Colors.grey.shade600)),
                    ]),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                const Spacer(),
              if (stale != null && stale > 3)
                Text('No new price for ${stale.round()} days',
                    style: const TextStyle(fontSize: 11, color: mandiOrange, fontWeight: FontWeight.w600)),
            ]),
          ],
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
          color: const Color(0xFF659442),
          barWidth: 2,
          dotData: const FlDotData(show: false),
        ),
      ],
    ));
  }
}
