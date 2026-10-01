// lib/screens/reports/reports_hub_screen.dart
//
// Reports (Sep 2026, group E): every report the person may see, grouped
// Factory / Farms. Tap one to open it (ReportBuilderScreen). The Daily
// reading report and the Electricity bill projection keep their own
// screens. Web counterpart: src/pages/ReportsHub.jsx.
// API: GET /report-hub.

import 'package:flutter/material.dart';
import '../daily_reports_screen.dart';
import '../electricity_bill_projection_screen.dart';
import 'report_builder_screen.dart';
import 'reports_common.dart';

class ReportsHubScreen extends StatefulWidget {
  const ReportsHubScreen({super.key});
  @override
  State<ReportsHubScreen> createState() => _ReportsHubScreenState();
}

class _ReportsHubScreenState extends State<ReportsHubScreen> {
  List<Map<String, dynamic>> reports = [];
  bool loading = true;
  String? error;

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
      final d = await ReportApi.get('/report-hub');
      setState(() => reports = List<Map<String, dynamic>>.from(d['reports'] ?? []));
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _open(Map<String, dynamic> r) {
    final key = r['key'];
    Widget screen;
    if (key == 'daily_readings') {
      screen = const DailyReportsScreen();
    } else if (key == 'bill') {
      screen = const ElectricityBillProjectionScreen();
    } else {
      screen = ReportBuilderScreen(report: r);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in reports) {
      (groups[r['group']?.toString() ?? 'Other'] ??= []).add(r);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F1),
      appBar: AppBar(title: const Text('Reports'), backgroundColor: rDark, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            const Text('Pick a report. Each one can be grouped, filtered and downloaded as Excel or PDF.',
                style: TextStyle(fontSize: 13, color: rMuted)),
            const SizedBox(height: 8),
            if (error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFBE2DF), borderRadius: BorderRadius.circular(10)),
                child: Text(error!, style: const TextStyle(color: Color(0xFF9E2419))),
              ),
            if (loading && reports.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (!loading && reports.isEmpty && error == null)
              const Padding(padding: EdgeInsets.all(30), child: Text('You don’t have access to any report yet.', textAlign: TextAlign.center)),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Text(g.key.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: rMuted)),
              ),
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: rBorder)),
                child: Column(children: [
                  for (var i = 0; i < g.value.length; i++)
                    InkWell(
                      onTap: () => _open(g.value[i]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: Color(0xFFEEF1EA)))),
                        child: Row(children: [
                          Icon(reportIcon(g.value[i]['icon']?.toString()), color: rGreen, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${g.value[i]['title']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              Text('${g.value[i]['description'] ?? ''}', style: const TextStyle(fontSize: 12, color: rMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, color: rMuted),
                        ]),
                      ),
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
