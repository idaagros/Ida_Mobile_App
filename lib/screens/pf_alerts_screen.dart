// lib/screens/pf_alerts_screen.dart
//
// Admin-only screen listing unacknowledged low Power-Factor (PF) alerts
// from machine readings. PF below 0.99 typically means the utility will
// charge a power-factor penalty, so these are surfaced separately from
// the normal pending/approved/returned review queue.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

class PfAlertsScreen extends StatefulWidget {
  const PfAlertsScreen({super.key});
  @override
  State<PfAlertsScreen> createState() => _PfAlertsScreenState();
}

class _PfAlertsScreenState extends State<PfAlertsScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  List _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<Map<String, String>> get _headers async {
    final p = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${p.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _fetchAlerts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/machine-pf/pf-alerts'),
          headers: h);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() => _alerts = body is List ? body : []);
      } else {
        setState(() => _error = 'Failed to load alerts');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(dynamic id) async {
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/machine-pf/pf-alerts/$id/acknowledge'),
        headers: h,
      );
      if (res.statusCode == 200) {
        setState(() => _alerts.removeWhere((a) => a['id'] == id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Alert acknowledged'),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      }
    } catch (e) {
      debugPrint('acknowledge error: $e');
    }
  }

  String? _photoUrl(String? relativeUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) return null;
    final host = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
    return '$host$relativeUrl';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Low PF Alerts',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
      body: Responsive.constrainedContent(
          context,
          _loading
              ? const Center(child: CircularProgressIndicator(color: idaGreen))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  : _alerts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      size: 56, color: Colors.grey.shade300),
                                  const SizedBox(height: 14),
                                  const Text('No low PF alerts',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black54)),
                                  const SizedBox(height: 6),
                                  Text('All machine PF readings are healthy.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade500)),
                                ]),
                          ),
                        )
                      : RefreshIndicator(
                          color: idaGreen,
                          onRefresh: _fetchAlerts,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _alerts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final a = _alerts[i];
                              final pf = double.tryParse(
                                      a['pf_value']?.toString() ?? '') ??
                                  0;
                              final photo =
                                  _photoUrl(a['pf_photo_url']?.toString());
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFF3B9B9)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: photo != null
                                          ? Image.network(photo,
                                              width: 70,
                                              height: 70,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                      width: 70,
                                                      height: 70,
                                                      color:
                                                          Colors.grey.shade200,
                                                      child: const Icon(
                                                          Icons.bolt,
                                                          color: Colors.grey)))
                                          : Container(
                                              width: 70,
                                              height: 70,
                                              color: Colors.grey.shade200,
                                              child: const Icon(Icons.bolt,
                                                  color: Colors.grey)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('PF ${pf.toStringAsFixed(3)}',
                                              style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFFB23A3A))),
                                          const SizedBox(height: 2),
                                          Text(
                                            a['reading_date'] != null
                                                ? DateFormat('dd-MMM-yyyy')
                                                    .format(DateTime.parse(
                                                        a['reading_date']
                                                            .toString()))
                                                : '',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF6B7280)),
                                          ),
                                          if (a['submitted_by'] != null)
                                            Text('By ${a['submitted_by']}',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF6B7280))),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _acknowledge(a['id']),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: idaGreen,
                                                side: const BorderSide(
                                                    color: idaGreen),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 6),
                                              ),
                                              child: const Text('Acknowledge',
                                                  style:
                                                      TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        )),
    );
  }
}
