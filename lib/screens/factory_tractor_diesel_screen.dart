// lib/screens/factory_tractor_diesel_screen.dart
//
// Diesel tracking for the factory's own tractor - completes the
// commitment made during the TV dashboard design round. Correlates
// fill-ups against the existing daily tractor_readings timeline
// rather than asking for a separate hour-meter snapshot at each
// fill-up (see the backend migration's comment for the full reasoning).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FactoryTractorDieselScreen extends StatefulWidget {
  const FactoryTractorDieselScreen({super.key});
  @override
  State<FactoryTractorDieselScreen> createState() => _FactoryTractorDieselScreenState();
}

class _FactoryTractorDieselScreenState extends State<FactoryTractorDieselScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
  }

  Future<bool> get _canEdit async {
    final prefs = await SharedPreferences.getInstance();
    final permsRaw = prefs.getString('permissions') ?? '[]';
    final isAdmin = prefs.getBool('is_admin') ?? false;
    if (isAdmin) return true;
    try {
      final perms = List<Map<String, dynamic>>.from(jsonDecode(permsRaw));
      return perms.any((p) => p['module'] == 'tractor' && p['level'] == 'edit');
    } catch (_) {
      return false;
    }
  }

  bool loading = true;
  bool canEdit = false;
  List<Map<String, dynamic>> logs = [];
  double? averageLPerHour;
  String? averageNote;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/tractor/diesel-logs'), headers: h),
        http.get(Uri.parse('$baseUrl/tractor/diesel-logs/average'), headers: h),
      ]);
      final canEditNow = await _canEdit;
      if (results[0].statusCode == 200) {
        setState(() => logs = List<Map<String, dynamic>>.from(jsonDecode(results[0].body)));
      }
      if (results[1].statusCode == 200) {
        final avgData = jsonDecode(results[1].body);
        setState(() {
          averageLPerHour = (avgData['average_liters_per_hour'] as num?)?.toDouble();
          averageNote = avgData['note'];
        });
      }
      setState(() => canEdit = canEditNow);
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _updateStatus(int id, String status) async {
    try {
      final h = await _headers;
      await http.patch(
        Uri.parse('$baseUrl/tractor/diesel-logs/$id/status'),
        headers: h,
        body: jsonEncode({'status': status}),
      );
      _load();
    } catch (_) {}
  }

  void _showAddDialog() {
    DateTime logDate = DateTime.now();
    final litersCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Log Diesel Fill-up', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: ctx, initialDate: logDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) setDialogState(() => logDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Date', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                  child: Text(DateFormat('dd MMM yyyy').format(logDate)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: litersCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Liters filled', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Cost (optional)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(labelText: 'Notes (optional)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: submitting ? null : () async {
                final liters = double.tryParse(litersCtrl.text.trim());
                if (liters == null) return;
                setDialogState(() => submitting = true);
                final h = await _headers;
                await http.post(
                  Uri.parse('$baseUrl/tractor/diesel-logs'),
                  headers: h,
                  body: jsonEncode({
                    'log_date': DateFormat('yyyy-MM-dd').format(logDate),
                    'liters_filled': liters,
                    'cost': double.tryParse(costCtrl.text.trim()),
                    'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved': return idaGreen;
      case 'returned': return const Color(0xFFC0392B);
      default: return const Color(0xFF92600A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Factory Tractor — Diesel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: idaGreen,
        onPressed: _showAddDialog,
        child: const Icon(Icons.local_gas_station, color: Colors.white),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFFDE8E8), borderRadius: BorderRadius.circular(12)),
                      child: Text(error!, style: const TextStyle(color: Color(0xFFC0392B), fontSize: 13)),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: idaDark, borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      Text('AVERAGE CONSUMPTION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.7), letterSpacing: 0.6)),
                      const SizedBox(height: 8),
                      Text(
                        averageLPerHour != null ? '${averageLPerHour!.toStringAsFixed(2)} L/hr' : '—',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      if (averageNote != null) ...[
                        const SizedBox(height: 6),
                        Text(averageNote!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.6))),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Text('FILL-UP HISTORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.6)),
                  const SizedBox(height: 10),
                  if (logs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: Text('No diesel logs yet — tap + to add one.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
                    )
                  else
                    ...logs.map((log) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7D8))),
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(DateFormat('dd MMM yyyy').format(DateTime.parse(log['log_date'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: _statusColor(log['status']).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                    child: Text((log['status'] ?? '').toString().toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: _statusColor(log['status']))),
                                  ),
                                ]),
                                const SizedBox(height: 4),
                                Text('${log['liters_filled']} L${log['cost'] != null ? ' · ₹${log['cost']}' : ''}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
                                if (log['notes'] != null)
                                  Text(log['notes'], style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
                              ]),
                            ),
                            if (canEdit && log['status'] == 'pending') ...[
                              IconButton(icon: const Icon(Icons.check_circle_outline, color: idaGreen), onPressed: () => _updateStatus(log['id'], 'approved')),
                              IconButton(icon: const Icon(Icons.cancel_outlined, color: Color(0xFFC0392B)), onPressed: () => _updateStatus(log['id'], 'returned')),
                            ],
                          ]),
                        )),
                ],
              ),
            ),
    );
  }
}
