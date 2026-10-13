// lib/screens/attendance_screen.dart
//
// Stage A — Attendance (redesigned Oct 2026).
//  - Morning: mark every worker Present / ½ (half day) / Absent. Live counters show
//    who is on work today (permanent, men, women) and the wage. Workers flagged
//    "Paid when absent" who are not on work are paid as leave with pay and counted
//    separately. Save draft keeps the list without sending it; Submit sends it for approval.
//  - Approved day: anyone with "Correct approved day" can change workers (half day,
//    left early, remove, make present, add late). The change is applied at once, the day
//    shows as pending again, and only the changed rows go back to the approver, who
//    approves or rejects each row (or all). Each waiting change can be undone.
//  - Offline: the morning list is saved on the phone when there is no signal (same as
//    before). Draft and approved-day changes need a connection.
// Calls: POST /attendance/day/:date/present { workers:[{worker_id, kind, amount}], draft? }
//        POST /attendance/day/:date/amend { reason, changes:[{worker_id, action, amount}] }
//        POST /attendance/day/:date/amendments/:id/undo
//        PATCH /attendance/day/:date/attendance-decision { decision, note, ids? }

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/responsive.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../widgets/offline_status_bar.dart';
import '../widgets/att_parts.dart';
import 'reports/report_builder_screen.dart';
import 'work_allocation_screen.dart';
import 'attendance_calendar_screen.dart';
import 'attendance_change_log_screen.dart';
import 'face_attendance_capture_screen.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';

class AttendanceScreen extends StatefulWidget {
  final DateTime? initialDate;
  const AttendanceScreen({super.key, this.initialDate});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const idaGreen = attGreen;
  static const idaDark = attDark;

  late DateTime selectedDate = widget.initialDate ?? DateTime.now();
  bool isAdmin = false;

  List workers = [];
  bool loadingMasters = true;
  bool loadingDay = false;
  String? error;

  // ── Marking (morning) ──
  // id -> 'present' | 'half' | 'early' | 'absent'; a worker not in the map is not marked yet.
  final Map<int, String> kinds = {};
  final Map<int, TextEditingController> amtCtrls = {};
  String workerFilter = 'All'; // All | M | F | P | N (not marked)
  final TextEditingController searchCtrl = TextEditingController();
  bool savingPresent = false;
  bool savingDraft = false;
  bool editList = false; // editing a submitted list that has no changes yet

  // ── Day state from GET /day/:date ──
  String? attendanceStatus; // null | pending | approved | returned
  String? attendanceAdminNote;
  String? allocationStatus;
  Map<String, dynamic>? presentSummary;
  List<Map<String, dynamic>> presentWorkers = [];
  List<Map<String, dynamic>> leaveWorkers = [];
  List<Map<String, dynamic>> amendments = [];
  int pendAtt = 0;
  int pendAlloc = 0;
  bool permanentAutoSuggested = false;

  // ── Changes after approval ──
  String viewFilter = 'All'; // All | M | F | P | L (leave) | C (changed)
  final Set<int> amendSel = {};
  bool busy = false;

  bool decidingAttendance = false;
  bool canUpdateStageA = false;
  bool canApproveStageA = false;
  bool canCorrectDay = false;

  // ── Offline entry ──
  String get _offlineKey => 'present:$_dateStr';
  bool _hadWaiting = false;
  String? mastersError;
  late final Listenable _offlineChanges = Listenable.merge(
      [Offline.sentTick, Offline.pendingCount, Offline.failedCount]);

  void _onOfflineChange() {
    if (!mounted) return;
    final had = _hadWaiting;
    final now = Offline.waitingFor(_offlineKey);
    _hadWaiting = now != null;
    if (had && now == null && !savingPresent) {
      _loadDay();
    } else {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _hadWaiting = Offline.waitingFor(_offlineKey) != null;
    _offlineChanges.addListener(_onOfflineChange);
    ApiService.canWriteSection('farm_attendance', 'attendance').then((v) {
      if (mounted) setState(() => canUpdateStageA = v);
    });
    ApiService.canApproveSection('farm_attendance', 'attendance').then((v) {
      if (mounted) setState(() => canApproveStageA = v);
    });
    ApiService.canCorrect('farm_attendance').then((v) {
      if (mounted) setState(() => canCorrectDay = v);
    });
    _init();
  }

  @override
  void dispose() {
    _offlineChanges.removeListener(_onOfflineChange);
    for (final c in amtCtrls.values) {
      c.dispose();
    }
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    isAdmin = await ApiService.isAdmin();
    await _loadMasters();
    await _loadDay();
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(selectedDate);

  Future<void> _loadMasters() async {
    setState(() {
      loadingMasters = true;
      mastersError = null;
    });
    try {
      final res = await Api.get('/farm-workers');
      if (res.statusCode == 200) {
        workers = jsonDecode(res.body);
        workers.sort((a, b) => (a['name'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
      }
    } catch (e) {
      debugPrint('Load masters error: $e');
      if (mounted && workers.isEmpty && Offline.isNetworkError(e)) {
        mastersError = AppLocalizations.of(context)!.offNoSaved;
      }
    } finally {
      if (mounted) setState(() => loadingMasters = false);
    }
  }

  int _int(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

  Future<void> _loadDay() async {
    setState(() {
      loadingDay = true;
      error = null;
    });
    try {
      final res = await Api.get('/attendance/day/$_dateStr');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final pc = data['pending_changes'] is Map ? data['pending_changes'] as Map : {};
        setState(() {
          presentSummary = data['present_summary'] is Map
              ? Map<String, dynamic>.from(data['present_summary'])
              : null;
          attendanceStatus = data['attendance_status'];
          attendanceAdminNote = data['attendance_admin_note'];
          allocationStatus = data['allocation_status'];
          permanentAutoSuggested = data['permanent_auto_suggested'] == true;
          pendAtt = _int(pc['attendance']);
          pendAlloc = _int(pc['allocation']);
          presentWorkers =
              List<Map<String, dynamic>>.from(data['present_workers'] ?? []);
          leaveWorkers =
              List<Map<String, dynamic>>.from(data['leave_workers'] ?? []);
          amendments =
              List<Map<String, dynamic>>.from(data['amendments'] ?? []);
          int byName(a, b) => (a['name'] ?? '')
              .toString()
              .toLowerCase()
              .compareTo((b['name'] ?? '').toString().toLowerCase());
          presentWorkers.sort(byName);
          leaveWorkers.sort(byName);
          amendSel.clear();
          editList = false;
          _resetMarks();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = Offline.isNetworkError(e)
            ? AppLocalizations.of(context)!.offNoSaved
            : 'Could not reach server: ${Api.errorText(e)}');
      }
    } finally {
      if (mounted) {
        _hadWaiting = Offline.waitingFor(_offlineKey) != null;
        setState(() => loadingDay = false);
      }
    }
  }

  // Marks start from what the server holds (a draft, a returned list, permanent
  // workers suggested on a fresh day).
  void _resetMarks() {
    for (final c in amtCtrls.values) {
      c.dispose();
    }
    amtCtrls.clear();
    kinds.clear();
    for (final p in presentWorkers) {
      final id = p['worker_id'] as int;
      final k = permanentAutoSuggested ? 'present' : ((p['kind'] ?? 'present') as String);
      kinds[id] = k;
      final amt = permanentAutoSuggested
          ? p['daily_wage']
          : (p['morning_amount'] ?? p['daily_wage']);
      amtCtrls[id] = TextEditingController(text: attFmt(attNum(amt)));
    }
  }

  Future<void> _pickDate() async {
    final picked = await Navigator.push<DateTime>(context,
        MaterialPageRoute(builder: (_) => const AttendanceCalendarScreen()));
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        kinds.clear();
        for (final c in amtCtrls.values) {
          c.dispose();
        }
        amtCtrls.clear();
      });
      _hadWaiting = Offline.waitingFor(_offlineKey) != null;
      await _loadDay();
    }
  }

  // ── Who may do what ──
  bool get _editing =>
      canUpdateStageA &&
      (attendanceStatus == null ||
          attendanceStatus == 'returned' ||
          (editList && attendanceStatus == 'pending' && pendAtt == 0));
  bool get _tracked =>
      attendanceStatus == 'approved' ||
      (attendanceStatus == 'pending' && pendAtt > 0);
  bool get _mayChange => canCorrectDay && _tracked;

  // ── Marking helpers ──
  Map _worker(int id) =>
      workers.firstWhere((w) => w['id'] == id, orElse: () => {}) as Map;
  double _wageOf(int id) => attNum(_worker(id)['daily_wage']);
  bool _isOn(int id) {
    final k = kinds[id];
    return k == 'present' || k == 'half' || k == 'early';
  }

  List<int> get _onIds => kinds.keys.where(_isOn).toList();

  void _setKind(int id, String k) {
    setState(() {
      final prev = kinds[id];
      if (k == 'half' && prev == 'early') return;
      kinds[id] = k;
      final wage = _wageOf(id);
      final c = amtCtrls.putIfAbsent(id, () => TextEditingController());
      if (k == 'present' &&
          (prev == null || prev == 'half' || prev == 'early' || prev == 'absent' || c.text.isEmpty)) {
        c.text = attFmt(wage);
      }
      if (k == 'half') c.text = attFmt(attHalfOf(wage));
    });
  }

  List get _shownWorkers {
    final q = searchCtrl.text.trim().toLowerCase();
    return workers.where((w) {
      final id = w['id'] as int;
      if (q.isNotEmpty && !(w['name'] ?? '').toString().toLowerCase().contains(q)) {
        return false;
      }
      switch (workerFilter) {
        case 'M':
          return w['gender'] == 'M';
        case 'F':
          return w['gender'] == 'F';
        case 'P':
          return attIsPerm(w);
        case 'N':
          return !kinds.containsKey(id);
      }
      return true;
    }).toList();
  }

  void _markShownPresent() {
    setState(() {
      for (final w in _shownWorkers) {
        final id = w['id'] as int;
        if (!_isOn(id)) {
          kinds[id] = 'present';
          amtCtrls.putIfAbsent(id, () => TextEditingController()).text =
              attFmt(attNum(w['daily_wage']));
        }
      }
    });
  }

  Future<void> _copyYesterday() async {
    final y = selectedDate.subtract(const Duration(days: 1));
    try {
      final res = await Api.get('/attendance/day/${DateFormat('yyyy-MM-dd').format(y)}');
      if (res.statusCode != 200) {
        setState(() => error = Api.responseError(res));
        return;
      }
      final data = jsonDecode(res.body);
      final list = List<Map<String, dynamic>>.from(data['present_workers'] ?? []);
      if (data['permanent_auto_suggested'] == true || list.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Nothing was marked yesterday'),
              behavior: SnackBarBehavior.floating));
        }
        return;
      }
      setState(() {
        for (final p in list) {
          final id = p['worker_id'] as int;
          if (!workers.any((w) => w['id'] == id)) continue;
          kinds[id] = 'present';
          amtCtrls.putIfAbsent(id, () => TextEditingController()).text =
              attFmt(_wageOf(id));
        }
      });
    } catch (e) {
      setState(() => error = 'Could not reach server: ${Api.errorText(e)}');
    }
  }

  // Counters of the list being marked (live).
  ({int on, int perm, int men, int women, int halfM, int halfF, int leaveN, double leaveAmt, double wage}) get _live {
    var on = 0, perm = 0, men = 0, women = 0, halfM = 0, halfF = 0;
    var wage = 0.0;
    for (final id in _onIds) {
      final w = _worker(id);
      on++;
      if (attIsPerm(w)) perm++;
      final half = kinds[id] != 'present';
      if (w['gender'] == 'M') {
        men++;
        if (half) halfM++;
      } else if (w['gender'] == 'F') {
        women++;
        if (half) halfF++;
      }
      wage += attNum(amtCtrls[id]?.text);
    }
    var leaveN = 0;
    var leaveAmt = 0.0;
    for (final w in workers) {
      if (attIsPaidAbsent(w) && !_isOn(w['id'] as int)) {
        leaveN++;
        leaveAmt += attNum(w['daily_wage']);
      }
    }
    return (on: on, perm: perm, men: men, women: women, halfM: halfM, halfF: halfF, leaveN: leaveN, leaveAmt: leaveAmt, wage: wage);
  }

  List<Map<String, dynamic>> _presentBody() => _onIds
      .map((id) => {
            'worker_id': id,
            'kind': kinds[id],
            'amount': double.tryParse(amtCtrls[id]?.text.trim() ?? ''),
          })
      .toList();

  Future<void> _saveDraft() async {
    setState(() {
      savingDraft = true;
      error = null;
    });
    try {
      final res = await Api.post('/attendance/day/$_dateStr/present',
          body: {'draft': true, 'workers': _presentBody()});
      if (res.statusCode == 200) {
        await _loadDay();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Draft saved. Nothing has gone to the approver yet.'),
              backgroundColor: idaGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16)));
        }
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: ${Api.errorText(e)}');
    } finally {
      if (mounted) setState(() => savingDraft = false);
    }
  }

  Future<void> _reviewAndSubmit() async {
    if (_onIds.isEmpty) {
      setState(() => error = 'Mark at least one worker present');
      return;
    }
    final t = _live;
    final loc = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.faReviewPresentWorkers,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t.on} on work today', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Men ${t.men} · Women ${t.women} · Permanent ${t.perm}', style: const TextStyle(fontSize: 13)),
          if (t.halfM + t.halfF > 0) Text('Half day: ${t.halfM + t.halfF}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text('Wage for work: ${attRs(t.wage)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if (t.leaveN > 0)
            Text('Paid, not working: ${t.leaveN} · ${attRs(t.leaveAmt)}',
                style: const TextStyle(fontSize: 13, color: attAmberFg)),
          const SizedBox(height: 8),
          Text('Not marked or absent: ${workers.length - t.on}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.faConfirmSubmit, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) await _submitPresent();
  }

  Future<void> _submitPresent() async {
    setState(() {
      savingPresent = true;
      error = null;
    });
    try {
      final res = await Api.post(
        '/attendance/day/$_dateStr/present',
        queueLabel: 'Attendance ${DateFormat('dd MMM yyyy').format(selectedDate)}',
        queueKey: _offlineKey,
        body: {'workers': _presentBody()},
      );
      if (Api.wasQueued(res)) {
        if (mounted) {
          final loc = AppLocalizations.of(context)!;
          setState(() => _hadWaiting = true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.offSavedSnack),
            backgroundColor: const Color(0xFFB45309),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      } else if (res.statusCode == 200) {
        final old = Offline.waitingFor(_offlineKey);
        if (old != null) await Offline.discard(old.id);
        await _loadDay();
        if (mounted) {
          final loc = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(loc.faAttendanceSubmitted),
            backgroundColor: idaGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ));
        }
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: ${Api.errorText(e)}');
    } finally {
      if (mounted) setState(() => savingPresent = false);
    }
  }

  // Face recognition is an alternative way to mark someone present.
  Future<void> _markViaFace() async {
    final result = await Navigator.push<FaceMatchResult>(
      context,
      MaterialPageRoute(builder: (_) => const FaceAttendanceCaptureScreen()),
    );
    if (result == null) return;
    if (_isOn(result.workerId)) {
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tl(context, result.name)} ${loc.faAlreadyMarkedPresent}'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    _setKind(result.workerId, 'present');
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

  // ── Approver ──
  Future<void> _decideAttendance(String decision, {List<int>? ids}) async {
    String? note;
    if (decision == 'reject') {
      final loc = AppLocalizations.of(context)!;
      note = await _promptForNote(loc.faRejectAttendanceTitle, loc.faRejectAttendanceHint);
      if (note == null || note.trim().isEmpty) return;
    }
    setState(() => decidingAttendance = true);
    try {
      final res = await Api.patch(
        '/attendance/day/$_dateStr/attendance-decision',
        body: {'decision': decision, if (note != null) 'note': note, if (ids != null) 'ids': ids},
      );
      if (res.statusCode == 200) {
        await _loadDay();
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: ${Api.errorText(e)}');
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            autofocus: true,
            decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text(loc.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(loc.faConfirm, style: const TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // ── Changes after approval ──
  Future<void> _postChange(String path, Map<String, dynamic> body) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await Api.post('/attendance/day/$_dateStr/$path', body: body);
      if (res.statusCode == 200) {
        await _loadDay();
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = 'Could not reach server: ${Api.errorText(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _undo(Map change) =>
      _postChange('amendments/${change['id']}/undo', {});

  // Rows of the submitted day: on work, leave with pay, and people removed by a waiting change.
  List<Map<String, dynamic>> get _rows {
    final list = <Map<String, dynamic>>[];
    for (final p in presentWorkers) {
      list.add({...p, 'kind': p['kind'] ?? 'present', 'amount': attNum(p['morning_amount'])});
    }
    for (final p in leaveWorkers) {
      list.add({...p, 'kind': 'paid_leave', 'amount': attNum(p['morning_amount'])});
    }
    final have = list.map((r) => r['worker_id']).toSet();
    for (final a in amendments) {
      if (a['stage'] != 'attendance' || have.contains(a['worker_id']) || a['was'] == null) continue;
      final w = _worker(a['worker_id'] as int);
      list.add({
        'worker_id': a['worker_id'],
        'name': a['worker_name'] ?? w['name'] ?? '#${a['worker_id']}',
        'gender': a['worker_gender'] ?? w['gender'],
        'is_permanent': w['is_permanent'],
        'paid_when_absent': w['paid_when_absent'],
        'daily_wage': w['daily_wage'],
        'kind': 'removed',
        'amount': 0.0,
        'change': a,
        'removed': true,
      });
    }
    const order = {'present': 0, 'half': 0, 'early': 0, 'paid_leave': 1, 'removed': 2};
    list.sort((a, b) {
      final c = (order[a['kind']] ?? 0).compareTo(order[b['kind']] ?? 0);
      if (c != 0) return c;
      return (a['name'] ?? '').toString().toLowerCase().compareTo((b['name'] ?? '').toString().toLowerCase());
    });
    return list;
  }

  bool _rowOnWork(Map r) => r['kind'] == 'present' || r['kind'] == 'half' || r['kind'] == 'early';

  // Half day / left early / remove / full day for the chosen people (one sheet, one reason).
  Future<void> _changeSheet(String mode, List<Map<String, dynamic>> people) async {
    final reasonCtrl = TextEditingController();
    final amounts = <int, TextEditingController>{};
    for (final p in people) {
      final id = p['worker_id'] as int;
      final wage = attNum(p['daily_wage'] ?? p['amount']);
      final base = p['kind'] == 'present' ? attNum(p['amount']) : wage;
      final text = mode == 'half'
          ? attFmt(attHalfOf(base))
          : mode == 'present'
              ? attFmt(wage > 0 ? wage : attNum(p['amount']))
              : mode == 'early'
                  ? (p['kind'] == 'early' ? attFmt(attNum(p['amount'])) : '')
                  : '';
      amounts[id] = TextEditingController(text: text);
    }
    String? err;
    final title = {'half': 'Half day', 'early': 'Left early', 'remove': 'Remove from today', 'present': 'Full day'}[mode]!;
    final help = {
      'half': 'Paid half the daily wage by default. Change the amount if it is different.',
      'early': 'Type what each person is paid for the day. They stay counted as present.',
      'remove': 'They are taken off the work list and any work allocated to them is removed.',
      'present': 'Marked present for the full day.',
    }[mode]!;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('$title · ${people.length == 1 ? tl(context, people.first['name'] ?? '') : '${people.length} workers'}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: idaDark)),
              const SizedBox(height: 4),
              Text('$help It goes back to the approver; the rest of the day stays approved.',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(shrinkWrap: true, children: [
                  for (final p in people)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tl(context, p['name'] ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text('now ${attKindTag(p['kind'] ?? 'present').text} · ${attRs(attNum(p['amount']))}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
                        ])),
                        if (mode != 'remove')
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: amounts[p['worker_id'] as int],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                              decoration: InputDecoration(
                                  prefixText: '₹', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            ),
                          ),
                      ]),
                    ),
                ]),
              ),
              if (mode == 'remove' && people.any((p) => attIsPaidAbsent(p)))
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Workers marked "Paid when absent" are paid as leave with pay.',
                        style: TextStyle(fontSize: 12, color: attAmberFg))),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: [
                for (final r in attQuickReasons)
                  ChoiceChip(
                    label: Text(r, style: const TextStyle(fontSize: 12.5)),
                    selected: reasonCtrl.text == r,
                    selectedColor: const Color(0xFFDCEBD2),
                    onSelected: (_) => setSheet(() {
                      reasonCtrl.text = r;
                      err = null;
                    }),
                  ),
              ]),
              const SizedBox(height: 4),
              TextField(
                controller: reasonCtrl,
                onChanged: (_) => setSheet(() => err = null),
                decoration: InputDecoration(
                    labelText: 'Reason (required)',
                    errorText: err,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: mode == 'remove' ? const Color(0xFFC0392B) : idaGreen),
                  onPressed: () {
                    if (reasonCtrl.text.trim().isEmpty) {
                      setSheet(() => err = 'Write a short reason first');
                      return;
                    }
                    if (mode == 'early' && amounts.values.any((c) => double.tryParse(c.text.trim()) == null)) {
                      setSheet(() => err = 'Type the amount for everyone');
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: Text(title, style: const TextStyle(color: Colors.white)),
                )),
              ]),
            ]),
          ),
        );
      }),
    );
    final reason = reasonCtrl.text.trim();
    final action = {'half': 'half', 'early': 'left_early', 'remove': 'absent', 'present': 'present'}[mode]!;
    final changes = [
      for (final p in people)
        {
          'worker_id': p['worker_id'],
          'action': action,
          if (mode != 'remove') 'amount': double.tryParse(amounts[p['worker_id'] as int]!.text.trim()),
        }
    ];
    // (the controllers are left to be collected: the sheet is still animating out)
    if (ok != true) return;
    setState(() => amendSel.clear());
    await _postChange('amend', {'reason': reason, 'changes': changes});
  }

  // Add workers who came but are not on today's list.
  Future<void> _addWorkersSheet() async {
    final onIds = presentWorkers.map((p) => p['worker_id']).toSet();
    final choices = workers.where((w) => !onIds.contains(w['id'])).toList();
    final pick = <int, TextEditingController>{};
    final reasonCtrl = TextEditingController();
    final qCtrl = TextEditingController();
    String? err;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final q = qCtrl.text.trim().toLowerCase();
        final shown = choices.where((w) => q.isEmpty || (w['name'] ?? '').toString().toLowerCase().contains(q)).toList();
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Add workers to today', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: idaDark)),
            const SizedBox(height: 4),
            const Text('For people who came to work but are not on the list. They are added as present, then need to be allocated to a task.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
            const SizedBox(height: 8),
            TextField(
              controller: qCtrl,
              onChanged: (_) => setSheet(() {}),
              decoration: InputDecoration(
                  hintText: 'Search worker',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(shrinkWrap: true, children: [
                  if (shown.isEmpty)
                    const Padding(padding: EdgeInsets.all(12), child: Text('No one left to add.', style: TextStyle(color: Colors.grey))),
                  for (final w in shown)
                    Row(children: [
                      Checkbox(
                        value: pick.containsKey(w['id']),
                        activeColor: idaGreen,
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            pick[w['id'] as int] = TextEditingController(text: attFmt(attNum(w['daily_wage'])));
                          } else {
                            pick.remove(w['id']);
                          }
                        }),
                      ),
                      Expanded(
                          child: Text(tl(context, w['name'] ?? ''),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                      if (pick.containsKey(w['id']))
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: pick[w['id']],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(prefixText: '₹', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          ),
                        ),
                    ]),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final r in attQuickReasons)
                ChoiceChip(
                  label: Text(r, style: const TextStyle(fontSize: 12.5)),
                  selected: reasonCtrl.text == r,
                  selectedColor: const Color(0xFFDCEBD2),
                  onSelected: (_) => setSheet(() {
                    reasonCtrl.text = r;
                    err = null;
                  }),
                ),
            ]),
            TextField(
              controller: reasonCtrl,
              onChanged: (_) => setSheet(() => err = null),
              decoration: InputDecoration(
                  labelText: 'Reason (required)', errorText: err, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed: () {
                  if (pick.isEmpty) {
                    setSheet(() => err = 'Tick at least one worker');
                    return;
                  }
                  if (reasonCtrl.text.trim().isEmpty) {
                    setSheet(() => err = 'Write a short reason first');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text('Add ${pick.length}', style: const TextStyle(color: Colors.white)),
              )),
            ]),
          ]),
        );
      }),
    );
    final reason = reasonCtrl.text.trim();
    final changes = [
      for (final e in pick.entries) {'worker_id': e.key, 'action': 'add', 'amount': double.tryParse(e.value.text.trim())}
    ];
    if (ok != true) return;
    await _postChange('amend', {'reason': reason, 'changes': changes});
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(loc.faAddWorker, style: const TextStyle(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: loc.faWorkerNameLabel,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: ChoiceChip(
                          label: Text(loc.faMaleFull),
                          selected: gender == 'M',
                          selectedColor: idaGreen.withOpacity(0.15),
                          onSelected: (_) => setDialogState(() => gender = 'M'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: ChoiceChip(
                          label: Text(loc.faFemaleFull),
                          selected: gender == 'F',
                          selectedColor: idaGreen.withOpacity(0.15),
                          onSelected: (_) => setDialogState(() => gender = 'F'))),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: wageCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: loc.faDailyWageLabel,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: loc.faPhoneOptionalLabel,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || wageCtrl.text.trim().isEmpty) return;
                  final res = await Api.post(
                    '/farm-workers',
                    body: {
                      'name': nameCtrl.text.trim(),
                      'daily_wage': wageCtrl.text.trim(),
                      'gender': gender,
                      'phone': phoneCtrl.text.trim(),
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx, res.statusCode == 200);
                },
                child: Text(loc.faAdd, style: const TextStyle(color: Colors.white)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  // ════════════════════════ build ════════════════════════
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: idaDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(loc.faTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: loc.faStatusCalendarTooltip,
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Change log',
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AttendanceChangeLogScreen(date: selectedDate)));
              if (mounted) _loadDay();
            },
          ),
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: loc.faReportsTooltip,
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReportBuilderScreen(reportKey: 'attendance'))),
          ),
        ],
      ),
      bottomNavigationBar: (_mayChange && amendSel.isNotEmpty && !_editing) ? _bulkBar() : null,
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
                      const OfflineStatusBar(),
                      _offlineNotice(loc),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE0E7D8))),
                          child: Row(children: [
                            const Icon(Icons.calendar_today, size: 18, color: idaGreen),
                            const SizedBox(width: 10),
                            Text(DateFormat('EEEE, dd MMM yyyy').format(selectedDate),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: idaDark)),
                            const Spacer(),
                            const Icon(Icons.edit_calendar_outlined, size: 18, color: Colors.grey),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _workflowStepper(loc),
                      const SizedBox(height: 12),
                      _statusBanner(loc),
                      const SizedBox(height: 12),
                      if (loadingDay)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(30),
                                child: CircularProgressIndicator(color: idaGreen)))
                      else if (_editing)
                        ..._editBody(loc)
                      else
                        ..._readBody(loc),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                      ],
                      if (mastersError != null && mastersError != error) ...[
                        const SizedBox(height: 10),
                        Text(mastersError!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                      ],
                    ],
                  )),
            ),
    );
  }

  Widget _offlineNotice(AppLocalizations loc) {
    final e = Offline.waitingFor(_offlineKey);
    if (e == null) return const SizedBox.shrink();
    final failed = e.status == 'failed';
    final fg = failed ? const Color(0xFFC0392B) : const Color(0xFF92600A);
    final bg = failed ? const Color(0xFFFDE8E8) : const Color(0xFFFEF3DC);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(failed ? Icons.error_outline : Icons.cloud_upload_outlined, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(failed ? loc.offNoticeFailed(e.error) : loc.offNoticeWaiting,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ]),
        if (failed) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.pushNamed(context, '/offline'),
              style: TextButton.styleFrom(foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(loc.offOpenList, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _workflowStepper(AppLocalizations loc) {
    int stage;
    String label;
    Color activeColor = idaGreen;
    final att = (attendanceStatus == 'pending' && pendAtt > 0) ? 'approved' : attendanceStatus;
    if (att == null) {
      stage = 1;
      label = loc.faStepMarkPresent;
    } else if (att == 'returned') {
      stage = 1;
      label = loc.faStepAttendanceReturned;
      activeColor = const Color(0xFFC0392B);
    } else if (att == 'pending') {
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
    if (pendAtt + pendAlloc > 0) {
      label = '${pendAtt + pendAlloc} change${pendAtt + pendAlloc == 1 ? '' : 's'} waiting for re-approval';
      activeColor = const Color(0xFF92600A);
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
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: activeColor)),
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
        label = pendAtt > 0
            ? '$pendAtt change${pendAtt == 1 ? ' is' : 's are'} waiting for re-approval. Everything else stays approved.'
            : loc.faStatusPendingAttendance;
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
        label = '${loc.faStatusReturned}${attendanceAdminNote != null ? ': $attendanceAdminNote' : ''}';
        break;
      default:
        return const SizedBox.shrink();
    }
    final firstDecision = attendanceStatus == 'pending' && pendAtt == 0 && canApproveStageA;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13))),
        ]),
        if (firstDecision) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
                onPressed: decidingAttendance ? null : () => _decideAttendance('approve'),
                child: Text(loc.faApprove, style: const TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                onPressed: decidingAttendance ? null : () => _decideAttendance('reject'),
                child: Text(loc.faReject),
              ),
            ),
          ]),
        ],
        if (attendanceStatus == 'pending' && pendAtt == 0 && canUpdateStageA && !editList) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit list'),
            onPressed: () => setState(() {
              editList = true;
              _resetMarks();
            }),
          ),
        ],
        if (_tracked) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.work_outline, color: Colors.white, size: 18),
              label: Text(loc.faGoToWorkAllocation,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: idaDark, padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => WorkAllocationScreen(attendanceDate: selectedDate)));
                if (mounted) _loadDay();
              },
            ),
          ),
        ],
      ]),
    );
  }

  // ── Morning marking ──
  List<Widget> _editBody(AppLocalizations loc) {
    final t = _live;
    final shown = _shownWorkers;
    return [
      AttStatTiles(
          onWork: t.on, permanent: t.perm, men: t.men, women: t.women, halfMen: t.halfM, halfWomen: t.halfF,
          leaveCount: t.leaveN, leaveAmount: t.leaveAmt, workWage: t.wage),
      const SizedBox(height: 12),
      if (permanentAutoSuggested)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF5D48A))),
          child: const Row(children: [
            Icon(Icons.push_pin, size: 15, color: Color(0xFFB8860B)),
            SizedBox(width: 6),
            Expanded(
                child: Text('Permanent workers are marked present for you. Change anyone who is absent or on a half day, then submit.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF8A6D1F)))),
          ]),
        ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 4, children: [
            TextButton.icon(
              onPressed: _markViaFace,
              icon: const Icon(Icons.face_retouching_natural, size: 16, color: idaGreen),
              label: Text(loc.faMarkViaFace,
                  style: const TextStyle(color: idaGreen, fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
            TextButton.icon(
              onPressed: _showAddWorkerDialog,
              icon: const Icon(Icons.person_add_alt_1, size: 16, color: idaGreen),
              label: Text(loc.faAddWorker,
                  style: const TextStyle(color: idaGreen, fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ]),
          TextField(
            controller: searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: loc.faSearchWorkers,
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
            ),
          ),
          const SizedBox(height: 8),
          _filterChips([
            ('All', loc.faAll, workers.length),
            ('M', loc.faMaleFull, workers.where((w) => w['gender'] == 'M').length),
            ('F', loc.faFemaleFull, workers.where((w) => w['gender'] == 'F').length),
            ('P', 'Permanent', workers.where((w) => attIsPerm(w)).length),
            ('N', 'Not marked', workers.where((w) => !kinds.containsKey(w['id'])).length),
          ], workerFilter, (v) => setState(() => workerFilter = v)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
                onPressed: _markShownPresent,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Mark shown present', style: TextStyle(fontSize: 12.5))),
            OutlinedButton.icon(
                onPressed: _copyYesterday,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy yesterday', style: TextStyle(fontSize: 12.5))),
          ]),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(padding: EdgeInsets.all(14), child: Text('No one matches.', style: TextStyle(color: Colors.grey))),
          for (final w in shown) _markRow(w as Map),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        if (editList)
          Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                  onPressed: () => setState(() {
                        editList = false;
                        _resetMarks();
                      }),
                  child: const Text('Cancel'))),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: (savingDraft || savingPresent) ? null : _saveDraft,
            child: Text(savingDraft ? 'Saving…' : 'Save draft'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            icon: savingPresent
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            label: Text(savingPresent ? loc.faSubmitting : 'Submit ${t.on} present',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: idaGreen,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: (savingPresent || savingDraft) ? null : _reviewAndSubmit,
          ),
        ),
      ]),
    ];
  }

  Widget _filterChips(List<(String, String, int)> items, String value, ValueChanged<String> onPick) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => onPick(it.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: value == it.$1 ? idaGreen : const Color(0xFFF4F7F2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${it.$2} ${it.$3}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: value == it.$1 ? Colors.white : Colors.grey.shade700)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _markRow(Map w) {
    final id = w['id'] as int;
    final k = kinds[id];
    final on = _isOn(id);
    final leave = attIsPaidAbsent(w) && !on;
    final half = k == 'half' || k == 'early';
    final bg = k == null
        ? Colors.white
        : on
            ? (half ? const Color(0xFFFFF8E8) : const Color(0xFFE8F5E2))
            : (leave ? const Color(0xFFFFFAF3) : const Color(0xFFF1F2EE));
    final sub = k == 'half'
        ? 'Half day'
        : k == 'early'
            ? 'Left early'
            : on
                ? 'Present'
                : leave
                    ? 'Leave with pay · not working'
                    : k == 'absent'
                        ? 'Absent'
                        : 'Not marked yet';
    Widget seg(String label, String kind, bool selected, Color on) => Expanded(
          child: InkWell(
            onTap: () => _setKind(id, kind),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              color: selected ? on : Colors.white,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: selected ? Colors.white : const Color(0xFF3C4837))),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(w['gender'] == 'M' ? Icons.male : (w['gender'] == 'F' ? Icons.female : Icons.person_outline), color: idaGreen, size: 18),
          const SizedBox(width: 6),
          Flexible(
              child: Text(tl(context, w['name'] ?? ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (attIsPerm(w)) const AttPermTag(),
          if (attIsPaidAbsent(w)) const AttPaidTag(),
          const Spacer(),
          if (on)
            SizedBox(
              width: 92,
              child: TextField(
                controller: amtCtrls[id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                    prefixText: '₹',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              ),
            )
          else
            Text(attRs(attNum(w['daily_wage'])), style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(sub,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: (half || leave) ? FontWeight.w700 : FontWeight.w500,
                  color: (half || leave) ? attAmberFg : Colors.grey.shade600)),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFCDD7C5)), borderRadius: BorderRadius.circular(9)),
            child: Row(children: [
              seg('Present', 'present', k == 'present', const Color(0xFF2C6A1A)),
              Container(width: 1, height: 40, color: const Color(0xFFCDD7C5)),
              seg('½', 'half', k == 'half' || k == 'early', const Color(0xFFB76E00)),
              Container(width: 1, height: 40, color: const Color(0xFFCDD7C5)),
              seg('Absent', 'absent', k == 'absent', const Color(0xFF5B6755)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Submitted day ──
  List<Widget> _readBody(AppLocalizations loc) {
    final rows = _rows;
    if (attendanceStatus == null && rows.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7D8))),
          child: Text(canUpdateStageA ? '' : 'Attendance for this day has not been marked yet.',
              style: const TextStyle(color: Colors.grey)),
        ),
      ];
    }
    final s = presentSummary;
    final men = s != null ? _int(s['male']) : presentWorkers.where((p) => p['gender'] == 'M').length;
    final women = s != null ? _int(s['female']) : presentWorkers.where((p) => p['gender'] == 'F').length;
    final halfM = presentWorkers.where((p) => p['gender'] == 'M' && (p['kind'] ?? 'present') != 'present').length;
    final halfF = presentWorkers.where((p) => p['gender'] == 'F' && (p['kind'] ?? 'present') != 'present').length;
    final shown = rows.where((r) {
      final q = searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty && !(r['name'] ?? '').toString().toLowerCase().contains(q)) return false;
      switch (viewFilter) {
        case 'M':
          return r['gender'] == 'M';
        case 'F':
          return r['gender'] == 'F';
        case 'P':
          return attIsPerm(r);
        case 'L':
          return r['kind'] == 'paid_leave';
        case 'C':
          return r['change'] != null;
      }
      return true;
    }).toList();
    final reviewList = amendments.where((a) => a['stage'] == 'attendance').toList();
    return [
      AttStatTiles(
          onWork: s != null ? _int(s['on_work']) : presentWorkers.length,
          permanent: s != null ? _int(s['permanent']) : presentWorkers.where((p) => attIsPerm(p)).length,
          men: men, women: women, halfMen: halfM, halfWomen: halfF,
          leaveCount: s != null ? _int(s['paid_leave_count']) : leaveWorkers.length,
          leaveAmount: s != null ? attNum(s['paid_leave_amount']) : 0,
          workWage: s != null ? attNum(s['work_wage']) : 0),
      const SizedBox(height: 12),
      if (attendanceStatus == 'pending' && pendAtt > 0 && canApproveStageA && reviewList.isNotEmpty) ...[
        _changeReview(reviewList),
        const SizedBox(height: 12),
      ],
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0E7D8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(attendanceStatus == 'approved' ? 'ATTENDANCE' : 'MARKED PRESENT',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6B7280), letterSpacing: 0.6)),
            const Spacer(),
            if (_mayChange)
              TextButton.icon(
                onPressed: busy ? null : _addWorkersSheet,
                icon: const Icon(Icons.person_add_alt_1, size: 16, color: idaGreen),
                label: const Text('Add workers', style: TextStyle(color: idaGreen, fontSize: 12.5, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
              ),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: loc.faSearchWorkers,
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E7D8))),
            ),
          ),
          const SizedBox(height: 8),
          _filterChips([
            ('All', loc.faAll, rows.length),
            ('M', loc.faMaleFull, rows.where((r) => r['gender'] == 'M').length),
            ('F', loc.faFemaleFull, rows.where((r) => r['gender'] == 'F').length),
            ('P', 'Permanent', rows.where((r) => attIsPerm(r)).length),
            ('L', 'Leave with pay', rows.where((r) => r['kind'] == 'paid_leave').length),
            if (pendAtt > 0) ('C', 'Changed', rows.where((r) => r['change'] != null).length),
          ], viewFilter, (v) => setState(() => viewFilter = v)),
          const SizedBox(height: 8),
          if (shown.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('No one here.', style: TextStyle(color: Colors.grey))),
          for (final r in shown) _sheetRow(r),
          if (!canCorrectDay && _tracked)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('You can view this day. Changing an approved day needs the "Correct approved day" permission.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
        ]),
      ),
    ];
  }

  Widget _sheetRow(Map<String, dynamic> r) {
    final id = r['worker_id'] as int;
    final change = r['change'] is Map ? r['change'] as Map : null;
    final removed = r['removed'] == true;
    final kind = removed ? 'removed' : (change != null && change['action'] == 'add' ? 'added' : (r['kind'] as String));
    final onW = _rowOnWork(r);
    final amount = attNum(r['amount']);
    final was = change != null && change['was'] is Map ? change['was'] as Map : null;
    final wasText = (was != null && (attNum(was['amount']) - amount).abs() > 0.004) ? ' (was ${attRs(attNum(was['amount']))})' : '';
    final selectable = _mayChange && onW && !removed;
    final bg = change != null ? const Color(0xFFFFF8E8) : (amendSel.contains(id) ? const Color(0xFFEEF6E8) : (r['kind'] == 'paid_leave' ? const Color(0xFFFFFAF3) : Colors.white));
    Widget btn(String t, VoidCallback f) => OutlinedButton(
        onPressed: busy ? null : f,
        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
        child: Text(t, style: const TextStyle(fontSize: 12.5)));
    final actions = <Widget>[];
    if (_mayChange) {
      if (change != null) {
        if (onW) actions.add(btn('Edit', () => _changeSheet(r['kind'] == 'early' ? 'early' : 'half', [r])));
        actions.add(btn('Undo change', () => _undo(change)));
      } else if (onW) {
        actions.add(r['kind'] == 'present' ? btn('Half', () => _changeSheet('half', [r])) : btn('Full day', () => _changeSheet('present', [r])));
        actions.add(btn('Left early', () => _changeSheet('early', [r])));
        actions.add(btn('Remove', () => _changeSheet('remove', [r])));
      } else if (r['kind'] == 'paid_leave') {
        actions.add(btn('Make present', () => _changeSheet('present', [r])));
      }
    }
    final note = change != null
        ? '${change['reason'] ?? ''}${change['created_by_name'] != null ? ' · ${change['created_by_name']}' : ''} · waiting approval'
        : (r['kind'] == 'paid_leave' ? 'Paid, not working' : (r['note'] ?? '').toString());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E7D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (selectable)
            SizedBox(
              width: 32,
              height: 28,
              child: Checkbox(
                value: amendSel.contains(id),
                activeColor: idaGreen,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    amendSel.add(id);
                  } else {
                    amendSel.remove(id);
                  }
                }),
              ),
            ),
          Flexible(
              child: Text(tl(context, r['name'] ?? ''),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (attIsPerm(r)) const AttPermTag(),
          if (attIsPaidAbsent(r)) const AttPaidTag(),
          const Spacer(),
          Text(removed ? '' : attRs(amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          AttChip.kind(kind),
          if (wasText.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 6), child: Text(wasText, style: const TextStyle(fontSize: 11.5, color: attAmberFg))),
        ]),
        if (note.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(note, style: TextStyle(fontSize: 11.5, color: change != null ? attAmberFg : Colors.grey.shade600))),
        if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, runSpacing: 4, children: actions)),
      ]),
    );
  }

  Widget _bulkBar() {
    final people = _rows.where((r) => amendSel.contains(r['worker_id'])).toList();
    Widget b(String t, String mode) => Expanded(
          child: TextButton(
              onPressed: busy ? null : () => _changeSheet(mode, people),
              child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
        );
    return Container(
      color: idaDark,
      padding: EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 6 + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        Text('${people.length} selected', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        b('Half day', 'half'),
        b('Left early', 'early'),
        b('Remove', 'remove'),
        IconButton(
            onPressed: () => setState(() => amendSel.clear()),
            icon: const Icon(Icons.close, color: Color(0xFFCFE3C0), size: 20)),
      ]),
    );
  }

  String _amText(Map a) {
    final now = a['now'] is Map ? a['now'] as Map : null;
    final was = a['was'] is Map ? a['was'] as Map : null;
    final act = a['action'];
    final label = act == 'add'
        ? 'Added late'
        : act == 'absent'
            ? ((now != null && now['kind'] == 'paid_leave') ? 'Absent, leave with pay' : 'Removed')
            : act == 'half'
                ? 'Half day'
                : act == 'left_early'
                    ? 'Left early'
                    : act == 'paid_leave'
                        ? 'Leave with pay'
                        : act == 'present'
                            ? 'Full day'
                            : '$act';
    final amt = now != null ? ' · ${attRs(attNum(now['amount']))}' : '';
    final wasT = (was != null && (now == null || (attNum(was['amount']) - attNum(now['amount'])).abs() > 0.004))
        ? ' (was ${attRs(attNum(was['amount']))})'
        : '';
    return '$label$amt$wasT';
  }

  // The approver's view of what changed: approve or reject each row, or all.
  Widget _changeReview(List<Map<String, dynamic>> list) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEC46B), width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Changes to approve · ${list.length}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: idaDark)),
        const SizedBox(height: 8),
        for (final a in list)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFAF0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0DBA6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tl(context, (a['worker_name'] ?? '').toString()),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(_amText(a), style: const TextStyle(fontSize: 12.5, color: Color(0xFF5C4A1A))),
              Text('${a['reason'] != null ? '"${a['reason']}"' : ''} ${a['created_by_name'] != null ? '· ${a['created_by_name']}' : ''}',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7280))),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: idaGreen, visualDensity: VisualDensity.compact),
                  onPressed: decidingAttendance ? null : () => _decideAttendance('approve', ids: [_int(a['id'])]),
                  child: const Text('Approve', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), visualDensity: VisualDensity.compact),
                  onPressed: decidingAttendance ? null : () => _decideAttendance('reject', ids: [_int(a['id'])]),
                  child: const Text('Reject', style: TextStyle(fontSize: 12.5)),
                )),
              ]),
            ]),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
            onPressed: decidingAttendance ? null : () => _decideAttendance('reject'),
            child: const Text('Reject all'),
          )),
          const SizedBox(width: 10),
          Expanded(
              child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: idaGreen),
            onPressed: decidingAttendance ? null : () => _decideAttendance('approve'),
            child: const Text('Approve all', style: TextStyle(color: Colors.white)),
          )),
        ]),
      ]),
    );
  }
}
