// lib/screens/farm_picker_screen.dart
//
// Simple "pick a farm" list used as the entry point into Precision
// Agriculture from the dashboard tile - the farm list itself already
// exists (Farm Masters), so this doesn't duplicate that management
// screen, it just gets you to a specific farm's Precision Ag view.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'farm_precision_ag_screen.dart';

class FarmPickerScreen extends StatefulWidget {
  final bool canEdit; // draw/edit boundary + trigger refresh, vs read-only
  const FarmPickerScreen({super.key, required this.canEdit});
  @override
  State<FarmPickerScreen> createState() => _FarmPickerScreenState();
}

class _FarmPickerScreenState extends State<FarmPickerScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List farms = [];
  bool loading = true;
  String? error;
  String _query = '';

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
    setState(() { loading = true; error = null; });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/farms'), headers: h);
      if (res.statusCode == 200) {
        farms = jsonDecode(res.body);
        farms.sort((a, b) => (a['name'] ?? '').toString().toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      } else {
        error = 'Could not load farms (${res.statusCode})';
      }
    } catch (e) {
      error = 'Could not reach server: $e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? farms
        : farms.where((f) => (f['name'] ?? '').toString().toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Precision Agriculture', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, style: const TextStyle(color: Colors.red))))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'Search farms…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No farms found', style: TextStyle(color: Colors.black45)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final f = visible[i];
                              final hasBoundary = f['boundary_area_acre'] != null;
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => FarmPrecisionAgScreen(
                                              farmId: f['id'],
                                              farmName: f['name'] ?? '',
                                              canEdit: widget.canEdit))),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE0E7D8)),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.satellite_alt_outlined, color: hasBoundary ? idaGreen : Colors.grey.shade400, size: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(f['name'] ?? '', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 2),
                                            Text(
                                              hasBoundary
                                                  ? '${double.tryParse(f['boundary_area_acre'].toString())?.toStringAsFixed(2) ?? f['boundary_area_acre']} acres drawn'
                                                  : 'No boundary drawn yet',
                                              style: TextStyle(fontSize: 12, color: hasBoundary ? Colors.grey.shade600 : Colors.orange.shade700),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, color: Colors.black26),
                                    ]),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}
