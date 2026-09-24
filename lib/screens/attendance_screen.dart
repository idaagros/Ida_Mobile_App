// lib/screens/attendance_screen.dart
//
// Stage A — Attendance Marking. Two-stage workflow, direct-save is
// gone (per the redesign). No headcount step any more (removed 24 Sep
// 2026): pick who's present from the worker master (search +
// checkbox, with an inline "+ Add Worker" for anyone
// missing), save. That SUBMITS the whole day for approval and locks
// it. An admin approves or rejects (one decision covering the whole
// day, not per worker) right here. Approved unlocks Stage B — Work
// Allocation — reached via the button that appears once approved.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../services/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'attendance_report_screen.dart';
import 'work_allocation_screen.dart';
import 'attendance_calendar_screen.dart';
import 'face_attendance_capture_screen.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../config/app_config.dart';

class AttendanceScreen extends StatefulWidget {
  final DateTime? initialDate;
  const AttendanceScreen({super.key, this.initialDate});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const amber = Color(0xFFF5A623);
  static const baseUrl = AppConfig.apiBaseUrl;

  late DateTime selectedDate = widget.initialDate ?? DateTime.now();
  bool isAdmin = false;

  List workers = [];
  bool loadingMasters = true;
  bool loadingDay = false;
  String? error;

  final Set<int> selectedWorkerIds = {};
  final Map<int, TextEditingController> presentWageCtrls = {};
  String workerFilter = 'All'; // 'All' | 'M' | 'F'
  bool savingPresent = false;

  // Day state from GET /day/:date
  String? attendanceStatus; // null | pending | approved | returned
  String? attendanceAdminNote;
  String? allocationStatus;
  // Totals of the submitted present list (from the server), shown once
  // the day is submitted: total, male, female, permanent, total_wage.
  Map<String, dynamic>? presentSummary;
  List<Map<String, dynamic>> presentWorkers = [];
  bool permanentAutoSuggested =
      false; // present_workers came from permanent-worker suggestions, not an actual saved submission

  bool decidingAttendance = false;
  // Stage A (attendance marking) specific access - separate from the
  // existing isAdmin check above, which only gates the admin
  // approve/reject decision, not the day-to-day marking itself.
  bool canUpdateStageA = false;
  // The actual admin approve/reject decision - now its own distinct
  // 'approve' permission rather than the plain isAdmin boolean, so a
  // non-admin can be granted specifically this without full admin.
  bool canApproveStageA = false;

  @override
  void initState() {
    super.initState();
    ApiService.canUpdateSection('farm_attendance', 'attendance').then((v) {
      if (mounted) setState(() => canUpdateStageA = v);
    });
    ApiService.canApproveSection('farm_attendance', 'attendance').then((v) {
      if (mounted) setState(() => canApproveStageA = v);
    });
    _init();
  }

  @override
  void dispose() {
    for (final c in presentWageCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    isAdmin = await ApiService.isAdmin();
    await _loadMasters();
    await _loadDay();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> _loadMasters() async {
    setState(() => loadingMasters = true);
    try {
      final h = await _headers;
      final res =
          await http.get(Uri.parse('$baseUrl/farm-workers'), headers: h);
      if (res.statusCode == 200) {
        workers = jsonDecode(res.body);
        workers.sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }
    } catch (e) {
      debugPrint('Load masters error: $e');
    } finally {
      if (mounted) setState(() => loadingMasters = false);
    }
  }

  Future<void> _loadDay() async {
    setState(() {
      loadingDay = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/attendance/day/$_dateStr'),
          headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          presentSummary = data['present_summary'] is Map
              ? Map<String, dynamic>.from(data['present_summary'])
              : null;
          attendanceStatus = data['attendance_status'];
          attendanceAdminNote = data['attendance_admin_note'];
          allocationStatus = data['allocation_status'];
          permanentAutoSuggested = data['permanent_auto_suggested'] == true;

          presentWorkers =
              List<Map<String, dynamic>>.from(data['present_workers'] ?? []);
          presentWorkers.sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()));
          for (final c in presentWageCtrls.values) c.dispose();
          presentWageCtrls.clear();
          for (final p in presentWorkers) {
            presentWageCtrls[p['worker_id'] as int] =
                TextEditingController(text: p['daily_wage']?.toString() ?? '');
          }
          selectedWorkerIds
            ..clear()
            ..addAll(presentWorkers.map((p) => p['worker_id'] as int));
        });
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loadingDay = false);
    }
  }

  Future<void> _pickDate() async {
    // Uses the same colored Status Calendar as the AppBar's calendar
    // icon, not Flutter's stock showDatePicker — the stock picker has
    // no way to show which dates already have attendance entered, so
    // every day looked identical regardless of status. This one
    // already fetches and colors by status; reusing it here means a
    // day with attendance already marked (or approved) now looks
    // visibly different the moment you open the picker to choose a
    // date, instead of only after separately opening "Status Calendar".
    final picked = await Navigator.push<DateTime>(context,
        MaterialPageRoute(builder: (_) => const AttendanceCalendarScreen()));
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedWorkerIds.clear();
        for (final c in presentWageCtrls.values) c.dispose();
        presentWageCtrls.clear();
      });
      await _loadDay();
    }
  }

  bool get _canEditAttendance =>
      canUpdateStageA &&
      (attendanceStatus == null || attendanceStatus == 'returned');

  void _addWorker(int id) {
    setState(() {
      selectedWorkerIds.add(id);
      final w = workers.firstWhere((w) => w['id'] == id, orElse: () => {});
      presentWageCtrls[id] =
          TextEditingController(text: w['daily_wage']?.toString() ?? '');
    });
  }

  // Face recognition is purely an ALTERNATIVE way to reach the same
  // outcome as tapping a worker in the manual list — it reuses
  // _addWorker() so amount defaults, gender counting, and everything
  // else behaves identically regardless of which way a worker got
  // selected. Android/iOS only (ML Kit + TFLite have no web support).
  Future<void> _markViaFace() async {
    final result = await Navigator.push<FaceMatchResult>(
      context,
      MaterialPageRoute(builder: (_) => const FaceAttendanceCaptureScreen()),
    );
    if (result == null) return;
    if (selectedWorkerIds.contains(result.workerId)) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${tl(context, result.name)} ${loc.faAlreadyMarkedPresent}'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    _addWorker(result.workerId);
    if (mounted) {
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tl(context, result.name)} ${loc.faMarkedViaFace}'),
        backgroundColor: idaGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ));
    }
  }

  void _removeWorker(int id) {
    setState(() {
      selectedWorkerIds.remove(id);
      presentWageCtrls.remove(id)?.dispose();
    });
  }

  double get _computedTotal => presentWageCtrls.values
      .fold(0.0, (s, c) => s + (double.tryParse(c.text.trim()) ?? 0));

  int get _selectedPermanent => selectedWorkerIds.where((id) {
        final w = workers.firstWhere((w) => w['id'] == id, orElse: () => {});
        return w['is_permanent'] == 1 || w['is_permanent'] == true;
      }).length;

  // The day's totals after submission — from the server's
  // present_summary, or worked out from the present list if missing.
  Widget _submittedTotals(AppLocalizations loc) {
    final s = presentSummary;
    int n(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    if (s != null) {
      return _dayTotals(loc,
          title: loc.faPresentToday,
          total: n(s['total']),
          male: n(s['male']),
          female: n(s['female']),
          permanent: n(s['permanent']),
          wage: double.tryParse(s['total_wage']?.toString() ?? '') ?? 0);
    }
    if (presentWorkers.isEmpty) return const SizedBox.shrink();
    return _dayTotals(loc,
        title: loc.faPresentToday,
        total: presentWorkers.length,
        male: presentWorkers.where((p) => p['gender'] == 'M').length,
        female: presentWorkers.where((p) => p['gender'] == 'F').length,
        permanent: presentWorkers
            .where((p) => p['is_permanent'] == 1 || p['is_permanent'] == true)
            .length,
        wage: presentWorkers.fold(
            0.0,
            (sum, p) =>
                sum +
                (double.tryParse(
                        (p['morning_amount'] ?? p['daily_wage'])?.toString() ??
                            '') ??
                    0)));
  }

  // Total workers, male/female split, permanent (included in the
  // total) and total wage. Same box on the web.
  Widget _dayTotals(AppLocalizations loc,
      {required String title,
      required int total,
      required int male,
      required int female,
      required int permanent,
      required double wage}) {
    const grey = TextStyle(fontSize: 12, color: Color(0xFF4B5563));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFFF3F7EF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC9D6BF))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title: $total ${loc.faWorkersWord}',
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700, color: idaDark)),
        const SizedBox(height: 4),
        Wrap(spacing: 14, runSpacing: 2, children: [
          Text('♂ $male ${loc.faMaleFull.toLowerCase()}', style: grey),
          Text('♀ $female ${loc.faFemaleFull.toLowerCase()}', style: grey),
          Text('📌 $permanent ${loc.faPermanentIncluded}', style: grey),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
              child: Text(loc.faTotalWage,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: idaDark))),
          Text('₹${wage.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: idaGreen)),
        ]),
      ]),
    );
  }

  Future<void> _reviewAndSubmit() async {
    if (selectedWorkerIds.isEmpty) {
      setState(() => error = 'Select at least one present worker');
      return;
    }
    final maleList = selectedWorkerIds
        .where((id) =>
            workers.firstWhere((w) => w['id'] == id,
                orElse: () => {})['gender'] ==
            'M')
        .toList();
    final femaleList = selectedWorkerIds
        .where((id) =>
            workers.firstWhere((w) => w['id'] == id,
                orElse: () => {})['gender'] ==
            'F')
        .toList();
    String nameOf(int id) =>
        workers.firstWhere((w) => w['id'] == id, orElse: () => {})['name'] ??
        '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.faReviewPresentWorkers,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (maleList.isNotEmpty) ...[
                      Text(
                          '${loc.faMaleFull.toUpperCase()} (${maleList.length})',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7280))),
                      const SizedBox(height: 4),
                      ...maleList.map((id) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Expanded(
                                  child: Text(tl(context, nameOf(id)),
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1)),
                              Text('₹${presentWageCtrls[id]?.text ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          )),
                      const SizedBox(height: 10),
                    ],
                    if (femaleList.isNotEmpty) ...[
                      Text(
                          '${loc.faFemaleFull.toUpperCase()} (${femaleList.length})',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7280))),
                      const SizedBox(height: 4),
                      ...femaleList.map((id) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [
                              Expanded(
                                  child: Text(tl(context, nameOf(id)),
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1)),
                              Text('₹${presentWageCtrls[id]?.text ?? ''}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          )),
                    ],
                    const Divider(height: 20),
                    _dayTotals(loc,
                        title: loc.faPresentToday,
                        total: selectedWorkerIds.length,
                        male: maleList.length,
                        female: femaleList.length,
                        permanent: _selectedPermanent,
                        wage: _computedTotal),
                  ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.faConfirmSubmit,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _submitPresent();
  }

  Future<void> _submitPresent() async {
    setState(() {
      savingPresent = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.post(
        Uri.parse('$baseUrl/attendance/day/$_dateStr/present'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'workers': selectedWorkerIds
              .map((id) => {
                    'worker_id': id,
                    'amount': double.tryParse(
                        presentWageCtrls[id]?.text.trim() ?? ''),
                  })
              .toList(),
        }),
      );
      if (res.statusCode == 200) {
        await _loadDay();
        if (mounted) {
          final loc = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.faAttendanceSubmitted),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() => error = data['error'] ?? 'Failed to submit attendance');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => savingPresent = false);
    }
  }

  Future<void> _decideAttendance(String decision) async {
    String? note;
    if (decision == 'reject') {
      final loc = AppLocalizations.of(context)!;
      note = await _promptForNote(
          loc.faRejectAttendanceTitle, loc.faRejectAttendanceHint);
      if (note == null || note.trim().isEmpty) return;
    }
    setState(() => decidingAttendance = true);
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/attendance/day/$_dateStr/attendance-decision'),
        headers: {...h, 'Content-Type': 'application/json'},
        body:
            jsonEncode({'decision': decision, if (note != null) 'note': note}),
      );
      if (res.statusCode == 200) {
        await _loadDay();
      } else {
        final data = jsonDecode(res.body);
        setState(() => error = data['error'] ?? 'Failed to record decision');
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => decidingAttendance = false);
    }
  }

  Future<String?> _promptForNote(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            autofocus: true,
            decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(loc.faConfirm,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddWorkerDialog() async {
    final nameCtrl = TextEditingController();
    final wageCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String? gender;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final loc = AppLocalizations.of(ctx)!;
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(loc.faAddWorker,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: loc.faWorkerNameLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: ChoiceChip(
                          label: Text(loc.faMaleFull),
                          selected: gender == 'M',
                          selectedColor: idaGreen.withOpacity(0.15),
                          onSelected: (_) =>
                              setDialogState(() => gender = 'M'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: ChoiceChip(
                          label: Text(loc.faFemaleFull),
                          selected: gender == 'F',
                          selectedColor: idaGreen.withOpacity(0.15),
                          onSelected: (_) =>
                              setDialogState(() => gender = 'F'))),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: wageCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: loc.faDailyWageLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: loc.faPhoneOptionalLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(loc.cancel)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      wageCtrl.text.trim().isEmpty) return;
                  final h = await _headers;
                  final res = await http.post(
                    Uri.parse('$baseUrl/farm-workers'),
                    headers: {...h, 'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'name': nameCtrl.text.trim(),
                      'daily_wage': wageCtrl.text.trim(),
                      'gender': gender,
                      'phone': phoneCtrl.text.trim(),
                    }),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, res.statusCode == 200);
                },
                child: Text(loc.faAdd,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (created == true) {
      await _loadMasters();
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(loc.faWorkerAdded),
          backgroundColor: idaGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
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
        title: Text(loc.faTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: loc.faStatusCalendarTooltip,
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: loc.faReportsTooltip,
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AttendanceReportScreen())),
          ),
        ],
      ),
      body: loadingMasters
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : RefreshIndicator(
              color: idaGreen,
              onRefresh: () async {
                await _loadMasters();
                await _loadDay();
              },
              child: Responsive.constrainedContent(
                  context,
                  ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE0E7D8))),
                          child: Row(children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: idaGreen),
                            const SizedBox(width: 10),
                            Text(
                                DateFormat('EEEE, dd MMM yyyy')
                                    .format(selectedDate),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: idaDark)),
                            const Spacer(),
                            const Icon(Icons.edit_calendar_outlined,
                                size: 18, color: Colors.grey),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _workflowStepper(loc),
                      const SizedBox(height: 12),
                      _statusBanner(loc),
                      const SizedBox(height: 16),
                      if (loadingDay)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(30),
                                child:
                                    CircularProgressIndicator(color: idaGreen)))
                      else ...[
                        _presentWorkersCard(loc),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 12.5)),
                      ],
                    ],
                  )),
            ),
    );
  }

  // Shows where today's entry stands in the two-gate pipeline:
  // Attendance marked/submitted -> Attendance approved ->
  // Allocation submitted -> Allocation approved. A compact segmented
  // bar rather than 4 individually-labeled steps, since 4 labels
  // don't fit comfortably on a narrow phone screen - one clear
  // current-stage sentence below the bar carries the actual meaning.
  Widget _workflowStepper(AppLocalizations loc) {
    int stage; // 1-4, how many segments are "reached"
    String label;
    Color activeColor = idaGreen;

    if (attendanceStatus == null) {
      stage = 1;
      label = loc.faStepMarkPresent;
    } else if (attendanceStatus == 'returned') {
      stage = 1;
      label = loc.faStepAttendanceReturned;
      activeColor = const Color(0xFFC0392B);
    } else if (attendanceStatus == 'pending') {
      stage = 1;
      label = loc.faStepAttendancePending;
      activeColor = const Color(0xFF92600A);
    } else if (allocationStatus == null) {
      stage = 2;
      label = loc.faStepAttendanceApproved;
    } else if (allocationStatus == 'returned') {
      stage = 3;
      label = loc.faStepAllocationReturned;
      activeColor = const Color(0xFFC0392B);
    } else if (allocationStatus == 'pending') {
      stage = 3;
      label = loc.faStepAllocationPending;
      activeColor = const Color(0xFF92600A);
    } else {
      stage = 4;
      label = loc.faStepComplete;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: List.generate(4, (i) {
          final reached = i < stage;
          return Expanded(
            child: Container(
              height: 5,
              margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
              decoration: BoxDecoration(
                color: reached ? activeColor : const Color(0xFFE0E7D8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 6),
      Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w600, color: activeColor)),
    ]);
  }

  Widget _statusBanner(AppLocalizations loc) {
    if (attendanceStatus == null) return const SizedBox.shrink();
    Color bg;
    Color fg;
    IconData icon;
    String label;
    switch (attendanceStatus) {
      case 'pending':
        bg = const Color(0xFFFEF3DC);
        fg = const Color(0xFF92600A);
        icon = Icons.hourglass_top;
        label = loc.faStatusPendingAttendance;
        break;
      case 'approved':
        bg = const Color(0xFFE8F5E2);
        fg = idaGreen;
        icon = Icons.check_circle;
        label = allocationStatus == 'approved'
            ? loc.faStatusApprovedAllocApproved
            : allocationStatus == 'pending'
                ? loc.faStatusApprovedAllocPending
                : loc.faStatusApprovedReady;
        break;
      case 'returned':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFC0392B);
        icon = Icons.error_outline;
        label =
            '${loc.faStatusReturned}${attendanceAdminNote != null ? ': $attendanceAdminNote' : ''}';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
        if (attendanceStatus == 'pending' && canApproveStageA) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed: decidingAttendance
                    ? null
                    : () => _decideAttendance('approve'),
                child: Text(loc.faApprove,
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red)),
                onPressed: decidingAttendance
                    ? null
                    : () => _decideAttendance('reject'),
                child: Text(loc.faReject),
              ),
            ),
          ]),
        ],
        if (attendanceStatus == 'approved') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon:
                  const Icon(Icons.work_outline, color: Colors.white, size: 18),
              label: Text(loc.faGoToWorkAllocation,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: idaDark,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          WorkAllocationScreen(attendanceDate: selectedDate))),
            ),
          ),
        ],
      ]),
    );
  }

  // Same reasoning as Dashboard's tile grid: one column on mobile
  // (unchanged behavior), reflowing to 2-3 columns on wider screens.
  // Each row card is wrapped in a fixed-width SizedBox before going
  // into the Wrap, since the card's Row contains an Expanded, which
  // needs a bounded width - a bare Wrap gives unbounded width and
  // would crash without this.
  Widget _presentWorkersGrid(BuildContext context, List<Widget> cards) {
    final columns = Responsive.gridColumns(context);
    if (columns == 1) return Column(children: cards);
    const spacing = 10.0;
    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: 0,
        children:
            cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
      );
    });
  }

  Widget _presentWorkersCard(AppLocalizations loc) {
    final selectedMale = selectedWorkerIds
        .where((id) =>
            workers.firstWhere((w) => w['id'] == id,
                orElse: () => {})['gender'] ==
            'M')
        .length;
    final selectedFemale = selectedWorkerIds
        .where((id) =>
            workers.firstWhere((w) => w['id'] == id,
                orElse: () => {})['gender'] ==
            'F')
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(loc.faSelectWorkers,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.6)),
          if (_canEditAttendance)
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _markViaFace,
                    icon: const Icon(Icons.face_retouching_natural,
                        size: 16, color: idaGreen),
                    label: Text(loc.faMarkViaFace,
                        style: const TextStyle(
                            color: idaGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0)),
                  ),
                  TextButton.icon(
                    onPressed: _showAddWorkerDialog,
                    icon: const Icon(Icons.person_add_alt_1,
                        size: 16, color: idaGreen),
                    label: Text(loc.faAddWorker,
                        style: const TextStyle(
                            color: idaGreen,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0)),
                  ),
                ],
              ),
            ),
        ]),
        if (!_canEditAttendance) ...[
          const SizedBox(height: 10),
          _submittedTotals(loc),
        ],
        if (permanentAutoSuggested && _canEditAttendance) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF5D48A)),
            ),
            child: const Row(children: [
              Icon(Icons.push_pin, size: 15, color: Color(0xFFB8860B)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Permanent workers are pre-selected below — uncheck anyone absent today, then submit.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF8A6D1F)),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        if (_canEditAttendance) ...[
          _genderFilterToggle(loc),
          const SizedBox(height: 10),
          _WorkerPicker(
            workers: workers,
            excludeIds: selectedWorkerIds,
            genderFilter: workerFilter,
            idaGreen: idaGreen,
            onAdd: _addWorker,
          ),
          if (selectedWorkerIds.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(loc.faTodayPresent,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                    letterSpacing: 0.6)),
            const SizedBox(height: 8),
            _presentWorkersGrid(
                context,
                (selectedWorkerIds.toList()
                      ..sort((a, b) {
                        final nameA = workers.firstWhere((w) => w['id'] == a,
                                orElse: () => {})['name'] ??
                            '';
                        final nameB = workers.firstWhere((w) => w['id'] == b,
                                orElse: () => {})['name'] ??
                            '';
                        return nameA
                            .toString()
                            .toLowerCase()
                            .compareTo(nameB.toString().toLowerCase());
                      }))
                    .map((id) {
                  final w = workers.firstWhere((w) => w['id'] == id,
                      orElse: () => {});
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E2),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Icon(w['gender'] == 'M' ? Icons.male : Icons.female,
                          color: idaGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(tl(context, w['name'] ?? ''),
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1)),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: presentWageCtrls[id],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            prefixText: '₹',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: Colors.red),
                        onPressed: () => _removeWorker(id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                  );
                }).toList()),
            const SizedBox(height: 4),
            _dayTotals(loc,
                title: loc.faSelectedSoFar,
                total: selectedWorkerIds.length,
                male: selectedMale,
                female: selectedFemale,
                permanent: _selectedPermanent,
                wage: _computedTotal),
          ],
        ] else
          Column(
            children: presentWorkers
                .map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(p['gender'] == 'M' ? Icons.male : Icons.female,
                              color: idaGreen, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(tl(context, p['name'] ?? ''),
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                                '₹${p['morning_amount'] ?? p['daily_wage']}',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1),
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        if (_canEditAttendance) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: savingPresent
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 18),
              label: Text(
                  savingPresent
                      ? loc.faSubmitting
                      : loc.faReviewSubmitAttendance,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: idaGreen,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: savingPresent ? null : _reviewAndSubmit,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _genderFilterToggle(AppLocalizations loc) {
    Widget chip(String label, String value) {
      final selected = workerFilter == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => workerFilter = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? idaGreen : const Color(0xFFF4F7F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Colors.grey.shade600)),
          ),
        ),
      );
    }

    return Row(children: [
      chip(loc.faAll, 'All'),
      const SizedBox(width: 6),
      chip(loc.faMaleFull, 'M'),
      const SizedBox(width: 6),
      chip(loc.faFemaleFull, 'F'),
      const SizedBox(width: 6),
      // Permanent workers already show up pre-selected on a fresh day
      // (server-suggested - see attendance.js's GET /day/:date), so this
      // chip is mainly for finding one to double-check or re-add after
      // an accidental uncheck, not the everyday path.
      chip('📌 Permanent', 'P'),
    ]);
  }
}

// ── Worker picker: search + gender filter, tap to add to Today Present ──
class _WorkerPicker extends StatefulWidget {
  final List workers;
  final Set<int> excludeIds; // already selected — not shown here
  final String genderFilter; // 'All' | 'M' | 'F'
  final Color idaGreen;
  final ValueChanged<int> onAdd;

  const _WorkerPicker(
      {required this.workers,
      required this.excludeIds,
      required this.genderFilter,
      required this.idaGreen,
      required this.onAdd});

  @override
  State<_WorkerPicker> createState() => _WorkerPickerState();
}

class _WorkerPickerState extends State<_WorkerPicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final filtered = widget.workers.where((w) {
      if (widget.excludeIds.contains(w['id'])) return false;
      final isPermanent = w['is_permanent'] == 1 || w['is_permanent'] == true;
      if (widget.genderFilter == 'P') {
        if (!isPermanent) return false;
      } else if (widget.genderFilter != 'All' &&
          w['gender'] != widget.genderFilter) {
        return false;
      }
      if (_query.isEmpty) return true;
      return (w['name'] ?? '')
          .toString()
          .toLowerCase()
          .contains(_query.toLowerCase());
    }).toList();

    return Column(children: [
      TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: loc.faSearchWorkers,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
        ),
      ),
      Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: filtered.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Text(loc.faNoWorkersMatch,
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey)))
            : ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final w = filtered[i];
                  final gender = w['gender'] as String?;
                  final isPermanent =
                      w['is_permanent'] == 1 || w['is_permanent'] == true;

                  return InkWell(
                    onTap: () => widget.onAdd(w['id']),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                              gender == 'M'
                                  ? Icons.male
                                  : gender == 'F'
                                      ? Icons.female
                                      : Icons.person_outline,
                              color: widget.idaGreen,
                              size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                    (isPermanent ? '📌 ' : '') +
                                        tl(context, w['name'] ?? ''),
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1),
                                gender == null
                                    ? Text(loc.faGenderNotSet,
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.orange),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1)
                                    : Text(
                                        '${gender == 'M' ? loc.faMaleFull : loc.faFemaleFull} · ₹${w['daily_wage']}/day',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.add_circle_outline,
                              color: widget.idaGreen, size: 22),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
