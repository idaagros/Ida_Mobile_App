// lib/screens/needs_attention_screen.dart
//
// Aggregates every "awaiting a decision" item across the whole app
// into one list, backed by GET /api/needs-attention. Permission-aware
// on the server side already — this screen just renders whatever the
// API returns for the logged-in user, grouped by sector (Factory /
// Agriculture / Admin) so the two-sector split introduced earlier in
// the dashboard carries through here too.
//
// Tapping an item navigates to that module's own screen rather than
// attempting custom deep-linking to the exact date — every reading
// screen already has its own Pending/Approved/Returned tabs, so
// landing on the screen surfaces the relevant item without needing to
// thread date parameters through every screen's constructor.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'attendance_screen.dart';
import 'work_allocation_screen.dart';
import 'admin_review_screen.dart';
import 'machine_maintenance_screen.dart';
import 'maintenance_screen.dart';
import 'outward_register_review_screen.dart';
import 'otp_approvals_screen.dart';
import 'electricity_screen.dart';
import 'machine_reading_screen.dart';
import 'machine_pf_screen.dart';
import 'tractor_screen.dart';
import 'reading_reminder_settings_screen.dart';
import '../services/responsive.dart';

import '../config/app_config.dart';
class NeedsAttentionScreen extends StatefulWidget {
  const NeedsAttentionScreen({super.key});
  @override
  State<NeedsAttentionScreen> createState() => _NeedsAttentionScreenState();
}

class _NeedsAttentionScreenState extends State<NeedsAttentionScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = AppConfig.apiBaseUrl;

  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  static const Map<String, String> _sectorLabels = {
    'factory': 'Factory',
    'agriculture': 'Agriculture',
    'admin': 'Admin',
  };

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
      final h = await _headers;
      final res =
          await http.get(Uri.parse('$baseUrl/needs-attention'), headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(
            () => items = List<Map<String, dynamic>>.from(data['items'] ?? []));
      } else {
        setState(() => error = 'Failed to load');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  void _openItem(Map<String, dynamic> item) {
    final module = item['module'] as String;
    final params = Map<String, dynamic>.from(item['route_params'] ?? {});
    Widget? screen;

    // Missing entries need the ENTRY screen, not the review screen -
    // there's nothing to review yet, that's the whole point. Handled
    // separately, before the pending-approval switch below, since the
    // same module key routes to a completely different destination
    // depending on which situation this actually is.
    if (item['item_type'] == 'missing_entry') {
      switch (module) {
        case 'electricity':
          screen = const ElectricityReadingScreen();
          break;
        case 'machine':
          screen = const MachineReadingScreen();
          break;
        case 'machine_pf':
          screen = const MachinePfScreen();
          break;
        case 'tractor':
          screen = const TractorReadingScreen();
          break;
      }
      if (screen != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen!))
            .then((_) => _load());
      }
      return;
    }

    switch (module) {
      case 'farm_attendance':
        final date = _parseDate(params['date']) ?? _parseDate(item['date']);
        if (date == null) return;
        screen = params['stage'] == 'allocation'
            ? WorkAllocationScreen(attendanceDate: date)
            : AttendanceScreen(initialDate: date);
        break;
      // These five all share one review screen with a tab per module -
      // landing on the bare entry screen would show a blank "new
      // entry" form, not the pending record. AdminReviewScreen already
      // has the approve/reject buttons; it just needs to open on the
      // right tab instead of always defaulting to Electricity.
      case 'electricity':
        screen = const AdminReviewScreen(
            initialFilter: 'pending', initialTabIndex: 0);
        break;
      case 'tractor':
        screen = const AdminReviewScreen(
            initialFilter: 'pending', initialTabIndex: 1);
        break;
      case 'factory':
        screen = const AdminReviewScreen(
            initialFilter: 'pending', initialTabIndex: 3);
        break;
      case 'machine':
        screen = const AdminReviewScreen(
            initialFilter: 'pending', initialTabIndex: 4);
        break;
      case 'machine_pf':
        screen = const AdminReviewScreen(
            initialFilter: 'pending', initialTabIndex: 5);
        break;
      // Same reasoning - the approve/reject list lives in the History
      // tab (index 2), not the default Activities tab.
      case 'machine_maintenance':
        screen = const MachineMaintScreen(initialTabIndex: 2);
        break;
      case 'tractor_maintenance':
        screen = const MaintenanceScreen(initialTabIndex: 2);
        break;
      // Outward Register's review UI takes the specific record - this
      // is the one place a plain list wouldn't even show which record
      // is pending, since pending status lives per-section not per-list-row.
      case 'outward_register':
        final recordId = params['record_id'];
        if (recordId == null) return;
        screen = OutwardRegisterReviewScreen(
            recordId: recordId is int
                ? recordId
                : int.tryParse(recordId.toString()) ?? 0);
        break;
      case 'otp_approval':
        screen = const OtpApprovalsScreen();
        break;
    }
    if (screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen!))
          .then((_) => _load());
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw.toString());
      return DateFormat('dd MMM').format(d);
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bySector = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final sector = item['sector'] as String? ?? 'other';
      bySector.putIfAbsent(sector, () => []).add(item);
    }
    // Stable, meaningful order: Agriculture, Factory, then Admin last.
    final sectorOrder = ['agriculture', 'factory', 'admin']
        .where((s) => bySector.containsKey(s))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Needs Attention',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Reminder Settings',
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReadingReminderSettingsScreen()));
              _load();
            },
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _load,
              child: Responsive.constrainedContent(
                  context,
                  items.isEmpty
                      ? ListView(children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      error ??
                                          "You're all caught up — nothing needs a decision right now.",
                                      style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13.5),
                                      textAlign: TextAlign.center,
                                    ),
                                  ]),
                            ),
                          ),
                        ])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          children: [
                            for (final sector in sectorOrder) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10, top: 6),
                                child: Row(children: [
                                  Text(_sectorLabels[sector] ?? sector,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF6B7280),
                                          letterSpacing: 0.6)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFFEF3DC),
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    child: Text('${bySector[sector]!.length}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF92600A))),
                                  ),
                                ]),
                              ),
                              ...bySector[sector]!
                                  .map((item) => _itemCard(item)),
                              const SizedBox(height: 8),
                            ],
                          ],
                        )),
            ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final isMissing = item['item_type'] == 'missing_entry';
    return InkWell(
      onTap: () => _openItem(item),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Row(children: [
          isMissing
              ? const Icon(Icons.edit_off_outlined,
                  size: 16, color: Color(0xFFC0392B))
              : Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                      color: Color(0xFFE67E22), shape: BoxShape.circle),
                ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(item['module_label'] ?? '',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: idaDark),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ),
                if (item['date'] != null)
                  Text(_formatDate(item['date']),
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 3),
              Text(item['summary'] ?? '',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2),
              if (item['detail'] != null) ...[
                const SizedBox(height: 2),
                Text(item['detail'],
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ]),
      ),
    );
  }
}
