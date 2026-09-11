import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class MaintenanceScreen extends StatefulWidget {
  final int? initialTabIndex;
  const MaintenanceScreen({super.key, this.initialTabIndex});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen>
    with SingleTickerProviderStateMixin {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const red = Color(0xFFE24B4A);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  late TabController _tabs;
  List activities = [];
  List alerts = [];
  List log = [];
  double odometer = 0;
  bool loading = true;
  // Matches the backend's ACTUAL authorization model (is_admin flag OR
  // a per-module permissions array with edit-level access) - NOT a
  // crude role-string comparison, same fix as machine_maintenance_screen.dart.
  bool canEdit = false;
  bool canAdd = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 3, vsync: this, initialIndex: widget.initialTabIndex ?? 0);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    final p = await SharedPreferences.getInstance();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${p.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _refreshCanEdit() async {
    // Was a custom, inline implementation that only matched the exact
    // legacy 'edit' string - missed anyone granted the newer granular
    // levels (add/update/delete). ApiService.canEdit/canAdd already
    // handle this correctly.
    canEdit = await ApiService.canEdit('tractor_maintenance');
    canAdd = await ApiService.canAdd('tractor_maintenance');
  }

  Future<void> _loadAll() async {
    setState(() => loading = true);
    try {
      await _refreshCanEdit();
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/maintenance/activities'), headers: h),
        http.get(Uri.parse('$baseUrl/maintenance/alerts'), headers: h),
        http.get(Uri.parse('$baseUrl/maintenance/log'), headers: h),
      ]);
      if (results[0].statusCode == 200) {
        final data = jsonDecode(results[0].body);
        setState(() {
          odometer = double.tryParse(data['odometer'].toString()) ?? 0;
          activities = data['activities'] ?? [];
        });
      }
      if (results[1].statusCode == 200)
        setState(() => alerts = jsonDecode(results[1].body));
      if (results[2].statusCode == 200)
        setState(() => log = jsonDecode(results[2].body));
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _markDone(Map activity) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Text(activity['icon'] ?? '🔧', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(activity['name'] ?? '',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current odometer: ${odometer.toStringAsFixed(1)} hrs',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          Text(
              'Next due at: ${(odometer + (activity['threshold_hours'] ?? 0)).toStringAsFixed(1)} hrs',
              style: const TextStyle(
                  fontSize: 13, color: idaGreen, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: notesCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Notes (optional)',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: idaGreen)),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            child: const Text('Mark as Done',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Logging maintenance…'),
          ]),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final h = await _headers;
      final res = await http
          .post(
            Uri.parse('$baseUrl/maintenance/log'),
            headers: h,
            body: jsonEncode({
              'activity_id': activity['id'],
              'notes': notesCtrl.text.trim(),
              'done_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Unexpected response from server (status ${res.statusCode})'),
              backgroundColor: red));
        }
        return;
      }

      if (res.statusCode == 200) {
        _loadAll();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '✅ ${activity['name']} logged — awaiting approval (it will keep showing as overdue until then)'),
            backgroundColor: idaGreen,
          ));
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error'] ?? 'Failed'),
            backgroundColor: red,
          ));
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Request timed out — check your connection and try again'),
            backgroundColor: red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: red));
      }
    }
  }

  Future<void> _acknowledgeAlert(int alertId) async {
    try {
      final h = await _headers;
      final res = await http
          .patch(Uri.parse('$baseUrl/maintenance/alerts/$alertId/acknowledge'),
              headers: h)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        _loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Alert acknowledged'), backgroundColor: idaGreen));
        }
      } else {
        if (mounted) {
          Map<String, dynamic> data = {};
          try {
            data = jsonDecode(res.body);
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['error'] ??
                  'Failed to acknowledge (status ${res.statusCode})'),
              backgroundColor: red));
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Request timed out — check your connection and try again'),
            backgroundColor: red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: red));
      }
    }
  }

  Future<void> _updateThreshold(Map activity) async {
    final ctrl =
        TextEditingController(text: activity['threshold_hours'].toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Update threshold — ${activity['name']}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Threshold hours',
            suffixText: 'hrs',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: idaGreen)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final h = await _headers;
    await http.patch(
      Uri.parse('$baseUrl/maintenance/activities/${activity['id']}'),
      headers: h,
      body: jsonEncode({'threshold_hours': double.tryParse(ctrl.text)}),
    );
    _loadAll();
  }

  Future<void> _approveLog(int logId, String status) async {
    try {
      final h = await _headers;
      final res = await http
          .patch(
            Uri.parse('$baseUrl/maintenance/log/$logId/status'),
            headers: h,
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        _loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Maintenance $status'), backgroundColor: idaGreen));
        }
      } else {
        if (mounted) {
          Map<String, dynamic> data = {};
          try {
            data = jsonDecode(res.body);
          } catch (_) {}
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['error'] ??
                  'Failed to update (status ${res.statusCode})'),
              backgroundColor: red));
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Request timed out — check your connection and try again'),
            backgroundColor: red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overdueCount =
        activities.where((a) => a['is_overdue'] == true).length;
    final alertCount = alerts.where((a) => a['acknowledged'] == 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 8),
          const Flexible(
              child: Text('Tractor Maintenance',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
          if (overdueCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: red, borderRadius: BorderRadius.circular(10)),
              child: Text('$overdueCount overdue',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _loadAll)
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: amber,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Activities'),
            Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Alerts'),
              if (alertCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                    width: 16,
                    height: 16,
                    decoration:
                        const BoxDecoration(color: red, shape: BoxShape.circle),
                    child: Center(
                        child: Text('$alertCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)))),
              ],
            ])),
            const Tab(text: 'History'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : TabBarView(controller: _tabs, children: [
              _activitiesTab(),
              _alertsTab(),
              _historyTab(),
            ]),
    );
  }

  // ── ACTIVITIES TAB ────────────────────────────────────
  Widget _activitiesTab() => RefreshIndicator(
        color: idaGreen,
        onRefresh: _loadAll,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Odometer card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: idaDark, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.speed, color: Colors.white70, size: 28),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Current odometer',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                Text('${odometer.toStringAsFixed(1)} hrs',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),

          const SizedBox(height: 16),

          ...activities.map<Widget>((a) => _activityCard(a)).toList(),
        ]),
      );

  Widget _activityCard(Map a) {
    final isOverdue = a['is_overdue'] == true;
    final isDueSoon = a['is_due_soon'] == true;
    final hoursUntil = (a['hours_until_due'] as num?)?.toDouble() ?? 0;
    final nextDue = (a['next_due_at'] as num?)?.toDouble() ?? 0;
    final threshold = (a['threshold_hours'] as num?)?.toDouble() ?? 0;
    final lastDoneAt = (a['last_done_at'] as num?)?.toDouble();
    final daysUntilDue = (a['days_until_due'] as num?)?.toDouble();
    final dailyRate = (a['daily_usage_rate'] as num?)?.toDouble();

    Color statusColor;
    String statusText;
    if (isOverdue) {
      statusColor = red;
      statusText = '⚠ OVERDUE';
    } else if (isDueSoon) {
      statusColor = amber;
      statusText = '⏰ DUE SOON';
    } else {
      statusColor = idaGreen;
      statusText = '✓ OK';
    }

    // Progress: hours since last done / threshold
    final double progress = lastDoneAt != null
        ? ((odometer - lastDoneAt) / threshold).clamp(0.0, 1.0)
        : (odometer / threshold).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue
              ? red.withOpacity(0.4)
              : isDueSoon
                  ? amber.withOpacity(0.4)
                  : const Color(0xFFE0E7D8),
          width: isOverdue || isDueSoon ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Text(a['icon'] ?? '🔧', style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(a['name'] ?? '',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Every ${threshold.toStringAsFixed(0)} hrs',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(statusText,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
                if (canEdit) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _updateThreshold(a),
                    child: const Text('Edit threshold',
                        style: TextStyle(
                            fontSize: 10,
                            color: idaGreen,
                            decoration: TextDecoration.underline)),
                  ),
                ],
              ]),
            ])),

        // Progress bar
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                  lastDoneAt != null
                      ? 'Last done at ${lastDoneAt.toStringAsFixed(1)} hrs'
                      : 'Never done',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
                Text(
                  isOverdue
                      ? '${(-hoursUntil).toStringAsFixed(1)} hrs overdue'
                      : 'Due at ${nextDue.toStringAsFixed(1)} hrs',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: statusColor.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
              if (daysUntilDue != null && dailyRate != null) ...[
                const SizedBox(height: 6),
                Text(
                  daysUntilDue >= 0
                      ? 'At current usage (${dailyRate.toStringAsFixed(1)} hrs/day), due in ~${daysUntilDue.toStringAsFixed(1)} day${daysUntilDue.abs() == 1 ? '' : 's'}'
                      : 'At current usage (${dailyRate.toStringAsFixed(1)} hrs/day), overdue by ~${(-daysUntilDue).toStringAsFixed(1)} day${daysUntilDue.abs() == 1 ? '' : 's'} worth',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ])),

        // Action button
        Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canAdd ? () => _markDone(a) : null,
                icon: const Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.white),
                label: Text(canAdd ? 'Mark as Done' : 'No permission',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  disabledBackgroundColor: Colors.grey.shade300,
                  backgroundColor: isOverdue ? red : idaGreen,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            )),
      ]),
    );
  }

  // ── ALERTS TAB ────────────────────────────────────────
  Widget _alertsTab() {
    if (alerts.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.notifications_none, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('No active alerts',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
        const SizedBox(height: 8),
        Text('All maintenance is up to date!',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ]));

    return ListView(padding: const EdgeInsets.all(16), children: [
      ...alerts.map<Widget>((alert) {
        final acked = alert['acknowledged'] == 1;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: acked ? Colors.white : const Color(0xFFFFF3F3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: acked ? const Color(0xFFE0E7D8) : red.withOpacity(0.3)),
          ),
          child: Row(children: [
            Text(alert['icon'] ?? '🔧', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(alert['activity_name'] ?? '',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Triggered at ${alert['triggered_at']} hrs',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                  if (!acked)
                    const Text('⚠ Needs attention',
                        style: TextStyle(
                            fontSize: 11,
                            color: red,
                            fontWeight: FontWeight.w600)),
                ])),
            if (!acked)
              ElevatedButton(
                onPressed: () => _acknowledgeAlert(alert['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: amber,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Acknowledge',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              )
            else
              const Icon(Icons.check_circle, color: idaGreen, size: 20),
          ]),
        );
      }).toList(),
    ]);
  }

  // ── HISTORY TAB ───────────────────────────────────────
  Widget _historyTab() {
    if (log.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text('No maintenance history yet',
            style: TextStyle(color: Colors.grey.shade500)),
      ]));

    return ListView(
        padding: const EdgeInsets.all(16),
        children: log.map<Widget>((entry) {
          final statusColor = entry['status'] == 'approved'
              ? idaGreen
              : entry['status'] == 'rejected'
                  ? red
                  : amber;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E7D8))),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(entry['icon'] ?? '🔧',
                    style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(entry['activity_name'] ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusColor.withOpacity(0.3))),
                  child: Text(entry['status']?.toString().toUpperCase() ?? '',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor)),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _historyChip(
                    Icons.speed, 'Done at ${entry['tractor_hours_at']} hrs'),
                const SizedBox(width: 8),
                _historyChip(Icons.arrow_forward,
                    'Next at ${entry['next_due_at_hours']} hrs'),
              ]),
              if (entry['done_by_name'] != null) ...[
                const SizedBox(height: 4),
                Text(
                    'By ${entry['done_by_name']} · ${entry['done_date']?.toString().substring(0, 10) ?? ''}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
              if (entry['notes'] != null &&
                  entry['notes'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(entry['notes'],
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              ],
              // Approve/reject for admin/office
              if (canEdit && entry['status'] == 'pending') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                    onPressed: () => _approveLog(entry['id'], 'rejected'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: red,
                        side: BorderSide(color: red.withOpacity(0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text('Reject', style: TextStyle(fontSize: 12)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                      child: ElevatedButton(
                    onPressed: () => _approveLog(entry['id'], 'approved'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: idaGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text('Approve',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  )),
                ]),
              ],
            ]),
          );
        }).toList());
  }

  Widget _historyChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: const Color(0xFFE8F5E2),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: idaGreen),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: idaDark, fontWeight: FontWeight.w500)),
        ]),
      );
}
