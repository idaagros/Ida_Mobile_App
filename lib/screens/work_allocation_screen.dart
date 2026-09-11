// lib/screens/work_allocation_screen.dart
//
// Stage B — Work Allocation. Only reachable once Stage A (attendance)
// is approved for the date. Assign every present worker to a Farm +
// Work Type: "Assign Single Task" starts a group with everyone
// pre-selected (the common case — one task for the whole day);
// "Assign Multi Task" starts an empty group so you can split workers
// across several Farm/Work Type groups one at a time. Both use the
// same underlying "task group" builder and both end up in the same
// save call — every present worker must land in exactly one group
// before saving. Each worker's rate is individually editable, with a
// "Break Attendance" action for anyone who left early (illness, etc.)
// — enter a reduced amount + a reason, no separate mechanism needed.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';

class WorkAllocationScreen extends StatefulWidget {
  final DateTime attendanceDate;
  const WorkAllocationScreen({super.key, required this.attendanceDate});

  @override
  State<WorkAllocationScreen> createState() => _WorkAllocationScreenState();
}

class _TaskGroup {
  int? farmId;
  int? workTypeId;
  final Map<int, TextEditingController> rateCtrls = {};
  final Map<int, TextEditingController> noteCtrls = {};
  final Set<int> workerIds = {};
  bool isTask1 =
      false; // true = Round 1 (rate defaults from morning amount, admin-gated); false = multi-task (blank, open to all)

  void dispose() {
    for (final c in rateCtrls.values) c.dispose();
    for (final c in noteCtrls.values) c.dispose();
  }
}

class _WorkAllocationScreenState extends State<WorkAllocationScreen> {
  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);
  static const baseUrl = 'https://excusable-moving-preorder.ngrok-free.dev/api';

  bool loading = true;
  bool saving = false;
  bool decidingAllocation = false;
  bool isAdmin = false;
  String? error;

  List farms = [];
  List workTypes = [];
  List<Map<String, dynamic>> presentWorkers = [];
  List<Map<String, dynamic>> savedAllocations = []; // once submitted/approved
  List<Map<String, dynamic>> perWorker =
      []; // fresh from server every load — used for review, not just post-save
  String? attendanceStatus;
  String? allocationStatus;
  String? allocationAdminNote;
  double? expectedTotalWage;

  final List<_TaskGroup> groups = [];
  // Stage B (work allocation) specific access - separate from isAdmin,
  // which only gates the admin approve/reject decision.
  bool canUpdateStageB = false;

  String get _dateStr => DateFormat('yyyy-MM-dd').format(widget.attendanceDate);

  @override
  void initState() {
    super.initState();
    ApiService.canUpdateSection('farm_attendance', 'allocation').then((v) {
      if (mounted) setState(() => canUpdateStageB = v);
    });
    _init();
  }

  @override
  void dispose() {
    for (final g in groups) g.dispose();
    super.dispose();
  }

  Future<Map<String, String>> get _headers async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Authorization': 'Bearer ${prefs.getString('token') ?? ''}',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  Future<void> _init() async {
    isAdmin = await ApiService.isAdmin();
    await _loadMasters();
    await _loadDay();
  }

  Future<void> _loadMasters() async {
    try {
      final h = await _headers;
      final results = await Future.wait([
        http.get(Uri.parse('$baseUrl/farms'), headers: h),
        http.get(Uri.parse('$baseUrl/work-types?applies_to=worker'),
            headers: h),
      ]);
      if (results[0].statusCode == 200) farms = jsonDecode(results[0].body);
      if (results[1].statusCode == 200) workTypes = jsonDecode(results[1].body);
    } catch (e) {
      debugPrint('Load masters error: $e');
    }
  }

  Future<void> _loadDay() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final h = await _headers;
      final res = await http.get(Uri.parse('$baseUrl/attendance/day/$_dateStr'),
          headers: h);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          attendanceStatus = data['attendance_status'];
          allocationStatus = data['allocation_status'];
          allocationAdminNote = data['allocation_admin_note'];
          expectedTotalWage = data['expected_total_wage'] != null
              ? double.tryParse(data['expected_total_wage'].toString())
              : null;
          presentWorkers =
              List<Map<String, dynamic>>.from(data['present_workers'] ?? []);
          presentWorkers.sort((a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase()));
          savedAllocations =
              List<Map<String, dynamic>>.from(data['allocations'] ?? []);
          // This is the fresh, always-available version — unlike a
          // save-response-only field would be, this comes from the
          // server every time the day loads, so an admin reviewing
          // later sees the same remarks the field user saw, not nothing.
          perWorker = List<Map<String, dynamic>>.from(data['per_worker'] ?? []);
        });
        if (_canBuild && groups.isEmpty) {
          await _loadDraft();
        }
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Set<int> get _allocatedWorkerIds => groups.expand((g) => g.workerIds).toSet();
  List<Map<String, dynamic>> get _unallocated => presentWorkers
      .where((p) => !_allocatedWorkerIds.contains(p['worker_id']))
      .toList();

  bool get _canBuild =>
      canUpdateStageB &&
      (allocationStatus == null || allocationStatus == 'returned');

  // ── Draft persistence ────────────────────────────────────────────
  //
  // groups only lives in memory until "Save All Allocations" is
  // pressed — before that, navigating away (even just to fix a
  // missing Work Type in a different screen) destroys this State
  // object and silently loses everything the person just built, with
  // no warning. That's a real data-loss bug, not acceptable for real
  // entered work.
  //
  // Fix: mirror `groups` to SharedPreferences on every change, keyed
  // by date, and restore it here on load if a draft exists and the
  // day is still in a buildable state (not yet submitted/approved).
  // Cleared once the final save actually reaches the server, since at
  // that point the server copy is the source of truth and an old
  // local draft would be actively wrong to keep resurrecting.
  String get _draftKey => 'wa_draft_$_dateStr';

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final data = groups
        .map((g) => {
              'farmId': g.farmId,
              'workTypeId': g.workTypeId,
              'isTask1': g.isTask1,
              'workers': g.workerIds
                  .map((id) => {
                        'workerId': id,
                        'rate': g.rateCtrls[id]?.text ?? '',
                        'note': g.noteCtrls[id]?.text ?? '',
                      })
                  .toList(),
            })
        .toList();
    await prefs.setString(_draftKey, jsonEncode(data));
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as List;
      final restored = <_TaskGroup>[];
      for (final item in data) {
        final g = _TaskGroup()
          ..farmId = item['farmId']
          ..workTypeId = item['workTypeId']
          ..isTask1 = item['isTask1'] ?? false;
        for (final w in (item['workers'] as List)) {
          final id = w['workerId'] as int;
          g.workerIds.add(id);
          g.rateCtrls[id] = TextEditingController(text: w['rate'] ?? '');
          g.noteCtrls[id] = TextEditingController(text: w['note'] ?? '');
        }
        restored.add(g);
      }
      if (mounted) setState(() => groups.addAll(restored));
    } catch (e) {
      debugPrint('Draft restore error: $e');
      await prefs.remove(_draftKey);
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  // A "single task" — pick Farm + Work Type, then choose WHICH
  // currently-unassigned present workers belong to it (not necessarily
  // everyone). Rates default to each worker's morning-allocated amount
  // (admin-gated to edit). Repeatable — each press creates a fresh
  // Task N covering whoever's still unassigned at that moment.
  void _addSingleTask() {
    final group = _TaskGroup()..isTask1 = true;
    _showGroupBuilder(group,
        isNew: true, prefillRate: true, restrictToWorkerId: null);
  }

  void _editGroup(_TaskGroup group) {
    final restrictTo =
        group.workerIds.length == 1 ? group.workerIds.first : null;
    _showGroupBuilder(group,
        isNew: false,
        prefillRate: group.isTask1,
        restrictToWorkerId: restrictTo);
  }

  // Multi Task remainder: one worker, one sheet — add as many
  // Farm + Work Type lines as needed (blank amounts, split however
  // their morning-allocated amount needs dividing), with "+" at the
  // bottom of the sheet, then a single Save for all of them at once.
  void _openMultiTaskSheet(int workerId) {
    final w = presentWorkers.firstWhere((p) => p['worker_id'] == workerId,
        orElse: () => {});
    final existingLines = _linesFor(workerId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MultiTaskWorkerSheet(
        workerId: workerId,
        workerName: w['name'] ?? '',
        workerGender: w['gender'],
        morningAmount: w['morning_amount'] != null
            ? double.tryParse(w['morning_amount'].toString())
            : null,
        farms: farms,
        workTypes: workTypes,
        idaGreen: idaGreen,
        existingGroups: existingLines,
        onSave: (newGroups) {
          setState(() {
            for (final g in existingLines) {
              groups.remove(g);
              g.dispose();
            }
            groups.addAll(newGroups);
          });
          _saveDraft();
        },
      ),
    );
  }

  void _showGroupBuilder(_TaskGroup group,
      {required bool isNew,
      required bool prefillRate,
      int? restrictToWorkerId,
      String? workerName}) {
    final candidateWorkers = restrictToWorkerId != null
        ? presentWorkers
            .where((p) => p['worker_id'] == restrictToWorkerId)
            .toList()
        : [
            ..._unallocated,
            ...presentWorkers
                .where((p) => group.workerIds.contains(p['worker_id'])),
          ]
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskGroupSheet(
        group: group,
        farms: farms,
        workTypes: workTypes,
        allPresent: presentWorkers,
        unallocatedExcludingThisGroup: candidateWorkers,
        idaGreen: idaGreen,
        prefillRate: prefillRate,
        isAdmin: isAdmin,
        title: workerName != null
            ? '${AppLocalizations.of(context)!.faWaAssignTaskTitlePrefix} — ${tl(context, workerName)}'
            : (restrictToWorkerId != null
                ? AppLocalizations.of(context)!.faWaAssignTask
                : AppLocalizations.of(context)!.faWaTask1FarmWorkersTitle),
        onSave: (finishedGroup) {
          setState(() {
            if (isNew) groups.add(finishedGroup);
          });
          _saveDraft();
        },
        onDelete: isNew
            ? null
            : () {
                setState(() {
                  groups.remove(group);
                  group.dispose();
                });
                _saveDraft();
              },
      ),
    );
  }

  Future<void> _saveAllocations() async {
    final loc = AppLocalizations.of(context)!;
    if (_unallocated.isNotEmpty) {
      setState(() => error =
          '${_unallocated.length} ${loc.faWaErrStillNeedTask} ${_unallocated.map((w) => tl(context, w['name'])).join(', ')}');
      return;
    }
    if (groups.isEmpty) {
      setState(() => error = loc.faWaErrAddTaskGroup);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final h = await _headers;
      final payload = groups
          .map((g) => {
                'farm_id': g.farmId,
                'work_type_id': g.workTypeId,
                'workers': g.workerIds
                    .map((id) => {
                          'worker_id': id,
                          'rate': double.tryParse(
                              g.rateCtrls[id]?.text.trim() ?? ''),
                          'notes': g.noteCtrls[id]?.text.trim(),
                        })
                    .toList(),
              })
          .toList();
      final res = await http.post(
        Uri.parse('$baseUrl/attendance/day/$_dateStr/allocation'),
        headers: {...h, 'Content-Type': 'application/json'},
        body: jsonEncode({'allocations': payload}),
      );
      if (res.statusCode == 200) {
        setState(() {
          for (final g in groups) g.dispose();
          groups.clear();
        });
        await _clearDraft();
        await _loadDay();
      } else {
        final data = jsonDecode(res.body);
        setState(() => error = data['error'] ?? loc.faWaErrSaveAllocation);
      }
    } catch (e) {
      setState(() => error = '${loc.faErrServer}: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _decideAllocation(String decision) async {
    final loc = AppLocalizations.of(context)!;
    String? note;
    if (decision == 'reject') {
      note = await _promptForNote(loc.faWaRejectTitle, loc.faWaRejectHint);
      if (note == null || note.trim().isEmpty) return;
    }
    setState(() => decidingAllocation = true);
    try {
      final h = await _headers;
      final res = await http.patch(
        Uri.parse('$baseUrl/attendance/day/$_dateStr/allocation-decision'),
        headers: {...h, 'Content-Type': 'application/json'},
        body:
            jsonEncode({'decision': decision, if (note != null) 'note': note}),
      );
      if (res.statusCode == 200) {
        await _loadDay();
      } else {
        final data = jsonDecode(res.body);
        setState(() => error = data['error'] ?? loc.faErrRecordDecision);
      }
    } catch (e) {
      setState(() => error = '${loc.faErrServer}: $e');
    } finally {
      if (mounted) setState(() => decidingAllocation = false);
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
            '${loc.faWaTitle} · ${DateFormat('dd MMM').format(widget.attendanceDate)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: idaGreen))
          : attendanceStatus != 'approved'
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(loc.faWaMustApproveFirst,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 14)),
                  ),
                )
              : RefreshIndicator(
                  color: idaGreen,
                  onRefresh: _loadDay,
                  child: Responsive.constrainedContent(
                      context,
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          _statusBanner(loc),
                          const SizedBox(height: 16),
                          if (_canBuild) ..._buildSection(loc),
                          if (!_canBuild) ...[
                            _readOnlyAllocations(loc),
                            _decisionButtons(loc),
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

  Widget _statusBanner(AppLocalizations loc) {
    if (allocationStatus == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFE8F5E2),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.info_outline, color: idaGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
                  '${presentWorkers.length} ${loc.faWaPresentToAllocate}${expectedTotalWage != null ? ' ${loc.faWaExpectedTotalSuffix}: ₹${expectedTotalWage!.toStringAsFixed(2)}' : ''}',
                  style: const TextStyle(
                      color: idaDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5))),
        ]),
      );
    }
    Color bg;
    Color fg;
    IconData icon;
    String label;
    switch (allocationStatus) {
      case 'pending':
        bg = const Color(0xFFFEF3DC);
        fg = const Color(0xFF92600A);
        icon = Icons.hourglass_top;
        label = loc.faWaStatusPending;
        break;
      case 'approved':
        bg = const Color(0xFFE8F5E2);
        fg = idaGreen;
        icon = Icons.check_circle;
        label = loc.faWaStatusApproved;
        break;
      case 'returned':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFC0392B);
        icon = Icons.error_outline;
        label =
            '${loc.faStatusReturned}${allocationAdminNote != null ? ': $allocationAdminNote' : ''}';
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
      ]),
    );
  }

  // Approve/Reject — deliberately rendered AFTER the remarks and
  // allocation list below, not at the top, so an admin scrolls through
  // what actually happened (same / excess / less / Break Attendance
  // reasons) before the buttons are even in view. Nothing to approve
  // blind against.
  Widget _decisionButtons(AppLocalizations loc) {
    if (allocationStatus != 'pending' || !isAdmin)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: idaGreen,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed:
                decidingAllocation ? null : () => _decideAllocation('approve'),
            child: Text(loc.faApprove,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed:
                decidingAllocation ? null : () => _decideAllocation('reject'),
            child: Text(loc.faReject,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  double get _liveTotal {
    double total = 0;
    for (final g in groups) {
      for (final id in g.workerIds) {
        total += double.tryParse(g.rateCtrls[id]?.text.trim() ?? '') ?? 0;
      }
    }
    return total;
  }

  List<Widget> _buildSection(AppLocalizations loc) {
    final hasBatchTasks = _batchTasks.isNotEmpty;
    return [
      // ── First single task, covering some or all present workers ──
      if (!hasBatchTasks)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.groups_outlined,
                color: Colors.white, size: 18),
            label: Text(loc.faWaAssignTaskSelectWorkers,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: idaGreen,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _addSingleTask,
          ),
        ),

      if (hasBatchTasks) ...[
        Row(children: [
          Text(loc.faWaTasks,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.6)),
          const Spacer(),
          Text(
              '${_allocatedWorkerIds.length}/${presentWorkers.length} ${loc.faWaAllocatedSuffix}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _unallocated.isEmpty ? idaGreen : Colors.orange)),
        ]),
        const SizedBox(height: 10),
        ..._batchTasks.asMap().entries.map((entry) {
          final taskNumber = entry.key + 1;
          final group = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${loc.faWaTaskNumber} $taskNumber',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF9CA3AF),
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              _groupCard(group, loc),
              if (_nonBatchTaskWorkers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _editGroup(group),
                      icon: const Icon(Icons.add, size: 16, color: idaGreen),
                      label: Text('${loc.faWaAddMoreWorkersToTask} $taskNumber',
                          style: const TextStyle(
                              color: idaGreen,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
                  ),
                ),
            ]),
          );
        }),

        // ── Start another single task from whoever's still fully
        // unassigned — same picker as the first task, different
        // Farm/Work Type, repeatable as many times as needed. ───────
        if (_unallocated.isNotEmpty) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon:
                  const Icon(Icons.add_box_outlined, size: 18, color: idaGreen),
              label: Text(loc.faWaAddNewSingleTask,
                  style: const TextStyle(
                      color: idaGreen, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: idaGreen,
                  side: const BorderSide(color: idaGreen),
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _addSingleTask,
            ),
          ),
        ],

        // ── Multi Task: whoever's left after every single task above.
        // Each worker can have MORE THAN ONE task line, splitting
        // their morning amount across farms/work types — the "+"
        // stays available even after their first task, for exactly
        // that. ─────────────────────────────────────────────────────
        if (_nonBatchTaskWorkers.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(loc.faWaMultiTaskRemaining,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(loc.faWaMultiTaskHint,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 10),
          _tileGrid(
              context,
              _nonBatchTaskWorkers
                  .map((w) => _multiTaskWorkerCard(w, loc))
                  .toList()),
        ],
      ],

      if (hasBatchTasks) ...[
        const SizedBox(height: 16),
        _totalComparisonBanner(loc),
      ],

      if (hasBatchTasks) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 18),
            label: Text(saving ? loc.faWaSaving : loc.faWaSaveAllAllocations,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: idaDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed:
                (saving || _unallocated.isNotEmpty) ? null : _saveAllocations,
          ),
        ),
      ],
    ];
  }

  // Every "single task" group (multi-worker, shared Farm/Work Type,
  // rate defaults from morning amount, admin-gated edit) — Task 1,
  // Task 2, etc. Distinct from the per-worker Multi Task lines below,
  // which are single-worker, blank-rate, open to everyone.
  List<_TaskGroup> get _batchTasks => groups.where((g) => g.isTask1).toList();

  // Everyone present, minus whoever's covered by ANY single task above.
  List<Map<String, dynamic>> get _nonBatchTaskWorkers {
    final coveredIds = _batchTasks.expand((g) => g.workerIds).toSet();
    return presentWorkers
        .where((p) => !coveredIds.contains(p['worker_id']))
        .toList();
  }

  // A worker's task lines beyond Task 1 — could be zero (not yet
  // assigned), one, or several (split across farms/work types).
  List<_TaskGroup> _linesFor(int workerId) =>
      groups.skip(1).where((g) => g.workerIds.contains(workerId)).toList();

  // Same reasoning as Dashboard's and Farm Attendance's grids: one
  // column on mobile (unchanged), reflowing to 2-3 columns on wider
  // screens. Cards are wrapped in a fixed-width SizedBox before going
  // into the Wrap, since _multiTaskWorkerCard uses Expanded
  // internally, which needs a bounded width - a bare Wrap gives
  // unbounded width and would crash without this. runSpacing is 0
  // because each card already carries its own bottom margin.
  Widget _tileGrid(BuildContext context, List<Widget> cards) {
    final columns = Responsive.gridColumns(context);
    if (columns == 1) return Column(children: cards);
    const spacing = 12.0;
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

  Widget _multiTaskWorkerCard(Map<String, dynamic> w, AppLocalizations loc) {
    final workerId = w['worker_id'] as int;
    final lines = _linesFor(workerId);
    final morning = w['morning_amount'] != null
        ? double.tryParse(w['morning_amount'].toString())
        : null;
    final subtotal = lines.fold(
        0.0,
        (s, g) =>
            s +
            (double.tryParse(g.rateCtrls[workerId]?.text.trim() ?? '') ?? 0));
    final matches = morning == null ? null : (subtotal - morning).abs() < 0.01;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w['gender'] == 'M' ? Icons.male : Icons.female,
              color: idaGreen, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(tl(context, w['name'] ?? ''),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1)),
          if (morning != null)
            Flexible(
              child: Text(
                  '₹${morning.toStringAsFixed(2)} ${loc.faWaThisMorningSuffix}',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
        ]),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...lines.map((g) {
            final farmName = tl(
                context,
                farms.firstWhere((f) => f['id'] == g.farmId,
                        orElse: () => {})['name'] ??
                    '—');
            final workTypeNameRaw = workTypes.firstWhere(
                (wt) => wt['id'] == g.workTypeId,
                orElse: () => {})['name'];
            final workTypeName =
                workTypeNameRaw != null ? tl(context, workTypeNameRaw) : null;
            final amount =
                double.tryParse(g.rateCtrls[workerId]?.text.trim() ?? '') ?? 0;
            return Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '$farmName${workTypeName != null ? ' · $workTypeName' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1)),
                Text('₹${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: idaDark)),
              ]),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Row(children: [
              Text('${loc.faWaSubtotal}: ₹${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: matches == false
                          ? Colors.orange.shade800
                          : idaGreen)),
              if (matches == false)
                const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.error_outline,
                        size: 13, color: Colors.orange)),
              if (matches == true)
                const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_circle, size: 13, color: idaGreen)),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(lines.isEmpty ? Icons.add : Icons.edit_outlined,
                size: 15, color: idaGreen),
            label: Text(lines.isEmpty ? loc.faWaAssignTask : loc.faWaEditTasks,
                style: const TextStyle(
                    color: idaGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
                foregroundColor: idaGreen,
                side: const BorderSide(color: idaGreen),
                padding: const EdgeInsets.symmetric(vertical: 8)),
            onPressed: () => _openMultiTaskSheet(workerId),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_off_outlined,
                size: 15, color: Color(0xFFC0392B)),
            label: Text(loc.faWaDidNotWork,
                style: const TextStyle(
                    color: Color(0xFFC0392B),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC0392B),
                side: const BorderSide(color: Color(0xFFC0392B)),
                padding: const EdgeInsets.symmetric(vertical: 8)),
            onPressed: () => _showDidNotWorkDialog(workerId, w['name'] ?? ''),
          ),
        ),
      ]),
    );
  }

  void _showDidNotWorkDialog(int workerId, String workerName) {
    final loc = AppLocalizations.of(context)!;
    final reasonCtrl = TextEditingController();
    bool submitting = false;
    String? validationError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('${loc.faWaDidNotWork} — ${tl(context, workerName)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.faWaDidNotWorkHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reasonCtrl,
                  autofocus: true,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: loc.faWaReasonLabel,
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 10),
                  Text(validationError!,
                      style: const TextStyle(
                          color: Color(0xFFC0392B), fontSize: 12)),
                ],
              ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC0392B)),
              onPressed: submitting
                  ? null
                  : () async {
                      if (reasonCtrl.text.trim().isEmpty) {
                        setDialogState(
                            () => validationError = loc.faWaReasonLabel);
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        validationError = null;
                      });
                      // Wrapped end to end - same reasoning as Add Missed
                      // Worker's fix: an unexpected failure here must never
                      // leave the button stuck spinning forever.
                      try {
                        final h = await _headers;
                        final res = await http.post(
                          Uri.parse(
                              '$baseUrl/attendance/day/$_dateStr/did-not-work'),
                          headers: {...h, 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'worker_id': workerId,
                            'reason': reasonCtrl.text.trim()
                          }),
                        );
                        if (res.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          // Clean up any local draft groups this worker was
                          // part of, so the UI doesn't still show them
                          // half-assigned to a task after they've been removed
                          // from the day entirely.
                          setState(() {
                            for (final g in groups) {
                              if (g.workerIds.remove(workerId)) {
                                g.rateCtrls.remove(workerId)?.dispose();
                                g.noteCtrls.remove(workerId)?.dispose();
                              }
                            }
                            groups.removeWhere((g) => g.workerIds.isEmpty);
                          });
                          await _saveDraft();
                          await _loadDay();
                        } else {
                          final data = jsonDecode(res.body);
                          setDialogState(() {
                            submitting = false;
                            validationError =
                                data['error'] ?? loc.faWaErrAddTaskGroup;
                          });
                        }
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          validationError = 'Could not reach server: $e';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.faWaDidNotWork,
                      style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMissedWorkerDialog() async {
    final loc = AppLocalizations.of(context)!;
    final h = await _headers;
    final res = await http.get(Uri.parse('$baseUrl/farm-workers'), headers: h);
    if (res.statusCode != 200) return;
    final allWorkers = List<Map<String, dynamic>>.from(jsonDecode(res.body));
    final presentIds = presentWorkers.map((p) => p['worker_id']).toSet();
    // Only workers NOT already on today's present list - by definition,
    // this dialog exists specifically for someone missing from it.
    final available = allWorkers
        .where((w) => !presentIds.contains(w['id']))
        .toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    if (available.isEmpty || !mounted) return;

    int? selectedWorkerId = available.first['id'];
    int? selectedFarmId = farms.isNotEmpty ? farms.first['id'] : null;
    int? selectedWorkTypeId;
    // Defaults to the selected worker's daily_wage, same fallback the
    // existing Assign Task sheet already uses for a worker with no
    // morning_amount - matching the established pattern rather than
    // leaving this blank, which is what silently broke submission
    // before (an empty rate parsed to null, and the button did
    // nothing with zero feedback).
    final rateCtrl = TextEditingController(
        text: available.first['daily_wage']?.toString() ?? '');
    bool rateManuallyEdited = false;
    final reasonCtrl = TextEditingController();
    bool submitting = false;
    String? validationError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(loc.faWaAddMissedWorker,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(loc.faWaAddMissedWorkerHint,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    value: selectedWorkerId,
                    decoration: InputDecoration(
                        labelText: loc.faWaWorkerLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: available
                        .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                            value: w['id'],
                            child: Text(tl(context, w['name'] ?? ''))))
                        .toList(),
                    onChanged: (v) => setDialogState(() {
                      selectedWorkerId = v;
                      // Update the default rate to match the newly-selected
                      // worker - but only if the field hasn't been manually
                      // touched, per "defaulted... unless changed".
                      if (!rateManuallyEdited) {
                        final w = available.firstWhere((w) => w['id'] == v,
                            orElse: () => {});
                        rateCtrl.text = w['daily_wage']?.toString() ?? '';
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedFarmId,
                    decoration: InputDecoration(
                        labelText: loc.faWaFarmLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: farms
                        .map<DropdownMenuItem<int>>((f) => DropdownMenuItem(
                            value: f['id'],
                            child: Text(tl(context, f['name'] ?? ''))))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedFarmId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedWorkTypeId,
                    decoration: InputDecoration(
                        labelText: loc.faWaWorkTypeOptionalLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    items: workTypes
                        .map<DropdownMenuItem<int>>((wt) => DropdownMenuItem(
                            value: wt['id'],
                            child: Text(tl(context, wt['name'] ?? ''))))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedWorkTypeId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => rateManuallyEdited = true,
                    decoration: InputDecoration(
                        labelText: loc.faWaRateLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                        labelText: loc.faWaReasonLabel,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 10),
                    Text(validationError!,
                        style: const TextStyle(
                            color: Color(0xFFC0392B), fontSize: 12)),
                  ],
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
              onPressed: submitting
                  ? null
                  : () async {
                      final rate = double.tryParse(rateCtrl.text.trim());
                      // Visible feedback on every validation failure - the
                      // previous version returned silently here, which is
                      // exactly what made a missing rate look like the button
                      // simply did nothing.
                      if (selectedWorkerId == null) {
                        setDialogState(
                            () => validationError = loc.faWaWorkerLabel);
                        return;
                      }
                      if (selectedFarmId == null) {
                        setDialogState(
                            () => validationError = loc.faWaFarmLabel);
                        return;
                      }
                      if (rate == null) {
                        setDialogState(
                            () => validationError = loc.faWaRateLabel);
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        setDialogState(
                            () => validationError = loc.faWaReasonLabel);
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        validationError = null;
                      });
                      // Wrapped end to end - a network hiccup, timeout, or any
                      // other unexpected failure here must never leave the
                      // button stuck showing its spinner forever with
                      // submitting stuck true and no way to retry or see why.
                      try {
                        final h2 = await _headers;
                        final res2 = await http.post(
                          Uri.parse(
                              '$baseUrl/attendance/day/$_dateStr/retroactive-add'),
                          headers: {...h2, 'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'worker_id': selectedWorkerId,
                            'farm_id': selectedFarmId,
                            'work_type_id': selectedWorkTypeId,
                            'rate': rate,
                            'reason': reasonCtrl.text.trim(),
                          }),
                        );
                        if (res2.statusCode == 200) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _loadDay();
                        } else {
                          final data = jsonDecode(res2.body);
                          setDialogState(() {
                            submitting = false;
                            validationError =
                                data['error'] ?? loc.faWaErrAddTaskGroup;
                          });
                        }
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          validationError = 'Could not reach server: $e';
                        });
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(loc.save, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(_TaskGroup g, AppLocalizations loc) {
    final farmName = tl(
        context,
        farms.firstWhere((f) => f['id'] == g.farmId,
                orElse: () => {})['name'] ??
            '—');
    final workTypeNameRaw = workTypes.firstWhere((w) => w['id'] == g.workTypeId,
        orElse: () => {})['name'];
    final workTypeName =
        workTypeNameRaw != null ? tl(context, workTypeNameRaw) : null;
    final total = g.workerIds.fold(0.0,
        (s, id) => s + (double.tryParse(g.rateCtrls[id]?.text ?? '') ?? 0));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                '$farmName${workTypeName != null ? ' · $workTypeName' : ''}',
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: idaGreen)),
          ),
          Text('₹${total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: idaDark)),
          IconButton(
              icon:
                  const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
              onPressed: () => _editGroup(g),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints()),
        ]),
        const SizedBox(height: 6),
        Text(
            (g.workerIds.toList()
                  ..sort((a, b) => (presentWorkers.firstWhere(
                              (p) => p['worker_id'] == a,
                              orElse: () => {})['name'] ??
                          '')
                      .toString()
                      .toLowerCase()
                      .compareTo((presentWorkers.firstWhere(
                                  (p) => p['worker_id'] == b,
                                  orElse: () => {})['name'] ??
                              '')
                          .toString()
                          .toLowerCase())))
                .map((id) => tl(
                    context, presentWorkers.firstWhere((p) => p['worker_id'] == id, orElse: () => {})['name'] ?? ''))
                .join(', '),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ]),
    );
  }

  Widget _totalComparisonBanner(AppLocalizations loc) {
    final total = _liveTotal;
    final expected = expectedTotalWage;
    final diff = expected != null ? total - expected : null;
    final matches = diff == null ? null : diff.abs() < 0.01;
    String label;
    if (expected == null) {
      label = '${loc.faWaAllocatedSoFarPrefix}: ₹${total.toStringAsFixed(2)}';
    } else if (matches == true) {
      label =
          '${loc.faWaAllocatedSoFarPrefix}: ₹${total.toStringAsFixed(2)} — ${loc.faWaMatchesExpectedSuffix} ₹${expected.toStringAsFixed(2)} ${loc.faWaExpectedSuffix}';
    } else if (diff! > 0) {
      label =
          '${loc.faWaAllocatedSoFarPrefix}: ₹${total.toStringAsFixed(2)} — ₹${diff.toStringAsFixed(2)} ${loc.faWaExcessOverSuffix} ₹${expected.toStringAsFixed(2)} ${loc.faWaExpectedSuffix}';
    } else {
      label =
          '${loc.faWaAllocatedSoFarPrefix}: ₹${total.toStringAsFixed(2)} — ₹${diff.abs().toStringAsFixed(2)} ${loc.faWaLessThanSuffix} ₹${expected.toStringAsFixed(2)} ${loc.faWaExpectedSuffix}';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: matches == false
            ? const Color(0xFFFEF3DC)
            : const Color(0xFFE8F5E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: matches == false ? const Color(0xFF92600A) : idaDark),
          ),
        ),
        if (matches == true)
          const Icon(Icons.check_circle, color: idaGreen, size: 18),
        if (matches == false)
          const Icon(Icons.error_outline, color: Color(0xFF92600A), size: 18),
      ]),
    );
  }

  Widget _readOnlyAllocations(AppLocalizations loc) {
    final groupsByTask = <String, List<Map<String, dynamic>>>{};
    for (final a in savedAllocations) {
      final key = '${a['farm_name'] ?? ''}·${a['work_type_name'] ?? '—'}';
      groupsByTask.putIfAbsent(key, () => []).add(a);
    }
    for (final list in groupsByTask.values) {
      list.sort((a, b) => (a['worker_name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['worker_name'] ?? '').toString().toLowerCase()));
    }
    final sortedPerWorker = List<Map<String, dynamic>>.from(perWorker)
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    final total = savedAllocations.fold(
        0.0, (s, a) => s + (double.tryParse(a['total_wage'].toString()) ?? 0));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (perWorker.isNotEmpty) ...[
        Text(loc.faWaRemarksHeader,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.6)),
        const SizedBox(height: 10),
        _tileGrid(
            context, sortedPerWorker.map((pw) => _remarkRow(pw, loc)).toList()),
        const SizedBox(height: 18),
      ],
      Row(children: [
        Text(loc.faWaAllocationsHeader,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.6)),
        const Spacer(),
        Text('${loc.faWaTotalPrefix}: ₹${total.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: idaGreen)),
      ]),
      const SizedBox(height: 10),
      ...groupsByTask.entries.map((entry) {
        final parts = entry.key.split('·');
        final farmName = tl(context, parts[0]);
        final workTypeName =
            parts.length > 1 && parts[1] != '—' ? tl(context, parts[1]) : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E7D8))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                  '$farmName${workTypeName != null ? ' · $workTypeName' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: idaGreen)),
            ),
            const Divider(height: 1),
            ...entry.value.map((a) {
              final canMarkDidNotWork = allocationStatus == 'pending' ||
                  (allocationStatus == 'approved' && isAdmin);
              return ListTile(
                dense: true,
                title: Text(tl(context, a['worker_name'] ?? ''),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: a['notes'] != null && a['notes'].toString().isNotEmpty
                    ? Text(a['notes'],
                        style:
                            const TextStyle(fontSize: 11, color: Colors.orange))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('₹${a['total_wage']}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: idaGreen)),
                  if (canMarkDidNotWork)
                    IconButton(
                      icon: const Icon(Icons.person_off_outlined,
                          size: 18, color: Color(0xFFC0392B)),
                      tooltip: loc.faWaDidNotWork,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _showDidNotWorkDialog(
                          a['worker_id'], a['worker_name'] ?? ''),
                    )
                  else
                    const SizedBox(width: 4),
                ]),
              );
            }),
          ]),
        );
      }),
      if (isAdmin) ...[
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.person_add_alt_1, size: 16, color: idaGreen),
            label: Text(loc.faWaAddMissedWorker,
                style: const TextStyle(
                    color: idaGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            style: OutlinedButton.styleFrom(
                foregroundColor: idaGreen,
                side: const BorderSide(color: idaGreen),
                padding: const EdgeInsets.symmetric(vertical: 10)),
            onPressed: _showAddMissedWorkerDialog,
          ),
        ),
      ],
    ]);
  }

  Widget _remarkRow(Map<String, dynamic> pw, AppLocalizations loc) {
    final remark = pw['remark'] as String?;
    final diff =
        pw['diff'] != null ? double.tryParse(pw['diff'].toString()) : null;
    final breakNotes = List<String>.from(pw['break_notes'] ?? []);

    Color bg;
    Color fg;
    String label;
    switch (remark) {
      case 'same':
        bg = const Color(0xFFE8F5E2);
        fg = idaGreen;
        label = loc.faWaRemarkSame;
        break;
      case 'excess':
        bg = const Color(0xFFFEF3DC);
        fg = const Color(0xFF92600A);
        label = '${loc.faWaRemarkExcess} ₹${diff?.toStringAsFixed(2)}';
        break;
      case 'less':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFC0392B);
        label = '${loc.faWaRemarkLess} ₹${diff?.abs().toStringAsFixed(2)}';
        break;
      case 'unallocated':
        bg = const Color(0xFFFDE8E8);
        fg = const Color(0xFFC0392B);
        label = loc.faWaRemarkUnallocated;
        break;
      default:
        bg = const Color(0xFFF4F7F2);
        fg = Colors.grey.shade600;
        label = loc.faWaRemarkNoMorning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(tl(context, pw['name'] ?? ''),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1)),
          Flexible(
            child: Text(
              pw['morning_amount'] != null
                  ? '₹${pw['morning_amount']} → ₹${pw['allocated_total'] ?? '—'}'
                  : '₹${pw['allocated_total'] ?? '—'}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ),
        if (breakNotes.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...breakNotes.map((n) => Row(children: [
                const Icon(Icons.timer_off_outlined,
                    size: 13, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                    child: Text('${loc.faWaBreakAttendanceNotePrefix}: $n',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            fontStyle: FontStyle.italic))),
              ])),
        ],
      ]),
    );
  }
}

// ── Bottom sheet: build/edit one task group ─────────────────────────
// ── One sheet per worker for Multi Task: add as many Farm + Work Type
// lines as needed, "+" at the bottom, one Save for all of them. ─────
class _SheetLine {
  int? farmId;
  int? workTypeId;
  final TextEditingController rateCtrl;
  final TextEditingController noteCtrl;
  _SheetLine({this.farmId, this.workTypeId, String? rate, String? note})
      : rateCtrl = TextEditingController(text: rate ?? ''),
        noteCtrl = TextEditingController(text: note ?? '');

  void dispose() {
    rateCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _MultiTaskWorkerSheet extends StatefulWidget {
  final int workerId;
  final String workerName;
  final String? workerGender;
  final double? morningAmount;
  final List farms;
  final List workTypes;
  final Color idaGreen;
  final List<_TaskGroup> existingGroups;
  final ValueChanged<List<_TaskGroup>> onSave;

  const _MultiTaskWorkerSheet({
    required this.workerId,
    required this.workerName,
    required this.workerGender,
    required this.morningAmount,
    required this.farms,
    required this.workTypes,
    required this.idaGreen,
    required this.existingGroups,
    required this.onSave,
  });

  @override
  State<_MultiTaskWorkerSheet> createState() => _MultiTaskWorkerSheetState();
}

class _MultiTaskWorkerSheetState extends State<_MultiTaskWorkerSheet> {
  static const idaDark = Color(0xFF1E4012);
  late List<_SheetLine> lines;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    lines = widget.existingGroups
        .map((g) => _SheetLine(
              farmId: g.farmId,
              workTypeId: g.workTypeId,
              rate: g.rateCtrls[widget.workerId]?.text,
              note: g.noteCtrls[widget.workerId]?.text,
            ))
        .toList();
    if (lines.isEmpty) lines.add(_SheetLine());
  }

  @override
  void dispose() {
    for (final l in lines) l.dispose();
    super.dispose();
  }

  void _addLine() => setState(() => lines.add(_SheetLine()));

  void _removeLine(_SheetLine line) {
    setState(() {
      lines.remove(line);
      line.dispose();
      if (lines.isEmpty) lines.add(_SheetLine());
    });
  }

  Future<void> _breakAttendance(_SheetLine line) async {
    final tempRate = TextEditingController(text: line.rateCtrl.text);
    final tempNote = TextEditingController(text: line.noteCtrl.text);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              '${loc.faWaBreakAttendanceTitlePrefix} — ${tl(context, widget.workerName)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(loc.faWaBreakHint,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: tempRate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: loc.faWaReducedAmountLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tempNote,
              maxLines: 2,
              decoration: InputDecoration(
                  hintText: loc.faWaReasonHint,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.faWaApply,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      setState(() {
        line.rateCtrl.text = tempRate.text;
        line.noteCtrl.text = tempNote.text;
      });
    }
  }

  double get _subtotal => lines.fold(
      0.0, (s, l) => s + (double.tryParse(l.rateCtrl.text.trim()) ?? 0));

  void _save() {
    final loc = AppLocalizations.of(context)!;
    final validLines = lines.where((l) => l.farmId != null).toList();
    if (validLines.isEmpty) {
      setState(() => _saveError = loc.faWaErrAddFarm);
      return;
    }
    for (final l in validLines) {
      if (double.tryParse(l.rateCtrl.text.trim()) == null) {
        setState(() => _saveError = loc.faWaErrAmountEveryLine);
        return;
      }
    }
    final newGroups = validLines.map((l) {
      final g = _TaskGroup()..isTask1 = false;
      g.farmId = l.farmId;
      g.workTypeId = l.workTypeId;
      g.workerIds.add(widget.workerId);
      g.rateCtrls[widget.workerId] =
          TextEditingController(text: l.rateCtrl.text);
      g.noteCtrls[widget.workerId] =
          TextEditingController(text: l.noteCtrl.text);
      return g;
    }).toList();
    widget.onSave(newGroups);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Row(children: [
                  Icon(widget.workerGender == 'M' ? Icons.male : Icons.female,
                      color: idaDark, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${loc.faWaAssignTaskTitlePrefix} — ${tl(context, widget.workerName)}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: idaDark),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (widget.morningAmount != null)
                    Text(
                        '₹${widget.morningAmount!.toStringAsFixed(2)} ${loc.faWaThisMorningSuffix}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                Text(loc.faWaWorkTypeAddAnotherHeader,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.6)),
                const SizedBox(height: 10),
                ...lines.map((line) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF4F7F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE0E7D8))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: widget.farms
                                          .any((f) => f['id'] == line.farmId)
                                      ? line.farmId
                                      : null,
                                  decoration: InputDecoration(
                                      labelText: loc.faWaFarmDropdownLabel,
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                  items: widget.farms
                                      .map<DropdownMenuItem<int>>((f) =>
                                          DropdownMenuItem(
                                              value: f['id'],
                                              child: Text(
                                                  tl(context, f['name']),
                                                  style: const TextStyle(
                                                      fontSize: 13))))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => line.farmId = v),
                                ),
                              ),
                              IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 18, color: Colors.red),
                                  onPressed: () => _removeLine(line),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints()),
                            ]),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: widget.workTypes
                                      .any((w) => w['id'] == line.workTypeId)
                                  ? line.workTypeId
                                  : null,
                              decoration: InputDecoration(
                                  labelText: loc.faWaWorkTypeDropdownLabel,
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              items: widget.workTypes
                                  .map<DropdownMenuItem<int>>((w) =>
                                      DropdownMenuItem(
                                          value: w['id'],
                                          child: Text(tl(context, w['name']),
                                              style: const TextStyle(
                                                  fontSize: 13))))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => line.workTypeId = v),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: line.rateCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                      labelText: loc.faWaRateLabel,
                                      hintText: loc.faWaEnterAmountHint,
                                      hintStyle: const TextStyle(
                                          fontSize: 12, color: Colors.orange),
                                      isDense: true,
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () => _breakAttendance(line),
                                icon: const Icon(Icons.timer_off_outlined,
                                    size: 15, color: Colors.orange),
                                label: Text(loc.faWaBreakShort,
                                    style: const TextStyle(
                                        fontSize: 11.5, color: Colors.orange)),
                                style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6)),
                              ),
                            ]),
                            if (line.noteCtrl.text.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                  '${loc.faWaNotePrefix}: ${line.noteCtrl.text}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                      fontStyle: FontStyle.italic)),
                            ],
                          ]),
                    )),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.add, size: 18, color: widget.idaGreen),
                    label: Text(loc.faWaAddAnotherWorkType,
                        style: TextStyle(
                            color: widget.idaGreen,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: widget.idaGreen,
                        side: BorderSide(color: widget.idaGreen),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _addLine,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Expanded(
                        child: Text(loc.faWaSubtotal,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: idaDark))),
                    Text(
                        '₹${_subtotal.toStringAsFixed(2)}${widget.morningAmount != null ? ' / ₹${widget.morningAmount!.toStringAsFixed(2)}' : ''}',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: idaDark)),
                  ]),
                ),
                const SizedBox(height: 14),
                if (_saveError != null) ...[
                  Text(_saveError!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12.5)),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: widget.idaGreen,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: _save,
                    child: Text(loc.faWaSaveAllAllocations,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _TaskGroupSheet extends StatefulWidget {
  final _TaskGroup group;
  final List farms;
  final List workTypes;
  final List<Map<String, dynamic>> allPresent;
  final List<Map<String, dynamic>> unallocatedExcludingThisGroup;
  final Color idaGreen;
  final bool prefillRate;
  final bool isAdmin;
  final String title;
  final ValueChanged<_TaskGroup> onSave;
  final VoidCallback? onDelete;

  const _TaskGroupSheet({
    required this.group,
    required this.farms,
    required this.workTypes,
    required this.allPresent,
    required this.unallocatedExcludingThisGroup,
    required this.idaGreen,
    required this.isAdmin,
    required this.onSave,
    this.prefillRate = true,
    this.title = 'Task Group',
    this.onDelete,
  });

  @override
  State<_TaskGroupSheet> createState() => _TaskGroupSheetState();
}

class _TaskGroupSheetState extends State<_TaskGroupSheet> {
  static const idaDark = Color(0xFF1E4012);
  int? farmId;
  int? workTypeId;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    farmId = widget.group.farmId;
    workTypeId = widget.group.workTypeId;
  }

  void _toggleWorker(int id) {
    setState(() {
      if (widget.group.workerIds.contains(id)) {
        widget.group.workerIds.remove(id);
        widget.group.rateCtrls.remove(id)?.dispose();
        widget.group.noteCtrls.remove(id)?.dispose();
      } else {
        widget.group.workerIds.add(id);
        final w = widget.allPresent
            .firstWhere((p) => p['worker_id'] == id, orElse: () => {});
        widget.group.rateCtrls[id] = TextEditingController(
            text: widget.prefillRate
                ? (w['morning_amount']?.toString() ??
                    w['daily_wage']?.toString() ??
                    '')
                : '');
        widget.group.noteCtrls[id] = TextEditingController();
      }
    });
  }

  Future<void> _breakAttendance(int workerId, String name) async {
    final rateCtrl = widget.group.rateCtrls[workerId]!;
    final noteCtrl = widget.group.noteCtrls[workerId]!;
    final tempRate = TextEditingController(text: rateCtrl.text);
    final tempNote = TextEditingController(
        text: noteCtrl.text.isNotEmpty ? noteCtrl.text : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              '${loc.faWaBreakAttendanceTitlePrefix} — ${tl(context, name)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(loc.faWaBreakHint,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: tempRate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: loc.faWaReducedAmountLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tempNote,
              maxLines: 2,
              decoration: InputDecoration(
                  hintText: loc.faWaReasonHint,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.faWaApply,
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      setState(() {
        rateCtrl.text = tempRate.text;
        noteCtrl.text = tempNote.text;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Row(children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: idaDark),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1),
                  ),
                  if (widget.onDelete != null)
                    TextButton.icon(
                      onPressed: () {
                        widget.onDelete!();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.red),
                      label: Text(loc.faWaRemove,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12.5)),
                    ),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: widget.farms.any((f) => f['id'] == farmId)
                      ? farmId
                      : null,
                  decoration: InputDecoration(
                      labelText: loc.faWaFarmDropdownLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: widget.farms
                      .map<DropdownMenuItem<int>>((f) => DropdownMenuItem(
                          value: f['id'],
                          child: Text(tl(context, f['name']),
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    farmId = v;
                    widget.group.farmId = v;
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: widget.workTypes.any((w) => w['id'] == workTypeId)
                      ? workTypeId
                      : null,
                  decoration: InputDecoration(
                      labelText: loc.faWaWorkTypeDropdownLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: widget.workTypes
                      .map<DropdownMenuItem<int>>((w) => DropdownMenuItem(
                          value: w['id'],
                          child: Text(tl(context, w['name']),
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (v) => setState(() {
                    workTypeId = v;
                    widget.group.workTypeId = v;
                  }),
                ),
                const SizedBox(height: 16),
                Text(loc.faWaWorkersForThisTask,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                        letterSpacing: 0.6)),
                const SizedBox(height: 8),
                ...widget.unallocatedExcludingThisGroup.map((w) {
                  final id = w['worker_id'] as int;
                  final selected = widget.group.workerIds.contains(id);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFE8F5E2) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected
                              ? widget.idaGreen
                              : const Color(0xFFE0E7D8)),
                    ),
                    child: Column(children: [
                      CheckboxListTile(
                        dense: true,
                        value: selected,
                        activeColor: widget.idaGreen,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(tl(context, w['name'] ?? ''),
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            w['gender'] == 'M'
                                ? loc.faMaleFull
                                : loc.faFemaleFull,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                        onChanged: (_) => _toggleWorker(id),
                      ),
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Row(children: [
                            Expanded(
                              child: TextField(
                                controller: widget.group.rateCtrls[id],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                onChanged: (_) => setState(() {}),
                                enabled: !widget.prefillRate || widget.isAdmin,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: loc.faWaRateLabel,
                                  hintText: widget.prefillRate
                                      ? null
                                      : loc.faWaEnterAmountHint,
                                  helperText:
                                      widget.prefillRate && !widget.isAdmin
                                          ? loc.faWaSetThisMorningHint
                                          : null,
                                  helperStyle: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                  labelStyle: const TextStyle(fontSize: 11),
                                  hintStyle: const TextStyle(
                                      fontSize: 12, color: Colors.orange),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE0E7D8))),
                                  filled: true,
                                  fillColor:
                                      (widget.prefillRate && !widget.isAdmin)
                                          ? const Color(0xFFF4F7F2)
                                          : Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () =>
                                  _breakAttendance(id, w['name'] ?? ''),
                              icon: const Icon(Icons.timer_off_outlined,
                                  size: 15, color: Colors.orange),
                              label: Text(loc.faWaBreakAttendanceLong,
                                  style: const TextStyle(
                                      fontSize: 11.5, color: Colors.orange)),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6)),
                            ),
                          ]),
                        ),
                      if (selected &&
                          (widget.group.noteCtrls[id]?.text.isNotEmpty ??
                              false))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                '${loc.faWaNotePrefix}: ${widget.group.noteCtrls[id]!.text}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontStyle: FontStyle.italic)),
                          ),
                        ),
                    ]),
                  );
                }),
                const SizedBox(height: 16),
                if (_saveError != null) ...[
                  Text(_saveError!,
                      style:
                          const TextStyle(color: Colors.red, fontSize: 12.5)),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: widget.idaGreen,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    onPressed: () {
                      if (farmId == null) {
                        setState(() => _saveError = loc.faWaErrSelectFarm);
                        return;
                      }
                      if (widget.group.workerIds.isEmpty) {
                        setState(() => _saveError = loc.faWaErrSelectOneWorker);
                        return;
                      }
                      final missingAmount = widget.group.workerIds.where((id) =>
                          double.tryParse(
                              widget.group.rateCtrls[id]?.text.trim() ?? '') ==
                          null);
                      if (missingAmount.isNotEmpty) {
                        setState(
                            () => _saveError = loc.faWaErrAmountEveryWorker);
                        return;
                      }
                      widget.onSave(widget.group);
                      Navigator.pop(context);
                    },
                    child: Text(loc.faWaSaveThisTaskGroup,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
