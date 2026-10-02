// lib/screens/farm_tractor_diesel_screen.dart
//
// Diesel fill-up records per tractor, plus a computed liters-per-hour
// average. See migrations/farm/schema.md for exactly how "average" is
// being interpreted — this is a real assumption, not a spec'd
// formula, so the number shown here should be checked against what
// you actually expect before relying on it.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

import '../services/api_client.dart';
class FarmTractorDieselScreen extends StatefulWidget {
  const FarmTractorDieselScreen({super.key});
  @override
  State<FarmTractorDieselScreen> createState() =>
      _FarmTractorDieselScreenState();
}

class _FarmTractorDieselScreenState extends State<FarmTractorDieselScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  List tractors = [];
  int? selectedTractorId;
  List logs = [];
  Map? average;
  Map? summary; // estimated tank level, learnt figure, checks (Sep 2026)
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadTractors();
  }

  Future<void> _loadTractors() async {
    setState(() => loading = true);
    try {
      final res = await Api.get('/farm-tractor/tractors');
      if (res.statusCode == 200) {
        tractors = jsonDecode(res.body);
        if (tractors.isNotEmpty) {
          selectedTractorId = tractors.first['id'];
          await _loadLogsAndAverage();
        }
      }
    } catch (e) {
      debugPrint('Load tractors error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadLogsAndAverage() async {
    if (selectedTractorId == null) return;
    setState(() => loading = true);
    try {
      final results = await Future.wait([
        Api.get('/farm-tractor/diesel-logs?tractor_id=$selectedTractorId'),
        Api.get('/farm-tractor/diesel-logs/$selectedTractorId/average'),
        Api.get('/farm-tractor/diesel/summary?tractor_id=$selectedTractorId'),
      ]);
      if (results[0].statusCode == 200) logs = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) average = jsonDecode(results[1].body);
      summary = null;
      if (results[2].statusCode == 200) {
        final list = (jsonDecode(results[2].body)['tractors'] as List?) ?? [];
        if (list.isNotEmpty) summary = list.first as Map;
      }
    } catch (e) {
      debugPrint('Load logs error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showAddLogDialog() {
    final loc = AppLocalizations.of(context)!;
    final litersCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final hourMeterCtrl = TextEditingController();
    DateTime logDate = DateTime.now();
    bool isFull = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.ftAddFillup,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: ctx,
                      initialDate: logDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (picked != null) setDialogState(() => logDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: loc.ftDateLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(logDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: litersCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.ftLitersLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: loc.ftCostLabel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: isFull,
                onChanged: (v) => setDialogState(() => isFull = v ?? false),
                title: const Text('Filled to full',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Tick when the tank was filled right up. This is how the app learns this tractor\'s real diesel use.',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hourMeterCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: loc.ftHourMeterReadingLabel,
                  helperText: loc.ftHourMeterHelper,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: () async {
                if (litersCtrl.text.trim().isEmpty) return;
                final res = await Api.post(
                  '/farm-tractor/diesel-logs',
                  body: jsonEncode({
                    'tractor_id': selectedTractorId,
                    'log_date': DateFormat('yyyy-MM-dd').format(logDate),
                    'liters_filled': double.tryParse(litersCtrl.text.trim()),
                    'cost': double.tryParse(costCtrl.text.trim()),
                    'hour_meter_reading':
                        double.tryParse(hourMeterCtrl.text.trim()),
                    'is_full': isFull,
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (res.statusCode == 201) {
                  _loadLogsAndAverage();
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(loc.ftFailedComplete),
                      backgroundColor: Colors.red));
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Estimated diesel left, what was learnt from full fill-ups, checks.
  Widget _tankCard(Map sum) {
    final tank = (sum['tank'] as Map?) ?? {};
    final cal = (sum['calibration'] as Map?) ?? {};
    final cap = tank['capacity'];
    final bal = tank['balance'];
    final pct = (tank['pct'] as num?)?.toDouble() ?? 0;
    final low = tank['low'] == true;
    final negative = tank['negative'] == true;
    final checks = (tank['checks'] as List?) ?? [];
    final intervals = ((cal['intervals'] as List?) ?? []);
    final factor = cal['factor'];
    Widget note(String t, {bool warn = false}) => Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: warn ? const Color(0xFFFFF7EA) : const Color(0xFFF3F8EE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: warn ? const Color(0xFFF3D7A6) : const Color(0xFFCFE3C0))),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12.5,
                  color: warn ? const Color(0xFF7A4D00) : const Color(0xFF2C5E17))),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('DIESEL IN THE TANK (EST.)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.6)),
          const Spacer(),
          Text(bal == null ? '—' : '$bal L',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: idaDark)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 10,
              backgroundColor: const Color(0xFFEEF1EA),
              color: low || negative ? const Color(0xFFF4A340) : idaGreen),
        ),
        const SizedBox(height: 6),
        Text(
            cap == null
                ? (tank['note'] ?? 'Set the tank size in Setup to work out diesel left.')
                : '$cap L tank${tank['anchor_date'] != null ? ' · counted from ${tank['assumed_empty'] == true ? 'the fill-up' : 'the full tank'} of ${tank['anchor_date']}' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        if (negative)
          note('Below zero — a fill-up is probably not entered, or the estimate is too high for this tractor.', warn: true)
        else if (low)
          note('Running low.', warn: true),
        if (factor != null)
          note('Learnt from full fill-ups: this tractor uses about ${((factor as num) * 100).round()}% of the standard figure. Its estimates use that now.'),
        for (final i in intervals.where((x) => x['usable'] != true && ((x['estimated_l'] ?? 0) as num) >= 10).take(1))
          note('Check: ${i['from']} to ${i['to']} took ${i['actual_l']} L, while the jobs add up to about ${i['estimated_l']} L. ${((i['actual_l'] as num) < (i['estimated_l'] as num)) ? 'A fill-up may not be entered.' : 'A job may not be entered, or diesel was used elsewhere.'}', warn: true),
        for (final c in checks.take(1))
          note('Full fill-up of ${c['date']} took ${c['filled_l']} L; about ${c['expected_l']} L was expected.', warn: true),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.ftDieselTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: selectedTractorId == null ? null : _showAddLogDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: tractors.isEmpty && !loading
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(loc.ftNoTractorsSetupFirst,
                      textAlign: TextAlign.center)))
          : Column(children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<int>(
                  value: selectedTractorId,
                  decoration: InputDecoration(
                      labelText: loc.ftTractorLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: tractors
                      .map<DropdownMenuItem<int>>((t) => DropdownMenuItem(
                          value: t['id'], child: Text(tl(context, t['name']))))
                      .toList(),
                  onChanged: (v) {
                    setState(() => selectedTractorId = v);
                    _loadLogsAndAverage();
                  },
                ),
              ),
              if (loading)
                const Expanded(
                    child: Center(
                        child: CircularProgressIndicator(color: idaGreen)))
              else
                Expanded(
                  child: Responsive.constrainedContent(
                      context,
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        children: [
                          if (summary != null) _tankCard(summary!),
                          const SizedBox(height: 16),
                          Text(loc.ftFillupHistory,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6B7280),
                                  letterSpacing: 0.6)),
                          const SizedBox(height: 8),
                          if (logs.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFE0E7D8))),
                              child: Text(loc.ftNoDieselLogs,
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 13)),
                            )
                          else
                            ...logs.map((l) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFE0E7D8))),
                                  child: Row(children: [
                                    const Icon(Icons.local_gas_station,
                                        color: idaGreen, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('${l['liters_filled']} L${l['is_full'] == 1 || l['is_full'] == true ? '  · filled to full' : ''}',
                                                style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            Text(
                                              '${l['log_date']}${l['hour_meter_reading'] != null ? ' · meter: ${l['hour_meter_reading']}' : ''}',
                                              style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.grey.shade600),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ]),
                                    ),
                                    if (l['cost'] != null)
                                      Text('₹${l['cost']}',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: idaGreen)),
                                  ]),
                                )),
                        ],
                      )),
                ),
            ]),
    );
  }
}
