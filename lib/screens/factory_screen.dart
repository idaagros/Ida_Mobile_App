import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/responsive.dart';

// ── Downtime reason options ───────────────────────────────
const _reasonOptions = [
  {'value': 'lunch', 'label': 'Lunch break', 'icon': '🍱'},
  {'value': 'dinner', 'label': 'Dinner break', 'icon': '🍽️'},
  {'value': 'power_failure', 'label': 'Power failure', 'icon': '⚡'},
  {'value': 'maintenance', 'label': 'Maintenance', 'icon': '🔧'},
  {'value': 'other', 'label': 'Other', 'icon': '📝'},
];

class FactoryRunScreen extends StatefulWidget {
  const FactoryRunScreen({super.key});
  @override
  State<FactoryRunScreen> createState() => _FactoryRunScreenState();
}

class _FactoryRunScreenState extends State<FactoryRunScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  DateTime selectedDate = DateTime.now().subtract(const Duration(days: 1));
  List entries = [];
  Map summary = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<String> get _token async {
    final p = await SharedPreferences.getInstance();
    return p.getString('token') ?? '';
  }

  Map<String, String> _hdrs(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'ngrok-skip-browser-warning': 'true',
      };

  String get _dateStr => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final t = await _token;
      final h = _hdrs(t);
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/factory?date=$_dateStr'), headers: h),
        http.get(Uri.parse('$baseUrl/factory/summary?date=$_dateStr'),
            headers: h),
      ]);
      if (results[0].statusCode == 200)
        setState(() => entries = jsonDecode(results[0].body));
      if (results[1].statusCode == 200)
        setState(() => summary = jsonDecode(results[1].body));
    } catch (e) {
      debugPrint('Load error: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (c, child) => Theme(
        data: Theme.of(c)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (p != null) {
      setState(() => selectedDate = p);
      _loadData();
    }
  }

  void _openAddForm() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _FactoryEntryForm(
          initialDate: selectedDate,
          baseUrl: baseUrl,
          getToken: () => _token,
          onSaved: _loadData,
        ),
      );

  String _fmtTime(dynamic t) {
    if (t == null) return '—';
    final parts = t.toString().split(':');
    if (parts.length < 2) return t.toString();
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F5),
      appBar: AppBar(
        backgroundColor: idaDark,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(children: [
          Image.asset('assets/images/idalogo.png', height: 28),
          const SizedBox(width: 10),
          const Flexible(
              child: Text('Factory Run Hours',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF5A623)))),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _loadData)
        ],
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddForm,
        backgroundColor: idaGreen,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Entry',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: _loadData,
              child: Responsive.constrainedContent(
                context,
                CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                      child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date picker
                          GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: idaDark,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Row(children: [
                                const Icon(Icons.calendar_today,
                                    color: Colors.white70, size: 18),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Text('Viewing entries for',
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11)),
                                      const SizedBox(height: 2),
                                      Text(
                                          DateFormat('EEEE, d MMMM yyyy')
                                              .format(selectedDate),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600)),
                                    ])),
                                const Icon(Icons.edit,
                                    color: Colors.white54, size: 16),
                              ]),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Summary cards
                          Row(children: [
                            _summaryCard(Icons.today, 'Today',
                                summary['daily_display'] ?? '0h 0m', idaGreen),
                            const SizedBox(width: 10),
                            _summaryCard(Icons.calendar_month, 'This month',
                                summary['monthly_display'] ?? '0h 0m', amber),
                            const SizedBox(width: 10),
                            _summaryCard(
                                Icons.av_timer,
                                'Overall',
                                summary['overall_display'] ?? '0h 0m',
                                const Color(0xFF5A9E40)),
                          ]),

                          const SizedBox(height: 20),

                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    '${entries.length} entr${entries.length == 1 ? 'y' : 'ies'}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                if (entries.isNotEmpty)
                                  Text(
                                      'Total: ${summary['daily_display'] ?? '0h 0m'}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: idaGreen,
                                          fontWeight: FontWeight.w600)),
                              ]),
                          const SizedBox(height: 12),
                        ]),
                  )),
                  entries.isEmpty
                      ? SliverToBoxAdapter(
                          child: Center(
                              child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(children: [
                            Icon(Icons.factory_outlined,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No entries for this date',
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 15)),
                            const SizedBox(height: 8),
                            Text('Tap + Add Entry to get started',
                                style: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 13)),
                          ]),
                        )))
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                          sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _entryCard(entries[i], i + 1),
                            childCount: entries.length,
                          )),
                        ),
                ]),
              )),
    );
  }

  Widget _entryCard(Map entry, int index) {
    final downtimes = (entry['downtimes'] as List?) ?? [];
    final statusColor = entry['status'] == 'approved'
        ? idaGreen
        : entry['status'] == 'rejected'
            ? Colors.red
            : amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text('$index',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: idaGreen)))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        '${_fmtTime(entry['machine_start_time'])} → ${_fmtTime(entry['machine_end_time'])}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('By ${entry['submitted_by'] ?? '—'}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280))),
                  ])),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E2),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(entry['total_run_display'] ?? '—',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: idaGreen))),
            ])),

        // Downtimes
        if (downtimes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
            child: Column(
                children: downtimes.map<Widget>((d) {
              final reason = _reasonOptions.firstWhere(
                (r) => r['value'] == d['reason_type'],
                orElse: () => {'label': 'Other', 'icon': '📝'},
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3DC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFf5d99e)),
                ),
                child: Row(children: [
                  Text(reason['icon']!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                          d['reason_note']?.isNotEmpty == true
                              ? '${reason['label']} — ${d['reason_note']}'
                              : reason['label']!,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7a4d00)),
                        ),
                        Text(
                            '${_fmtTime(d['start_time'])} → ${_fmtTime(d['end_time'])}',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9a6d00))),
                      ])),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFFf5d99e),
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('${d['duration_mins']} min',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7a4d00)))),
                ]),
              );
            }).toList()),
          ),

        // Footer
        Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Row(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withOpacity(0.3))),
                  child: Text(
                      entry['status']?.toString().toUpperCase() ?? 'PENDING',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor))),
              if (downtimes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                    '${downtimes.length} downtime${downtimes.length > 1 ? 's' : ''} · ${entry['total_down_display'] ?? '0h 0m'} lost',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ])),
      ]),
    );
  }

  Widget _summaryCard(IconData icon, String label, String value, Color color) =>
      Expanded(
          child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        ]),
      ));
}

// ─────────────────────────────────────────────────────────────
//  ADD ENTRY FORM
// ─────────────────────────────────────────────────────────────
class _DowntimeSlot {
  TimeOfDay? start;
  TimeOfDay? end;
  String reasonType = 'lunch';
  String reasonNote = '';
  _DowntimeSlot();
}

class _FactoryEntryForm extends StatefulWidget {
  final DateTime initialDate;
  final String baseUrl;
  final Future<String> Function() getToken;
  final VoidCallback onSaved;
  const _FactoryEntryForm(
      {required this.initialDate,
      required this.baseUrl,
      required this.getToken,
      required this.onSaved});
  @override
  State<_FactoryEntryForm> createState() => _FactoryEntryFormState();
}

class _FactoryEntryFormState extends State<_FactoryEntryForm> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);

  final notesCtrl = TextEditingController();
  late DateTime entryDate;
  TimeOfDay? machineStart;
  TimeOfDay? machineEnd;
  List<_DowntimeSlot> downtimes = [];
  bool submitting = false;
  String? errorMsg;
  int? totalRunMins;
  int totalDownMins = 0;

  @override
  void initState() {
    super.initState();
    entryDate = widget.initialDate;
  }

  @override
  void dispose() {
    notesCtrl.dispose();
    super.dispose();
  }

  int _tod2mins(TimeOfDay t) => t.hour * 60 + t.minute;
  String _tod24(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String _fmtTOD(TimeOfDay? t) {
    if (t == null) return 'Tap to set';
    final h = t.hour;
    final m = t.minute;
    final p = h >= 12 ? 'PM' : 'AM';
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $p';
  }

  void _recalc() {
    if (machineStart == null || machineEnd == null) {
      setState(() {
        totalRunMins = null;
        totalDownMins = 0;
      });
      return;
    }
    final ms = _tod2mins(machineStart!);
    final me = _tod2mins(machineEnd!);
    if (me <= ms) {
      setState(() {
        totalRunMins = null;
        errorMsg = 'End time must be after start time';
      });
      return;
    }

    int down = 0;
    for (final d in downtimes) {
      if (d.start != null && d.end != null) {
        final dur = _tod2mins(d.end!) - _tod2mins(d.start!);
        if (dur > 0) down += dur;
      }
    }
    setState(() {
      totalDownMins = down;
      totalRunMins = (me - ms) - down;
      if (totalRunMins! < 0) totalRunMins = 0;
      errorMsg = null;
    });
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: entryDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (c, child) => Theme(
        data: Theme.of(c)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (p != null) setState(() => entryDate = p);
  }

  Future<void> _pickTime(Function(TimeOfDay) onPicked,
      [TimeOfDay? initial]) async {
    final p = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      builder: (c, child) => Theme(
        data: Theme.of(c)
            .copyWith(colorScheme: const ColorScheme.light(primary: idaGreen)),
        child: child!,
      ),
    );
    if (p != null) {
      onPicked(p);
      _recalc();
    }
  }

  String _minsDisplay(int? mins) {
    if (mins == null || mins <= 0) return '—';
    return '${mins ~/ 60}h ${mins % 60}m';
  }

  Future<void> _submit() async {
    if (machineStart == null || machineEnd == null) {
      setState(() => errorMsg = 'Machine start and end times are required');
      return;
    }
    for (int i = 0; i < downtimes.length; i++) {
      final d = downtimes[i];
      if (d.start == null || d.end == null) {
        setState(
            () => errorMsg = 'Downtime ${i + 1}: set both start and end time');
        return;
      }
    }
    if (errorMsg != null && errorMsg!.contains('End time')) return;

    setState(() {
      submitting = true;
      errorMsg = null;
    });

    try {
      final token = await widget.getToken();
      final dateStr = DateFormat('yyyy-MM-dd').format(entryDate);

      final body = jsonEncode({
        'entry_date': dateStr,
        'machine_start_time': _tod24(machineStart!),
        'machine_end_time': _tod24(machineEnd!),
        'notes': notesCtrl.text.trim(),
        'downtimes': downtimes
            .map((d) => {
                  'start_time': _tod24(d.start!),
                  'end_time': _tod24(d.end!),
                  'reason_type': d.reasonType,
                  'reason_note': d.reasonNote,
                })
            .toList(),
      });

      final res = await http.post(
        Uri.parse('${widget.baseUrl}/factory'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'ngrok-skip-browser-warning': 'true',
        },
        body: body,
      );

      debugPrint('FACTORY STATUS: ${res.statusCode}');
      debugPrint('FACTORY BODY: ${res.body}');

      if (res.body.contains('<!DOCTYPE') || res.body.contains('<html')) {
        setState(
            () => errorMsg = 'Tunnel error — restart servers and try again');
        return;
      }

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          widget.onSaved();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Saved — Run: ${data['total_run_display']}, Downtime: ${data['total_down_display']}'),
            backgroundColor: idaGreen,
          ));
        }
      } else {
        setState(() => errorMsg = data['error'] ?? 'Submission failed');
      }
    } catch (e) {
      setState(() => errorMsg = 'Error: $e');
    } finally {
      setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.6,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),

          // Title row
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E2),
                        borderRadius: BorderRadius.circular(10)),
                    child:
                        const Icon(Icons.factory, color: idaGreen, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Add Factory Entry',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: idaDark)),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.calendar_today,
                              size: 11, color: idaGreen),
                          const SizedBox(width: 4),
                          Text(DateFormat('dd MMM yyyy').format(entryDate),
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: idaGreen,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit, size: 11, color: idaGreen),
                        ]),
                      ),
                    ])),
                IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context)),
              ])),

          const Divider(height: 24),

          Expanded(
              child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                // Error
                if (errorMsg != null) ...[
                  Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200)),
                      child: Text(errorMsg!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13))),
                  const SizedBox(height: 16),
                ],

                // Machine times
                _label('MACHINE RUN TIMES'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _timeTile(
                          'Start',
                          machineStart,
                          idaGreen,
                          Icons.play_circle_outline,
                          () => _pickTime(
                              (t) => setState(() => machineStart = t),
                              machineStart))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _timeTile(
                          'End',
                          machineEnd,
                          Colors.red.shade400,
                          Icons.stop_circle_outlined,
                          () => _pickTime((t) => setState(() => machineEnd = t),
                              machineEnd))),
                ]),

                const SizedBox(height: 16),

                // Live total
                if (totalRunMins != null)
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFB8D99E))),
                      child: Row(children: [
                        const Icon(Icons.timelapse, color: idaGreen, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Total run time (auto calculated)',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF6B7280))),
                              const SizedBox(height: 2),
                              Row(children: [
                                Text(_minsDisplay(totalRunMins),
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: idaGreen)),
                                if (totalDownMins > 0) ...[
                                  const SizedBox(width: 12),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFFEF3DC),
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Text(
                                          '−${_minsDisplay(totalDownMins)} downtime',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF7a4d00),
                                              fontWeight: FontWeight.w600))),
                                ],
                              ]),
                            ])),
                      ])),

                const SizedBox(height: 20),

                // Downtimes section
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _label('DOWNTIME SLOTS'),
                      GestureDetector(
                        onTap: () {
                          setState(() => downtimes.add(_DowntimeSlot()));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFEF3DC),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: const Color(0xFFf5d99e))),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add,
                                    size: 14, color: Color(0xFF7a4d00)),
                                SizedBox(width: 4),
                                Text('Add downtime',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF7a4d00),
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ),
                      ),
                    ]),

                const SizedBox(height: 10),

                if (downtimes.isEmpty)
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF7F9F5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE0E7D8))),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            size: 16, color: Color(0xFF9CA3AF)),
                        SizedBox(width: 8),
                        Text('No downtime — machine ran the full period',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF9CA3AF))),
                      ]))
                else
                  ...downtimes
                      .asMap()
                      .entries
                      .map((e) => _downtimeCard(e.key, e.value)),

                const SizedBox(height: 20),

                // Notes
                _label('NOTES (OPTIONAL)'),
                const SizedBox(height: 6),
                TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Any additional observations...',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFFF7F9F5),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE0E7D8))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: idaGreen, width: 1.5)),
                    )),

                const SizedBox(height: 24),

                // Submit
                SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: submitting ? null : _submit,
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save,
                              color: Colors.white, size: 18),
                      label: Text(submitting ? 'Saving...' : 'Save Entry',
                          style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: idaGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    )),
              ])),
        ]),
      ),
    );
  }

  Widget _downtimeCard(int index, _DowntimeSlot slot) {
    final reason = _reasonOptions.firstWhere(
        (r) => r['value'] == slot.reasonType,
        orElse: () => _reasonOptions.last);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFf5d99e)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Text('${reason['icon']} Downtime ${index + 1}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7a4d00))),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() => {downtimes.removeAt(index), _recalc()});
            },
            child: const Icon(Icons.close, size: 18, color: Color(0xFF9CA3AF)),
          ),
        ]),
        const SizedBox(height: 10),

        // Times
        Row(children: [
          Expanded(
              child: _timeTile(
                  'From',
                  slot.start,
                  amber,
                  Icons.pause,
                  () => _pickTime(
                      (t) => setState(() => slot.start = t), slot.start))),
          const SizedBox(width: 10),
          Expanded(
              child: _timeTile(
                  'Until',
                  slot.end,
                  amber,
                  Icons.play_arrow,
                  () => _pickTime(
                      (t) => setState(() => slot.end = t), slot.end))),
        ]),

        // Duration preview
        if (slot.start != null && slot.end != null) ...[
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final dur = _tod2mins(slot.end!) - _tod2mins(slot.start!);
            return dur > 0
                ? Text('Duration: ${dur ~/ 60}h ${dur % 60}m',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF7a4d00),
                        fontWeight: FontWeight.w600))
                : const Text('⚠ End must be after start',
                    style: TextStyle(fontSize: 11, color: Colors.red));
          }),
        ],

        const SizedBox(height: 10),

        // Reason chips
        _label('REASON'),
        const SizedBox(height: 6),
        Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _reasonOptions.map((r) {
              final sel = slot.reasonType == r['value'];
              return GestureDetector(
                onTap: () => setState(() => slot.reasonType = r['value']!),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFFF5A623).withOpacity(0.15)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? amber : const Color(0xFFE0E7D8),
                        width: sel ? 1.5 : 1),
                  ),
                  child: Text('${r['icon']} ${r['label']}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? const Color(0xFF7a4d00)
                              : const Color(0xFF6B7280))),
                ),
              );
            }).toList()),

        // Other reason text
        if (slot.reasonType == 'other') ...[
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => slot.reasonNote = v,
            decoration: InputDecoration(
              hintText: 'Describe the reason...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: amber, width: 1.5)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
          letterSpacing: 0.8));

  Widget _timeTile(String label, TimeOfDay? time, Color color, IconData icon,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: time != null
                ? color.withOpacity(0.07)
                : const Color(0xFFF7F9F5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: time != null
                    ? color.withOpacity(0.4)
                    : const Color(0xFFE0E7D8),
                width: time != null ? 1.5 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 5),
            Row(children: [
              Icon(icon, size: 14, color: time != null ? color : Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(_fmtTOD(time),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              time != null ? color : const Color(0xFF9CA3AF)))),
            ]),
          ]),
        ),
      );
}
