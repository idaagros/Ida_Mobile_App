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

class OutwardRegisterListScreen extends StatefulWidget {
  const OutwardRegisterListScreen({super.key});
  @override
  State<OutwardRegisterListScreen> createState() => _OutwardRegisterListScreenState();
}

class _OutwardRegisterListScreenState extends State<OutwardRegisterListScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List records = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
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
      final res = await http.get(Uri.parse('$baseUrl/outward-register'), headers: h);
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

  String _overallLabel(Map record) {
    final sections = (record['sections'] as List? ?? []);
    if (sections.isEmpty) return 'Not started';
    final approved = sections.where((s) => s['status'] == 'approved').length;
    final returned = sections.where((s) => s['status'] == 'returned').length;
    if (returned > 0) return '$returned section${returned == 1 ? '' : 's'} returned';
    if (approved == sections.length && sections.length == 5) return 'All approved';
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: idaGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Dispatch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const OutwardRegisterScreen()));
          _load();
        },
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  color: idaGreen,
                  onRefresh: _load,
                  child: records.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Column(children: [
                              Icon(Icons.local_shipping_outlined, size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 14),
                              const Text('No dispatch entries yet',
                                  style: TextStyle(fontSize: 15, color: Colors.black54)),
                              const SizedBox(height: 6),
                              Text('Tap "New Dispatch" to log a truck dispatch',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ]),
                          ),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                          itemCount: records.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = records[i];
                            final date = DateTime.tryParse(r['dispatch_date']?.toString() ?? '');
                            return GestureDetector(
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => OutwardRegisterScreen(recordId: r['id'])));
                                _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE0E7D8)),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(color: idaGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.local_shipping, color: idaGreen, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(r['truck_number'] ?? '—',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                      Text('${r['party_name'] ?? ''} → ${r['destination_name'] ?? ''}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                                      Text(
                                        date != null ? DateFormat('dd-MMM-yyyy').format(date) : '',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                      ),
                                    ]),
                                  ),
                                  Text(_overallLabel(r),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB8860B))),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
