// lib/screens/farm_tractor_diesel_screen.dart
//
// Diesel fill-up records per tractor, plus a computed liters-per-hour
// average. See migrations/farm/schema.md for exactly how "average" is
// being interpreted — this is a real assumption, not a spec'd
// formula, so the number shown here should be checked against what
// you actually expect before relying on it.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class FarmTractorDieselScreen extends StatefulWidget {
  const FarmTractorDieselScreen({super.key});
  @override
  State<FarmTractorDieselScreen> createState() =>
      _FarmTractorDieselScreenState();
}

class _FarmTractorDieselScreenState extends State<FarmTractorDieselScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  List tractors = [];
  int? selectedTractorId;
  List logs = [];
  Map? average;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadTractors();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _loadTractors() async {
    setState(() => loading = true);
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/farm-tractor/tractors'),
          headers: h);
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
      final h = await _headers;
      final results = await Future.wait([
        http.get(
            Uri.parse(
                '$baseUrl/farm-tractor/diesel-logs?tractor_id=$selectedTractorId'),
            headers: h),
        http.get(
            Uri.parse(
                '$baseUrl/farm-tractor/diesel-logs/$selectedTractorId/average'),
            headers: h),
      ]);
      if (results[0].statusCode == 200) logs = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) average = jsonDecode(results[1].body);
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
                final h = await _headers;
                final res = await http.post(
                  Uri.parse('$baseUrl/farm-tractor/diesel-logs'),
                  headers: {...h, 'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'tractor_id': selectedTractorId,
                    'log_date': DateFormat('yyyy-MM-dd').format(logDate),
                    'liters_filled': double.tryParse(litersCtrl.text.trim()),
                    'cost': double.tryParse(costCtrl.text.trim()),
                    'hour_meter_reading':
                        double.tryParse(hourMeterCtrl.text.trim()),
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
                          if (average != null)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: idaGreen.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(loc.ftAverageFuelUse,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF6B7280),
                                            letterSpacing: 0.6)),
                                    const SizedBox(height: 6),
                                    if (average!['average_liters_per_hour'] !=
                                        null)
                                      Text(
                                          '${average!['average_liters_per_hour']} L / hour',
                                          style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: idaDark))
                                    else
                                      Text(
                                          average!['note'] ??
                                              'Not enough data yet',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey.shade600)),
                                  ]),
                            ),
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
                                            Text('${l['liters_filled']} L',
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
