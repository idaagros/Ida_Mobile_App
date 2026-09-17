// lib/screens/outward_register_list_screen.dart
//
// Entry point for the Outward Sales Register from the dashboard. Shows
// recent dispatch entries (each with its section-status dots) and a
// button to start a new one. Tapping a record opens it in
// OutwardRegisterScreen for progressive editing.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'outward_register_screen.dart';
import '../services/responsive.dart';
import '../services/api_service.dart';

class OutwardRegisterListScreen extends StatefulWidget {
  const OutwardRegisterListScreen({super.key});
  @override
  State<OutwardRegisterListScreen> createState() =>
      _OutwardRegisterListScreenState();
}

class _OutwardRegisterListScreenState extends State<OutwardRegisterListScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List records = [];
  bool loading = true;
  String? error;
  bool canAdd = false;
  DateTime? fromDate;
  DateTime? toDate;

  @override
  void initState() {
    super.initState();
    ApiService.canAdd('outward_register').then((v) {
      if (mounted) setState(() => canAdd = v);
    });
    _load();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final h = await _headers;
      final params = <String, String>{};
      if (fromDate != null)
        params['from'] = DateFormat('yyyy-MM-dd').format(fromDate!);
      if (toDate != null)
        params['to'] = DateFormat('yyyy-MM-dd').format(toDate!);
      final uri = Uri.parse('$baseUrl/outward-register')
          .replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: h);
      if (res.statusCode == 200) {
        setState(() => records = jsonDecode(res.body));
      } else {
        setState(() => error = 'Could not load entries');
      }
    } catch (e) {
      setState(() => error = 'Error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? fromDate : toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom)
        fromDate = picked;
      else
        toDate = picked;
    });
    _load();
  }

  void _clearDateRange() {
    setState(() {
      fromDate = null;
      toDate = null;
    });
    _load();
  }

  String _overallLabel(Map record) {
    final sections = (record['sections'] as List? ?? []);
    if (sections.isEmpty) return 'Not started';
    final approved = sections.where((s) => s['status'] == 'approved').length;
    final returned = sections.where((s) => s['status'] == 'returned').length;
    if (returned > 0)
      return '$returned section${returned == 1 ? '' : 's'} returned';
    if (approved == sections.length && sections.length == 5)
      return 'All approved';
    return '$approved of 5 sections approved';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Outward Sales Register',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              backgroundColor: idaGreen,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Dispatch',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const OutwardRegisterScreen()));
                _load();
              },
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: true),
                    child: Text(
                      fromDate == null
                          ? 'From date'
                          : DateFormat('dd-MMM-yyyy').format(fromDate!),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: false),
                    child: Text(
                      toDate == null
                          ? 'To date'
                          : DateFormat('dd-MMM-yyyy').format(toDate!),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                if (fromDate != null || toDate != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear date range',
                    onPressed: _clearDateRange,
                  ),
                ],
              ],
            ),
          ),
          if (fromDate == null && toDate == null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E2D6),
                border: Border.all(color: const Color(0xFFF8AF75)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Showing the 30 most recent records only. Older entries aren't missing — set a \"From\" date above to see your full history.",
                style: TextStyle(fontSize: 11, color: Color(0xFF8A5628)),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: idaGreen))
                : error != null
                    ? Center(
                        child: Text(error!,
                            style: const TextStyle(color: Colors.red)))
                    : RefreshIndicator(
                        color: idaGreen,
                        onRefresh: _load,
                        child: Responsive.constrainedContent(
                            context,
                            records.isEmpty
                                ? ListView(children: [
                                    const SizedBox(height: 120),
                                    Center(
                                      child: Column(children: [
                                        Icon(Icons.local_shipping_outlined,
                                            size: 56,
                                            color: Colors.grey.shade300),
                                        const SizedBox(height: 14),
                                        const Text('No dispatch entries yet',
                                            style: TextStyle(
                                                fontSize: 15,
                                                color: Colors.black54)),
                                        const SizedBox(height: 6),
                                        Text(
                                            'Tap "New Dispatch" to log a truck dispatch',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500)),
                                      ]),
                                    ),
                                  ])
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 90),
                                    itemCount: records.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, i) {
                                      final r = records[i];
                                      final date = DateTime.tryParse(
                                          r['dispatch_date']?.toString() ?? '');
                                      return GestureDetector(
                                        onTap: () async {
                                          await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      OutwardRegisterScreen(
                                                          recordId: r['id'])));
                                          _load();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: const Color(0xFFE0E7D8)),
                                          ),
                                          child: Row(children: [
                                            Container(
                                              width: 42,
                                              height: 42,
                                              decoration: BoxDecoration(
                                                  color:
                                                      idaGreen.withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10)),
                                              child: const Icon(
                                                  Icons.local_shipping,
                                                  color: idaGreen,
                                                  size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        r['truck_number'] ??
                                                            '—',
                                                        style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    Text(
                                                        '${r['party_name'] ?? ''} → ${r['destination_name'] ?? ''}',
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            color: Color(
                                                                0xFF6B7280))),
                                                    Text(
                                                      date != null
                                                          ? DateFormat(
                                                                  'dd-MMM-yyyy')
                                                              .format(date)
                                                          : '',
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors
                                                              .grey.shade400),
                                                    ),
                                                  ]),
                                            ),
                                            Text(_overallLabel(r),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFB8860B))),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.chevron_right,
                                                color: Color(0xFF9CA3AF)),
                                          ]),
                                        ),
                                      );
                                    },
                                  )),
                      ),
          ),
        ],
      ),
    );
  }
}
