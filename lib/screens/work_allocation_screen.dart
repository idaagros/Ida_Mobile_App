// lib/screens/work_allocation_screen.dart
//
// Step 2 - Work allocation (redesigned Oct 2026, same behaviour as the web).
//
//  While it can still be changed (not submitted, or returned):
//   * Workers tab: tick one, many or all workers (Select all / Men / Women).
//   * "Assign" them to a task: farm + work (+ crop when the farm has several,
//     + work detail). A person can be in several tasks (same or different
//     farms); their pay is then split by rupee amounts typed per task, with a
//     live balance and "Split equally".
//   * Tasks tab: the tasks with amounts, and a "Check before submit" panel.
//   * "Paid, not working" people are not allocated.
//   * Save draft keeps everything on the server without sending it to the
//     approver; Submit sends it. Reopening a day keeps what was entered.
//
//  Once submitted (waiting / approved):
//   * First submission: the approver approves or returns it.
//   * Approved day: people with "Correct approved day" can Change one person,
//     or Assign / Remove many. The change applies at once, the day shows as
//     pending and ONLY the changed people go back to the approver. Each change
//     can be undone. The approver reviews per person or all together.
//
// Calls: POST  /attendance/day/:date/allocation          { submit?, allocations }
//        POST  /attendance/day/:date/allocation-amend    { reason, changes }
//        POST  /attendance/day/:date/amendments/:id/undo
//        PATCH /attendance/day/:date/allocation-decision { decision, note, ids? }
// The submit is kept on the phone when there is no signal (key 'allocation:$date').
// Reopen moved to the change log screen.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../widgets/offline_status_bar.dart';
import '../widgets/att_parts.dart';
import '../localization/app_localizations.dart';
import '../localization/transliterate.dart';
import '../services/responsive.dart';
import '../widgets/voice_allocation_sheet.dart';
import '../widgets/grouped_scan_review_sheet.dart';
import 'attendance_change_log_screen.dart';

// A master row is active unless it says otherwise (inactive farms / work types are
// only offered when they are already picked).
bool _waIsActive(dynamic row) {
  if (row is! Map) return true;
  final v = row['is_active'];
  if (v == null) return true;
  return v == 1 || v == true || v == '1' || v == 'true';
}

class WorkAllocationScreen extends StatefulWidget {
  final DateTime attendanceDate;
  const WorkAllocationScreen({super.key, required this.attendanceDate});

  @override
  State<WorkAllocationScreen> createState() => _WorkAllocationScreenState();
}

int _int(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

// One person inside one task.
class _TW {
  final int workerId;
  final TextEditingController amount;
  String notes;
  _TW(this.workerId, String amt, {this.notes = ''})
      : amount = TextEditingController(text: amt);
}

class _Task {
  final int uid;
  int? farmId;
  int? workTypeId;
  String? workTypeName;
  String crop = ''; // '' | 'seasonal:12' | 'orchard:3' | 'none:x' (general work)
  String detail = '';
  final List<_TW> workers = [];
  _Task(this.uid);
  String get key => '$farmId::${workTypeId ?? ''}::$crop';
}

// What the farm / work / crop / detail form edits.
class _Spec {
  int? farmId;
  int? workTypeId;
  String? workTypeName;
  String crop;
  final TextEditingController detail;
  final TextEditingController amount;
  _Spec(
      {this.farmId,
      this.workTypeId,
      this.workTypeName,
      this.crop = '',
      String detailText = '',
      String amountText = ''})
      : detail = TextEditingController(text: detailText),
        amount = TextEditingController(text: amountText);
  void dispose() {
    detail.dispose();
    amount.dispose();
  }
}

// Quick-pick chips ("detail_options") of one work type, read defensively:
// missing / non-list / non-string items give an empty or cleaned list.
List<String> _detailOptionsOf(List workTypes, int? workTypeId) {
  if (workTypeId == null) return const [];
  for (final w in workTypes) {
    if (w is Map && w['id'] == workTypeId) {
      final raw = w['detail_options'];
      if (raw is! List) return const [];
      final out = <String>[];
      for (final o in raw) {
        if (o is! String) continue;
        final t = o.trim();
        if (t.isEmpty) continue;
        if (out.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
        out.add(t);
      }
      return out;
    }
  }
  return const [];
}

List<String> _detailParts(String text) => text
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

// Text field + quick-pick chips for the optional work detail.
class _WorkDetailField extends StatefulWidget {
  final TextEditingController controller;
  final List<String> options;
  final VoidCallback? onChanged;
  const _WorkDetailField(
      {super.key, required this.controller, required this.options, this.onChanged});

  @override
  State<_WorkDetailField> createState() => _WorkDetailFieldState();
}

class _WorkDetailFieldState extends State<_WorkDetailField> {
  static const _maxLen = 255;

  bool _isSelected(String opt) => _detailParts(widget.controller.text)
      .any((p) => p.toLowerCase() == opt.toLowerCase());

  void _toggle(String opt) {
    final parts = _detailParts(widget.controller.text);
    final i = parts.indexWhere((p) => p.toLowerCase() == opt.toLowerCase());
    if (i >= 0) {
      parts.removeAt(i);
    } else {
      parts.add(opt);
    }
    final text = parts.join(', ');
    if (text.length > _maxLen) return;
    widget.controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: widget.controller,
        maxLength: _maxLen,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 13),
        onChanged: (_) {
          setState(() {});
          widget.onChanged?.call();
        },
        decoration: InputDecoration(
            labelText: loc.faWorkDetailOptional,
            hintText: loc.faWorkDetailHint,
            hintStyle: const TextStyle(fontSize: 12),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
      ),
      if (widget.options.isNotEmpty)
        LayoutBuilder(builder: (context, c) {
          final maxLabel = c.maxWidth.isFinite ? (c.maxWidth - 48) : 300.0;
          return Wrap(spacing: 6, runSpacing: 0, children: [
            for (final opt in widget.options)
              Builder(builder: (_) {
                final sel = _isSelected(opt);
                final fits = widget.controller.text.length + opt.length + 2 <=
                    _maxLen;
                return FilterChip(
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: maxLabel < 60 ? 60 : maxLabel),
                    child: Text(opt,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                  selected: sel,
                  selectedColor: const Color(0xFFE8F5E2),
                  checkmarkColor: const Color(0xFF3B7A28),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (sel || fits) ? (_) => _toggle(opt) : null,
                );
              }),
          ]);
        }),
    ]);
  }
}

// Farm, work done, crop (only when the farm has several) and work detail.
class _TaskFields extends StatefulWidget {
  final _Spec spec;
  final List farms;
  final List workTypes;
  final Future<List> Function(int farmId) loadCrops;
  final VoidCallback? onChanged;
  final bool showErr;
  const _TaskFields({
    super.key,
    required this.spec,
    required this.farms,
    required this.workTypes,
    required this.loadCrops,
    this.onChanged,
    this.showErr = false,
  });

  @override
  State<_TaskFields> createState() => _TaskFieldsState();
}

class _TaskFieldsState extends State<_TaskFields> {
  List crops = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final id = widget.spec.farmId;
    if (id == null) {
      if (mounted) setState(() => crops = []);
      return;
    }
    final c = await widget.loadCrops(id);
    if (mounted && widget.spec.farmId == id) setState(() => crops = c);
  }

  InputDecoration _dec(String label, {bool err = false}) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        errorText: err ? 'Required' : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final farmItems = widget.farms
        .where((f) => _waIsActive(f) || f['id'] == s.farmId)
        .toList();
    final workItems = widget.workTypes
        .where((w) => _waIsActive(w) || w['id'] == s.workTypeId)
        .toList();
    final farmVal = farmItems.any((f) => f['id'] == s.farmId) ? s.farmId : null;
    final workVal =
        workItems.any((w) => w['id'] == s.workTypeId) ? s.workTypeId : null;
    final cropValues = [
      for (final c in crops) '${c['cycle_type']}:${c['cycle_id']}',
      'none:x'
    ];
    final cropVal = cropValues.contains(s.crop) ? s.crop : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<int>(
        value: farmVal,
        isExpanded: true,
        decoration: _dec('Farm', err: widget.showErr && s.farmId == null),
        items: [
          for (final f in farmItems)
            DropdownMenuItem<int>(
                value: f['id'] as int,
                child: Text(tl(context, '${f['name']}'),
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() {
            s.farmId = v;
            s.crop = '';
            crops = [];
          });
          _fetch();
          widget.onChanged?.call();
        },
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        value: workVal,
        isExpanded: true,
        decoration: _dec('Work done (optional)'),
        items: [
          for (final w in workItems)
            DropdownMenuItem<int>(
                value: w['id'] as int,
                child: Text(tl(context, '${w['name']}'),
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() {
            s.workTypeId = v;
            s.workTypeName = null;
          });
          widget.onChanged?.call();
        },
      ),
      if (crops.length > 1) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: cropVal,
          isExpanded: true,
          decoration:
              _dec('For which crop', err: widget.showErr && s.crop.isEmpty),
          items: [
            for (final c in crops)
              DropdownMenuItem<String>(
                  value: '${c['cycle_type']}:${c['cycle_id']}',
                  child: Text('${c['label'] ?? c['crop_name'] ?? ''}',
                      overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem<String>(
                value: 'none:x', child: Text('General farm work (no crop)')),
          ],
          onChanged: (v) {
            setState(() => s.crop = v ?? '');
            widget.onChanged?.call();
          },
        ),
      ],
      const SizedBox(height: 10),
      _WorkDetailField(
        key: ValueKey('wd-${s.workTypeId}'),
        controller: s.detail,
        options: _detailOptionsOf(widget.workTypes, s.workTypeId),
        onChanged: widget.onChanged,
      ),
    ]);
  }
}

class _WorkAllocationScreenState extends State<WorkAllocationScreen> {
  bool loading = true;
  String? busy; // 'draft' | 'submit' | 'copy' | 'save' | 'decide'
  String? error;
  String? notice;

  bool canWriteAlloc = false;
  bool canApproveAlloc = false;
  bool canCorrectDay = false;

  List farms = [];
  List workTypes = [];
  List<Map<String, dynamic>> presentWorkers = [];
  List<Map<String, dynamic>> leaveWorkers = [];
  List<Map<String, dynamic>> savedAllocations = [];
  List<Map<String, dynamic>> amendments = []; // allocation stage only
  String? attendanceStatus;
  String? allocationStatus;
  String? allocationAdminNote;
  int pendAtt = 0;
  int pendAlloc = 0;

  final List<_Task> tasks = [];
  int _uid = 1;
  final Set<int> sel = {};
  String status = 'todo'; // builder: todo | done | split | all
  String filter = 'all'; // sheet: all | none | split | changed
  String q = '';
  int tab = 0; // 0 workers, 1 tasks
  final TextEditingController _searchCtrl = TextEditingController();

  String get _dateStr => DateFormat('yyyy-MM-dd').format(widget.attendanceDate);

  // ── Offline entry ──
  String get _offlineKey => 'allocation:$_dateStr';
  bool _hadWaiting = false;
  bool _mastersNetFail = false;
  late final Listenable _offlineChanges = Listenable.merge(
      [Offline.sentTick, Offline.pendingCount, Offline.failedCount]);

  void _onOfflineChange() {
    if (!mounted) return;
    final had = _hadWaiting;
    final now = Offline.waitingFor(_offlineKey);
    _hadWaiting = now != null;
    if (had && now == null && busy == null) {
      _reloadAfterSend();
    } else {
      setState(() {});
    }
  }

  Future<void> _reloadAfterSend() async {
    await _loadDay();
    if (!mounted) return;
    if (allocationStatus == 'pending' || allocationStatus == 'approved') {
      setState(() => tasks.clear());
      await _clearLocalDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    _hadWaiting = Offline.waitingFor(_offlineKey) != null;
    _offlineChanges.addListener(_onOfflineChange);
    _init();
  }

  @override
  void dispose() {
    _offlineChanges.removeListener(_onOfflineChange);
    _searchCtrl.dispose();
    for (final t in tasks) {
      for (final w in t.workers) {
        w.amount.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _init() async {
    canWriteAlloc =
        await ApiService.canWriteSection('farm_attendance', 'allocation');
    canApproveAlloc =
        await ApiService.canApproveSection('farm_attendance', 'allocation');
    canCorrectDay = await ApiService.canCorrect('farm_attendance');
    await _loadMasters();
    await _loadDay();
    if (mounted &&
        _mastersNetFail &&
        (farms.isEmpty || workTypes.isEmpty) &&
        error == null) {
      setState(() => error = AppLocalizations.of(context)!.offNoSaved);
    }
  }

  Future<List?> _getMaster(String path, String allQuery) async {
    try {
      final r = await Api.get('$path$allQuery');
      if (r.statusCode == 200) return jsonDecode(r.body) as List;
    } catch (e) {
      debugPrint('Load master (all=1) error: $e');
    }
    final r = await Api.get(path);
    if (r.statusCode == 200) return jsonDecode(r.body) as List;
    return null;
  }

  Future<void> _loadMasters() async {
    try {
      final results = await Future.wait([
        _getMaster('/farms', '?all=1'),
        _getMaster('/work-types?applies_to=worker', '&all=1'),
      ]);
      if (results[0] != null) farms = results[0]!;
      if (results[1] != null) workTypes = results[1]!;
    } catch (e) {
      debugPrint('Load masters error: $e');
      if (Offline.isNetworkError(e)) _mastersNetFail = true;
    }
  }

  bool get _attOpen =>
      attendanceStatus == 'approved' ||
      (attendanceStatus == 'pending' && pendAtt > 0);

  bool get _canBuild =>
      canWriteAlloc &&
      (allocationStatus == null || allocationStatus == 'returned');

  bool get _tracked =>
      allocationStatus == 'approved' ||
      (allocationStatus == 'pending' && pendAlloc > 0);

  bool get _mayChange => canCorrectDay && _tracked;

  Future<void> _loadDay() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await Api.get('/attendance/day/$_dateStr');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final pc = data['pending_changes'] is Map
            ? data['pending_changes'] as Map
            : {};
        List<Map<String, dynamic>> maps(dynamic v) => [
              for (final e in (v is List ? v : const []))
                if (e is Map) Map<String, dynamic>.from(e)
            ];
        setState(() {
          attendanceStatus = data['attendance_status'];
          allocationStatus = data['allocation_status'];
          allocationAdminNote = data['allocation_admin_note'];
          pendAtt = _int(pc['attendance']);
          pendAlloc = _int(pc['allocation']);
          presentWorkers = maps(data['present_workers']);
          presentWorkers.sort((a, b) => '${a['name'] ?? ''}'
              .toLowerCase()
              .compareTo('${b['name'] ?? ''}'.toLowerCase()));
          leaveWorkers = maps(data['leave_workers']);
          savedAllocations = maps(data['allocations']);
          amendments = maps(data['amendments'])
              .where((a) => a['stage'] == 'allocation')
              .toList();
          sel.removeWhere(
              (id) => !presentWorkers.any((p) => _int(p['worker_id']) == id));
        });
        if (_canBuild && tasks.isEmpty) {
          await _restoreLocalDraft();
          if (tasks.isEmpty) _prefillFromSaved();
          await _normalizeCrops();
        }
        if ((allocationStatus == 'pending' || allocationStatus == 'approved') &&
            Offline.waitingFor(_offlineKey) == null) {
          await _clearLocalDraft();
        }
      } else if (mounted) {
        setState(() => error = Api.responseError(res));
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
        setState(() => loading = false);
      }
    }
  }

  // ── small helpers ──
  Map<String, dynamic>? _person(int id) {
    for (final p in presentWorkers) {
      if (_int(p['worker_id']) == id) return p;
    }
    return null;
  }

  double _wage(Map p) =>
      attNum(p['morning_amount'] ?? p['daily_wage'] ?? p['wage']);
  double _wageOf(int id) {
    final p = _person(id);
    return p == null ? 0 : _wage(p);
  }

  String _nameOf(int id) => tl(context, '${_person(id)?['name'] ?? '#$id'}');

  String _farmName(int? id) {
    for (final f in farms) {
      if (f is Map && f['id'] == id) return tl(context, '${f['name']}');
    }
    return 'Farm not chosen';
  }

  String _workName(_Task t) {
    for (final w in workTypes) {
      if (w is Map && w['id'] == t.workTypeId) return tl(context, '${w['name']}');
    }
    return t.workTypeName ?? 'Work not chosen';
  }

  final Map<int, List> _farmCrops = {};

  Future<List> _cropsOn(int farmId) async {
    if (_farmCrops.containsKey(farmId)) return _farmCrops[farmId]!;
    try {
      final res = await Api.get(
          '/agri/cycles/on-farm?farm_id=$farmId&date=$_dateStr');
      _farmCrops[farmId] = res.statusCode == 200
          ? ((jsonDecode(res.body)['cycles'] as List?) ?? [])
          : [];
    } catch (_) {
      return [];
    }
    return _farmCrops[farmId]!;
  }

  bool _needsCrop(int? farmId) =>
      farmId != null && (_farmCrops[farmId]?.length ?? 0) > 1;

  // A farm with one crop (or none) needs no crop on the task: the server fills it in.
  Future<void> _normalizeCrops() async {
    for (final t in tasks) {
      if (t.farmId == null) continue;
      final c = await _cropsOn(t.farmId!);
      if (c.length <= 1) t.crop = '';
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _cycleFields(String crop, int? farmId) {
    if (!_needsCrop(farmId) || crop.isEmpty) return {};
    final p = crop.split(':');
    return {
      'cycle_type': p[0],
      if (p[0] != 'none' && p.length > 1 && p[1].isNotEmpty)
        'cycle_id': int.tryParse(p[1]),
    };
  }

  // Farm chosen? crop chosen where the farm has several? detail not too long?
  Future<String?> _checkSpec(_Spec s) async {
    if (s.farmId == null) return 'Choose the farm first.';
    await _cropsOn(s.farmId!);
    if (_needsCrop(s.farmId) && s.crop.isEmpty) {
      return 'This farm has more than one crop. Choose the crop, or General farm work.';
    }
    if (s.detail.text.length > 255) {
      return 'Work detail can be at most 255 characters.';
    }
    return null;
  }

  // ── per-person view of the tasks ──
  Map<int, List<(_Task, double)>> get _entries {
    final m = <int, List<(_Task, double)>>{};
    for (final t in tasks) {
      for (final w in t.workers) {
        (m[w.workerId] ??= []).add((t, attNum(w.amount.text)));
      }
    }
    return m;
  }

  String _stateOf(Map<int, List<(_Task, double)>> e, int id) {
    final n = e[id]?.length ?? 0;
    return n == 0 ? 'todo' : (n == 1 ? 'done' : 'split');
  }

  double _totalOf(Map<int, List<(_Task, double)>> e, int id) =>
      attRound2((e[id] ?? []).fold<double>(0, (a, x) => a + x.$2));

  // one task = full pay, several = equal split (then editable)
  void _rebalance(int id) {
    final hits = <_TW>[];
    for (final t in tasks) {
      for (final w in t.workers) {
        if (w.workerId == id) hits.add(w);
      }
    }
    final wage = _wageOf(id);
    if (hits.length == 1) {
      hits[0].amount.text = attFmt(wage);
    } else if (hits.length > 1) {
      final parts = attEqualSplit(wage, hits.length);
      for (var i = 0; i < hits.length; i++) {
        hits[i].amount.text = parts[i];
      }
    }
  }

  void _toggle(int id) => setState(() {
        if (!sel.remove(id)) sel.add(id);
      });

  // ── local draft (a copy kept on this phone while building) ──
  String get _draftKey => 'wa_draft_$_dateStr';

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = tasks
          .where((t) => t.workers.isNotEmpty)
          .map((t) => {
                'farmId': t.farmId,
                'workTypeId': t.workTypeId,
                'workTypeName': t.workTypeName,
                'crop': t.crop,
                'detail': t.detail,
                'workers': [
                  for (final w in t.workers)
                    {'workerId': w.workerId, 'amount': w.amount.text, 'notes': w.notes}
                ],
              })
          .toList();
      if (data.isEmpty) {
        await prefs.remove(_draftKey);
      } else {
        await prefs.setString(_draftKey, jsonEncode(data));
      }
    } catch (_) {}
  }

  Future<void> _clearLocalDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _restoreLocalDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as List;
      final restored = <_Task>[];
      for (final item in data) {
        if (item is! Map || item['workers'] is! List) continue; // an older draft format
        final t = _Task(_uid++)
          ..farmId = item['farmId'] is int ? item['farmId'] : null
          ..workTypeId = item['workTypeId'] is int ? item['workTypeId'] : null
          ..workTypeName = item['workTypeName']?.toString()
          ..crop = '${item['crop'] ?? ''}'
          ..detail = '${item['detail'] ?? ''}';
        for (final w in (item['workers'] as List)) {
          if (w is! Map) continue;
          final id = _int(w['workerId']);
          if (_person(id) == null) continue; // no longer on work today
          t.workers.add(_TW(id, '${w['amount'] ?? ''}', notes: '${w['notes'] ?? ''}'));
        }
        if (t.workers.isNotEmpty) restored.add(t);
      }
      if (mounted && restored.isNotEmpty) setState(() => tasks.addAll(restored));
    } catch (e) {
      debugPrint('Draft restore error: $e');
      await _clearLocalDraft();
    }
  }

  // Rebuilds the tasks from what the server holds (a saved draft, or a day that
  // came back / was reopened): same farm + work + crop = one task.
  void _prefillFromSaved() {
    final by = <String, _Task>{};
    for (final a in savedAllocations) {
      final wid = _int(a['worker_id']);
      if (_person(wid) == null) continue;
      final ct = a['cycle_type']?.toString();
      final crop = ct == null || ct.isEmpty
          ? ''
          : (ct == 'none' ? 'none:x' : '$ct:${a['cycle_id'] ?? ''}');
      final key = '${a['farm_id']}::${a['work_type_id'] ?? ''}::$crop';
      final t = by.putIfAbsent(
          key,
          () => _Task(_uid++)
            ..farmId = _int(a['farm_id'])
            ..workTypeId = a['work_type_id'] == null ? null : _int(a['work_type_id'])
            ..workTypeName = a['work_type_name']?.toString()
            ..crop = crop);
      final d = a['work_detail'];
      if (t.detail.isEmpty && d is String && d.trim().isNotEmpty) t.detail = d.trim();
      t.workers.add(_TW(wid,
          attFmt(attNum(a['total_wage'] ?? a['wage_snapshot'])),
          notes: a['notes']?.toString() ?? ''));
    }
    if (by.isNotEmpty && mounted) setState(() => tasks.addAll(by.values));
  }

  // ── building the tasks ──
  void _after({String? msg}) {
    setState(() {
      error = null;
      notice = msg;
    });
    _persist();
  }

  _Task _taskFor(_Spec s) {
    final key = '${s.farmId}::${s.workTypeId ?? ''}::${s.crop}';
    for (final t in tasks) {
      if (t.key == key) return t;
    }
    final t = _Task(_uid++)
      ..farmId = s.farmId
      ..workTypeId = s.workTypeId
      ..crop = s.crop;
    tasks.add(t);
    return t;
  }

  void _addPeople(_Task t, Iterable<int> ids) {
    for (final id in ids) {
      if (t.workers.any((w) => w.workerId == id)) continue;
      t.workers.add(_TW(id, ''));
      _rebalance(id);
    }
  }

  Future<void> _assignSheet({_Spec? preset, List<int>? presetIds}) async {
    if (preset == null && sel.isEmpty) return;
    final spec = preset ?? _Spec();
    String? err;
    final ids = presetIds ?? sel.toList();
    final ok = await _sheet<bool>((ctx, setSheet) => [
          Text('Assign ${ids.length} ${ids.length == 1 ? 'person' : 'people'} to a task',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
          const SizedBox(height: 4),
          const Text(
              'Each person gets this task. Someone in several tasks has their pay split, you can change the amounts on the Tasks tab.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
          const SizedBox(height: 12),
          _TaskFields(
              spec: spec,
              farms: farms,
              workTypes: workTypes,
              loadCrops: _cropsOn,
              showErr: err != null,
              onChanged: () => setSheet(() => err = null)),
          if (err != null) _errText(err!),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: attGreen,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final e = await _checkSpec(spec);
              if (e != null) {
                setSheet(() => err = e);
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: Text(
                'Add ${ids.length} ${ids.length == 1 ? 'person' : 'people'} to this task',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]);
    if (ok == true && mounted) {
      final t = _taskFor(spec);
      if (spec.detail.text.trim().isNotEmpty) t.detail = spec.detail.text.trim();
      _addPeople(t, ids);
      final msg =
          '${ids.length} ${ids.length == 1 ? 'person' : 'people'} added to ${_workName(t)} · ${_farmName(t.farmId)}.';
      if (preset == null) sel.clear();
      _after(msg: msg);
    }
  }

  // ── Speak the allocation (Oct 2026) ──
  // The phone listens, the server matches the words, this screen shows a review sheet,
  // and only then are the tasks added - exactly like picking people and pressing Assign.
  Future<void> _voiceAllocate() async {
    final draft = await showModalBottomSheet<VoiceDraft>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => VoiceAllocationSheet(dateStr: _dateStr, idaGreen: attGreen),
    );
    if (draft == null || !mounted) return;
    final confirmed = await showModalBottomSheet<List<ConfirmedSection>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupedScanReviewSheet(
        sections: draft.sections,
        unclassified: draft.unclassified,
        candidateWorkers: presentWorkers,
        farms: farms.map<Map<String, dynamic>>((f) => Map<String, dynamic>.from(f as Map)).toList(),
        workTypes: workTypes.map<Map<String, dynamic>>((w) => Map<String, dynamic>.from(w as Map)).toList(),
        idaGreen: attGreen,
        workerIdOf: (w) => _int(w['worker_id']),
        workerNameOf: (w) => '${w['name'] ?? ''}',
        title: 'Review spoken allocation',
        hint: 'check each farm, work and name, then confirm',
        showRate: false,
        requireFarm: true,
      ),
    );
    if (confirmed == null || !mounted) return;
    var added = 0;
    for (final c in confirmed) {
      final ids = c.entries.where((e) => e.selectedWorkerId != null).map((e) => e.selectedWorkerId!).toList();
      if (ids.isEmpty || c.farmId == null) continue;
      final spec = _Spec(farmId: c.farmId, workTypeId: c.workTypeId);
      final needs = await _checkSpec(spec);
      if (needs != null) {
        // a farm with more than one crop: the person picks the crop (or General farm work)
        final before = tasks.fold<int>(0, (a, t) => a + t.workers.length);
        await _assignSheet(preset: spec, presetIds: ids);
        added += tasks.fold<int>(0, (a, t) => a + t.workers.length) - before;
        continue;
      }
      final t = _taskFor(spec);
      _addPeople(t, ids);
      added += ids.length;
    }
    if (!mounted) return;
    _after(msg: added == 0 ? 'Nothing was added.' : '$added ${added == 1 ? 'person' : 'people'} added by voice. Check the Tasks tab, then Draft or Submit.');
  }

  Future<void> _editTask(_Task t) async {
    final spec = _Spec(
        farmId: t.farmId,
        workTypeId: t.workTypeId,
        workTypeName: t.workTypeName,
        crop: t.crop,
        detailText: t.detail);
    String? err;
    final ok = await _sheet<bool>((ctx, setSheet) => [
          const Text('Edit task',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
          const SizedBox(height: 12),
          _TaskFields(
              spec: spec,
              farms: farms,
              workTypes: workTypes,
              loadCrops: _cropsOn,
              showErr: err != null,
              onChanged: () => setSheet(() => err = null)),
          if (err != null) _errText(err!),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: attGreen,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final e = await _checkSpec(spec);
              if (e != null) {
                setSheet(() => err = e);
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Done',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]);
    if (ok == true && mounted) {
      t.farmId = spec.farmId;
      t.workTypeId = spec.workTypeId;
      t.workTypeName = spec.workTypeId == null ? null : t.workTypeName;
      t.crop = spec.crop;
      t.detail = spec.detail.text.trim();
      // now the same as another task? join them
      _Task? other;
      for (final x in tasks) {
        if (!identical(x, t) && x.key == t.key) other = x;
      }
      if (other != null) {
        for (final w in t.workers) {
          if (!other.workers.any((o) => o.workerId == w.workerId)) {
            other.workers.add(w);
          }
        }
        if (other.detail.isEmpty) other.detail = t.detail;
        tasks.remove(t);
        for (final id in other.workers.map((w) => w.workerId).toSet()) {
          _rebalance(id);
        }
      }
      _after();
    }
  }

  void _addSelectedTo(_Task t) {
    final n = sel.length;
    _addPeople(t, sel.toList());
    sel.clear();
    _after(msg: '$n ${n == 1 ? 'person' : 'people'} added to ${_workName(t)} · ${_farmName(t.farmId)}.');
  }

  void _removeFrom(_Task t, int id) {
    t.workers.removeWhere((w) => w.workerId == id);
    _rebalance(id);
    if (t.workers.isEmpty) tasks.remove(t);
    _after();
  }

  Future<void> _deleteTask(_Task t) async {
    if (t.workers.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this task?'),
          content: Text(
              'Its ${t.workers.length} ${t.workers.length == 1 ? 'person goes' : 'people go'} back to "To do".'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Color(0xFFC0392B)))),
          ],
        ),
      );
      if (ok != true) return;
    }
    final ids = t.workers.map((w) => w.workerId).toList();
    tasks.remove(t);
    for (final id in ids) {
      _rebalance(id);
    }
    _after();
  }

  Future<void> _copyYesterday() async {
    if (tasks.any((t) => t.workers.isNotEmpty)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Copy yesterday?'),
          content: const Text(
              "This replaces what you have entered with yesterday's allocation."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      busy = 'copy';
      error = null;
    });
    try {
      final y = widget.attendanceDate.subtract(const Duration(days: 1));
      final res = await Api.get('/attendance/day/${DateFormat('yyyy-MM-dd').format(y)}');
      if (res.statusCode != 200) {
        setState(() => error = Api.responseError(res));
        return;
      }
      final data = jsonDecode(res.body);
      final by = <String, _Task>{};
      for (final a in (data['allocations'] is List ? data['allocations'] as List : [])) {
        if (a is! Map) continue;
        final wid = _int(a['worker_id']);
        if (_person(wid) == null) continue;
        final key = '${a['farm_id']}::${a['work_type_id'] ?? ''}::';
        final t = by.putIfAbsent(
            key,
            () => _Task(_uid++)
              ..farmId = _int(a['farm_id'])
              ..workTypeId = a['work_type_id'] == null ? null : _int(a['work_type_id'])
              ..workTypeName = a['work_type_name']?.toString()
              ..detail = '${a['work_detail'] ?? ''}'.trim());
        if (!t.workers.any((w) => w.workerId == wid)) t.workers.add(_TW(wid, ''));
      }
      if (by.isEmpty) {
        setState(() => error = 'Nothing was allocated yesterday for the people on work today.');
        return;
      }
      setState(() {
        tasks
          ..clear()
          ..addAll(by.values);
        sel.clear();
      });
      for (final p in presentWorkers) {
        _rebalance(_int(p['worker_id']));
      }
      await _normalizeCrops();
      _after(msg: 'Copied ${by.length} ${by.length == 1 ? 'task' : 'tasks'} from yesterday. Check the crop and amounts.');
    } catch (e) {
      if (mounted) setState(() => error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  // ── save draft / submit ──
  List<Map<String, dynamic>> _payload() {
    return [
      for (final t in tasks)
        if (t.workers.isNotEmpty)
          {
            'farm_id': t.farmId,
            'work_type_id': t.workTypeId,
            if (t.detail.trim().isNotEmpty) 'work_detail': t.detail.trim(),
            ..._cycleFields(t.crop, t.farmId),
            'workers': [
              for (final w in t.workers)
                {
                  'worker_id': w.workerId,
                  'amount': w.amount.text.trim().isEmpty
                      ? _wageOf(w.workerId)
                      : attNum(w.amount.text),
                  if (w.notes.trim().isNotEmpty) 'notes': w.notes.trim(),
                }
            ],
          }
    ];
  }

  Future<void> _save(bool submit) async {
    final loc = AppLocalizations.of(context)!;
    setState(() {
      error = null;
      notice = null;
    });
    final e = _entries;
    final todo = presentWorkers
        .where((p) => _stateOf(e, _int(p['worker_id'])) == 'todo')
        .toList();
    if (tasks.any((t) => t.workers.isNotEmpty && t.farmId == null)) {
      setState(() {
        tab = 1;
        error = 'Choose a farm for every task (tap Edit).';
      });
      return;
    }
    for (final t in tasks) {
      if (t.farmId != null) await _cropsOn(t.farmId!);
    }
    if (submit) {
      if (todo.isNotEmpty) {
        setState(() {
          status = 'todo';
          tab = 0;
          error =
              '${todo.length} ${loc.faWaErrStillNeedTask} ${todo.map((p) => tl(context, p['name'])).join(', ')}';
        });
        return;
      }
      if (tasks.every((t) => t.workers.isEmpty)) {
        setState(() => error = loc.faWaErrAddTaskGroup);
        return;
      }
      for (final t in tasks) {
        if (t.workers.isNotEmpty && _needsCrop(t.farmId) && t.crop.isEmpty) {
          setState(() {
            tab = 1;
            error =
                '${_farmName(t.farmId)} has more than one crop. Tap Edit and choose which crop this work was for, or General farm work.';
          });
          return;
        }
      }
    }
    setState(() => busy = submit ? 'submit' : 'draft');
    try {
      final res = await Api.post(
        '/attendance/day/$_dateStr/allocation',
        queueLabel: submit
            ? 'Work allocation ${DateFormat('dd MMM yyyy').format(widget.attendanceDate)}'
            : null,
        queueKey: submit ? _offlineKey : null,
        body: {'allocations': _payload(), if (!submit) 'submit': false},
      );
      if (Api.wasQueued(res)) {
        if (mounted) {
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
        if (submit) {
          final old = Offline.waitingFor(_offlineKey);
          if (old != null) await Offline.discard(old.id);
          setState(() => tasks.clear());
          await _clearLocalDraft();
          await _loadDay();
        } else {
          await _persist();
          if (mounted) {
            setState(() => notice = 'Draft saved. Nothing has gone to the approver yet.');
          }
        }
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (ex) {
      setState(() => error = '${loc.faErrServer}: ${Api.errorText(ex)}');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  // ══════════════════════════ UI helpers ══════════════════════════
  Widget _errText(String t) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(t,
            style: const TextStyle(color: Color(0xFFC0392B), fontSize: 12.5)),
      );

  Future<T?> _sheet<T>(
      List<Widget> Function(BuildContext ctx, StateSetter setSheet) builder) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: builder(ctx, setSheet)),
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: on ? attDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: on ? attDark : const Color(0xFFD5DECC)),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : attDark)),
          ),
        ),
      );

  Widget _box(String text,
          {required Color bg,
          required Color fg,
          IconData icon = Icons.info_outline,
          Widget? action}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(text,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
                if (action != null) action,
              ])),
        ]),
      );

  Widget _card({required Widget child, Color? border}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border ?? const Color(0xFFE0E7D8))),
        child: child,
      );

  Widget _kv(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, color: Color(0xFF5F6A58)))),
          Text(v,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: color ?? attDark)),
        ]),
      );

  Widget _reasonField(
      TextEditingController ctrl, StateSetter setSheet, String? err) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, children: [
        for (final r in const ['Wrong entry', 'Went to other farm', 'Came late'])
          ActionChip(
            label: Text(r, style: const TextStyle(fontSize: 12)),
            onPressed: () => setSheet(() => ctrl.text = r),
          ),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        onChanged: (_) => setSheet(() {}),
        decoration: InputDecoration(
            labelText: 'Reason (required)',
            errorText: err,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
      ),
    ]);
  }

  // The allocation saved on this phone for this date: waiting to be sent,
  // or refused by the server (with its words).
  Widget _offlineNotice(AppLocalizations loc) {
    final e = Offline.waitingFor(_offlineKey);
    if (e == null) return const SizedBox.shrink();
    final failed = e.status == 'failed';
    return _box(
      failed ? loc.offNoticeFailed(e.error) : loc.offAllocSaved,
      bg: failed ? const Color(0xFFFDE8E8) : const Color(0xFFFEF3DC),
      fg: failed ? const Color(0xFFC0392B) : const Color(0xFF92600A),
      icon: failed ? Icons.error_outline : Icons.cloud_upload_outlined,
      action: failed
          ? TextButton(
              onPressed: () => Navigator.pushNamed(context, '/offline'),
              child: Text(loc.offOpenList,
                  style: const TextStyle(fontWeight: FontWeight.w700)))
          : null,
    );
  }

  // ══════════════════════════ build ══════════════════════════
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    Widget body;
    Widget? bottom;
    if (loading) {
      body = const Center(child: CircularProgressIndicator(color: attGreen));
    } else if (!_attOpen) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const OfflineStatusBar(),
            Text(error ?? loc.faWaMustApproveFirst,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: error != null ? Colors.red : Colors.grey.shade600,
                    fontSize: 14)),
          ]),
        ),
      );
    } else if (_canBuild) {
      body = _builderBody(loc);
      bottom = _builderBar();
    } else {
      body = _sheetBody(loc);
      bottom = _bulkBar();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F2),
      appBar: AppBar(
        backgroundColor: attDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
            '${loc.faWaTitle} · ${DateFormat('dd MMM').format(widget.attendanceDate)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (!loading && _attOpen && _canBuild)
            IconButton(
              icon: const Icon(Icons.mic_none),
              tooltip: 'Speak the allocation',
              onPressed: busy == null ? _voiceAllocate : null,
            ),
          if (!loading && _attOpen && _canBuild)
            IconButton(
              icon: const Icon(Icons.content_copy_outlined),
              tooltip: 'Copy yesterday',
              onPressed: busy == null ? _copyYesterday : null,
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Change log',
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AttendanceChangeLogScreen(date: widget.attendanceDate)));
              if (mounted) _loadDay();
            },
          ),
        ],
      ),
      body: Responsive.constrainedContent(context, body),
      bottomNavigationBar: bottom,
    );
  }

  // ══════════════════════════ BUILDER (before / until submitted) ══════════════════════════
  Widget _topMessages(AppLocalizations loc) {
    return Column(children: [
      const OfflineStatusBar(),
      _offlineNotice(loc),
      if (allocationStatus == 'returned')
        _box(
            'The work allocation was returned${(allocationAdminNote ?? '').isNotEmpty ? ': "$allocationAdminNote"' : '.'} Fix it and submit again.',
            bg: const Color(0xFFFDE8E8),
            fg: const Color(0xFFC0392B),
            icon: Icons.undo),
      if (error != null)
        _box(error!,
            bg: const Color(0xFFFDE8E8),
            fg: const Color(0xFFC0392B),
            icon: Icons.error_outline),
      if (notice != null)
        _box(notice!,
            bg: const Color(0xFFE8F5E2),
            fg: const Color(0xFF2C5E17),
            icon: Icons.check_circle_outline),
    ]);
  }

  Widget _builderBody(AppLocalizations loc) {
    final e = _entries;
    final real = tasks.where((t) => t.workers.isNotEmpty).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: _topMessages(loc),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(children: [
          _pill('Workers · ${presentWorkers.length}', tab == 0,
              () => setState(() => tab = 0)),
          _pill('Tasks · $real', tab == 1, () => setState(() => tab = 1)),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          color: attGreen,
          onRefresh: _loadDay,
          child: tab == 0 ? _workersList(e) : _tasksList(e),
        ),
      ),
    ]);
  }

  Widget _workersList(Map<int, List<(_Task, double)>> e) {
    int cnt(String s) =>
        presentWorkers.where((p) => _stateOf(e, _int(p['worker_id'])) == s).length;
    final counts = {
      'todo': cnt('todo'),
      'done': cnt('done'),
      'split': cnt('split'),
      'all': presentWorkers.length,
    };
    final shown = presentWorkers.where((p) {
      final s = q.trim().toLowerCase();
      if (s.isNotEmpty && !'${p['name']}'.toLowerCase().contains(s)) return false;
      return status == 'all' || _stateOf(e, _int(p['worker_id'])) == status;
    }).toList();
    final allOn = shown.isNotEmpty &&
        shown.every((p) => sel.contains(_int(p['worker_id'])));
    void selectShown(bool Function(Map) pred) => setState(() {
          for (final p in shown.where(pred)) {
            sel.add(_int(p['worker_id']));
          }
        });
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final f in const [
              ['todo', 'To do'],
              ['done', 'Done'],
              ['split', 'Split'],
              ['all', 'All']
            ])
              _pill('${f[1]} ${counts[f[0]]}', status == f[0],
                  () => setState(() => status = f[0])),
          ]),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => q = v),
          decoration: InputDecoration(
              hintText: 'Find by name',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          OutlinedButton(
              onPressed: shown.isEmpty
                  ? null
                  : () => allOn
                      ? setState(() => sel.clear())
                      : selectShown((_) => true),
              child: Text(allOn ? 'Clear' : 'Select all')),
          OutlinedButton(
              onPressed: () => selectShown((p) => p['gender'] == 'M'),
              child: const Text('Men')),
          OutlinedButton(
              onPressed: () => selectShown((p) => p['gender'] == 'F'),
              child: const Text('Women')),
        ]),
        if (leaveWorkers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _box(
                '${leaveWorkers.length} paid, not working · ${attRs(leaveWorkers.fold<double>(0, (a, p) => a + _wage(p)))}. They are not allocated; the pay shows as leave with pay.',
                bg: attAmberBg,
                fg: attAmberFg,
                icon: Icons.event_busy_outlined),
          ),
        const SizedBox(height: 6),
        if (presentWorkers.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No one is on work today.'))),
        if (presentWorkers.isNotEmpty && shown.isEmpty)
          Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Text(status == 'todo'
                      ? 'Everyone is allocated.'
                      : 'No one here.'))),
        for (final p in shown) _workerTile(p, e),
      ],
    );
  }

  Widget _workerTile(Map<String, dynamic> p, Map<int, List<(_Task, double)>> e) {
    final id = _int(p['worker_id']);
    final st = _stateOf(e, id);
    final es = e[id] ?? [];
    final tot = _totalOf(e, id);
    final wage = _wage(p);
    final mismatch = st != 'todo' && (tot - wage).abs() > 0.005;
    final on = sel.contains(id);
    final kind = '${p['kind'] ?? 'present'}';
    return InkWell(
      onTap: () => _toggle(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        decoration: BoxDecoration(
            color: on ? const Color(0xFFEEF6E8) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: on ? attGreen : const Color(0xFFE0E7D8))),
        child: Row(children: [
          Checkbox(
              value: on,
              activeColor: attGreen,
              onChanged: (_) => _toggle(id)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(tl(context, '${p['name']}'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (attIsPerm(p)) const AttPermTag(),
                if (attIsPaidAbsent(p)) const AttPaidTag(),
              ]),
              Text(
                  '${p['gender'] == 'F' ? 'Woman' : 'Man'} · ${attRs(wage)}${kind != 'present' ? ' · ${attKindTag(kind).text}' : ''}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (st == 'todo')
              const AttChip(
                  text: 'Not allocated',
                  bg: Color(0xFFFDE6D2),
                  fg: Color(0xFF8C3F06)),
            if (st == 'done')
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: AttChip(
                    text: _workName(es[0].$1),
                    bg: const Color(0xFFE3F0DA),
                    fg: attGreen),
              ),
            if (st == 'split')
              AttChip(
                  text: 'Split in ${es.length}',
                  bg: const Color(0xFFDBE9FB),
                  fg: const Color(0xFF17467F)),
            if (mismatch)
              Text('${attRs(tot)} of ${attRs(wage)}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: attAmberFg)),
          ]),
        ]),
      ),
    );
  }

  Widget _tasksList(Map<int, List<(_Task, double)>> e) {
    final real = tasks.where((t) => t.workers.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        _checkCard(e),
        if (real.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text(
                      'No tasks yet. On the Workers tab, tick the people and press Assign.',
                      textAlign: TextAlign.center))),
        for (final t in real) _taskCard(t, e),
      ],
    );
  }

  Widget _checkCard(Map<int, List<(_Task, double)>> e) {
    final wageTotal = attRound2(
        presentWorkers.fold<double>(0, (a, p) => a + _wage(p)));
    final allocTotal = attRound2(presentWorkers.fold<double>(
        0, (a, p) => a + _totalOf(e, _int(p['worker_id']))));
    final todo = presentWorkers
        .where((p) => _stateOf(e, _int(p['worker_id'])) == 'todo')
        .toList();
    final stillWage = attRound2(todo.fold<double>(0, (a, p) => a + _wage(p)));
    final off = presentWorkers.where((p) {
      final id = _int(p['worker_id']);
      return _stateOf(e, id) != 'todo' &&
          (_totalOf(e, id) - _wage(p)).abs() > 0.005;
    }).toList();
    final byFarm = <String, double>{};
    for (final t in tasks) {
      if (t.workers.isEmpty) continue;
      final a = t.workers.fold<double>(0, (s, w) => s + attNum(w.amount.text));
      final n = _farmName(t.farmId);
      byFarm[n] = (byFarm[n] ?? 0) + a;
    }
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Check before submit',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: attDark)),
        const SizedBox(height: 6),
        _kv('Pay of people on work', attRs(wageTotal)),
        _kv('Allocated so far', attRs(allocTotal)),
        _kv('Still to allocate',
            todo.isEmpty ? 'None' : '${todo.length} · ${attRs(stillWage)}',
            color: todo.isEmpty ? attGreen : const Color(0xFFB3500A)),
        if (off.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF0DBA6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${off.length} ${off.length == 1 ? 'person differs' : 'people differ'} from their pay. This is allowed, the approver will see it.',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: attAmberFg)),
              for (final p in off)
                Text(
                    '${tl(context, '${p['name']}')}: ${attRs(_totalOf(e, _int(p['worker_id'])))} of ${attRs(_wage(p))}',
                    style: const TextStyle(fontSize: 12, color: attAmberFg)),
            ]),
          ),
        if (byFarm.isNotEmpty) ...[
          const Divider(height: 18),
          const Text('BY FARM',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                  color: Color(0xFF6B7280))),
          for (final en in byFarm.entries) _kv(en.key, attRs(attRound2(en.value))),
        ],
      ]),
    );
  }

  Widget _taskCard(_Task t, Map<int, List<(_Task, double)>> e) {
    final total = attRound2(t.workers.fold<double>(0, (s, w) => s + attNum(w.amount.text)));
    final n = t.workers.length;
    return _card(
      border: const Color(0xFFCFE0C2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_workName(t),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: attDark)),
              Text(
                  '${_farmName(t.farmId)} · $n ${n == 1 ? 'person' : 'people'}${t.detail.trim().isNotEmpty ? ' · ${t.detail.trim()}' : ''}',
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280))),
            ]),
          ),
          Text(attRs(total),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 0, children: [
          OutlinedButton.icon(
              onPressed: () => _editTask(t),
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('Edit')),
          if (sel.isNotEmpty)
            OutlinedButton.icon(
                onPressed: () => _addSelectedTo(t),
                icon: const Icon(Icons.add, size: 15),
                label: Text('Add ${sel.length} selected')),
          TextButton.icon(
              onPressed: () => _deleteTask(t),
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: Color(0xFFC0392B)),
              label: const Text('Delete',
                  style: TextStyle(color: Color(0xFFC0392B)))),
        ]),
        const Divider(height: 14),
        for (final w in t.workers) _taskWorkerRow(t, w, e),
      ]),
    );
  }

  Widget _taskWorkerRow(_Task t, _TW w, Map<int, List<(_Task, double)>> e) {
    final p = _person(w.workerId);
    final split = (e[w.workerId]?.length ?? 0) > 1;
    final tot = _totalOf(e, w.workerId);
    final wage = _wageOf(w.workerId);
    final bad = (tot - wage).abs() > 0.005;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(_nameOf(w.workerId),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (p != null && attIsPerm(p)) const AttPermTag(),
              if (split)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: AttChip(
                      text: 'split',
                      bg: Color(0xFFDBE9FB),
                      fg: Color(0xFF17467F)),
                ),
            ]),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: w.amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
              onChanged: (_) {
                setState(() {});
                _persist();
              },
              decoration: InputDecoration(
                  prefixText: '₹',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8))),
            ),
          ),
          IconButton(
            tooltip: 'Take out of this task',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => _removeFrom(t, w.workerId),
          ),
        ]),
        if (split && bad)
          Row(children: [
            Text('${attRs(tot)} of ${attRs(wage)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: attAmberFg)),
            TextButton(
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: () {
                _rebalance(w.workerId);
                _after();
              },
              child: const Text('Split equally',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
      ]),
    );
  }

  Widget _builderBar() {
    final e = _entries;
    final todo = presentWorkers
        .where((p) => _stateOf(e, _int(p['worker_id'])) == 'todo')
        .length;
    final off = presentWorkers.where((p) {
      final id = _int(p['worker_id']);
      return _stateOf(e, id) != 'todo' && (_totalOf(e, id) - _wage(p)).abs() > 0.005;
    }).length;
    final hint = todo > 0
        ? '$todo still to allocate'
        : off > 0
            ? '$off differ from their pay (allowed)'
            : 'Everyone is allocated';
    final working = busy != null;
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(hint,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: todo > 0 ? const Color(0xFF8C3F06) : attGreen)),
            const SizedBox(height: 6),
            Row(children: [
              OutlinedButton.icon(
                onPressed: working ? null : () => _save(false),
                icon: const Icon(Icons.save_outlined, size: 17),
                label: Text(busy == 'draft' ? 'Saving…' : 'Draft'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: sel.isEmpty ? null : _assignSheet,
                  child: Text(sel.isEmpty ? 'Assign…' : 'Assign ${sel.length}…'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: attGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: working ? null : () => _save(true),
                  child: Text(busy == 'submit' ? 'Sending…' : 'Submit',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ══════════════════════════ SHEET (submitted / approved) ══════════════════════════
  List<({Map<String, dynamic> p, int id, List<Map<String, dynamic>> tasks, double wage, double total, Map<String, dynamic>? change})>
      _rows() {
    return [
      for (final p in presentWorkers)
        (() {
          final id = _int(p['worker_id']);
          final ts = savedAllocations.where((a) => _int(a['worker_id']) == id).toList();
          Map<String, dynamic>? ch;
          for (final a in amendments) {
            if (_int(a['worker_id']) == id) ch = a;
          }
          return (
            p: p,
            id: id,
            tasks: ts,
            wage: _wage(p),
            total: attRound2(ts.fold<double>(
                0, (s, a) => s + attNum(a['total_wage'] ?? a['wage_snapshot']))),
            change: ch,
          );
        })()
    ];
  }

  String _taskLine(Map a) {
    final w = '${a['work_type_name'] ?? 'Work'}';
    final d = '${a['work_detail'] ?? ''}'.trim();
    return '${d.isEmpty ? w : '$w — $d'} · ${a['farm_name'] ?? ''}';
  }

  Widget _sheetBody(AppLocalizations loc) {
    final rows = _rows();
    final none = rows.where((r) => r.tasks.isEmpty).length;
    final split = rows.where((r) => r.tasks.length > 1).length;
    final changed = rows.where((r) => r.change != null).length;
    final shown = rows.where((r) {
      final s = q.trim().toLowerCase();
      if (s.isNotEmpty && !'${r.p['name']}'.toLowerCase().contains(s)) return false;
      if (filter == 'none') return r.tasks.isEmpty;
      if (filter == 'split') return r.tasks.length > 1;
      if (filter == 'changed') return r.change != null;
      return true;
    }).toList();
    final allocated = attRound2(rows.fold<double>(0, (s, r) => s + r.total));
    final wageTotal = attRound2(rows.fold<double>(0, (s, r) => s + r.wage));
    final byFarm = <String, double>{};
    for (final a in savedAllocations) {
      final n = '${a['farm_name'] ?? 'Farm ${a['farm_id']}'}';
      byFarm[n] = (byFarm[n] ?? 0) + attNum(a['total_wage'] ?? a['wage_snapshot']);
    }
    final filters = [
      ['all', 'All ${rows.length}'],
      ['none', 'Not allocated $none'],
      ['split', 'Split $split'],
      if (pendAlloc > 0) ['changed', 'Changed $changed'],
    ];
    return RefreshIndicator(
      color: attGreen,
      onRefresh: _loadDay,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: [
          const OfflineStatusBar(),
          _offlineNotice(loc),
          if (error != null)
            _box(error!,
                bg: const Color(0xFFFDE8E8),
                fg: const Color(0xFFC0392B),
                icon: Icons.error_outline),
          if (notice != null)
            _box(notice!,
                bg: const Color(0xFFE8F5E2),
                fg: const Color(0xFF2C5E17),
                icon: Icons.check_circle_outline),
          if (allocationStatus == null)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text(
                        "Work hasn't been allocated yet, and you can't allocate it.",
                        textAlign: TextAlign.center))),
          if (allocationStatus == 'returned')
            _box('Returned for correction: "${allocationAdminNote ?? ''}"',
                bg: const Color(0xFFFDE8E8),
                fg: const Color(0xFFC0392B),
                icon: Icons.undo),
          if (pendAlloc > 0)
            _box(
                '$pendAlloc ${pendAlloc == 1 ? 'change is' : 'changes are'} waiting for re-approval. Everything else stays approved.',
                bg: attAmberBg,
                fg: attAmberFg,
                icon: Icons.schedule),
          if (allocationStatus == 'approved')
            _box(
                'Work allocation approved. This day is complete.${(allocationAdminNote ?? '').isNotEmpty ? ' Earlier changes were rejected: "$allocationAdminNote".' : ''}',
                bg: const Color(0xFFE8F5E2),
                fg: const Color(0xFF2C5E17),
                icon: Icons.check_circle_outline),
          if (allocationStatus == 'pending' && pendAlloc == 0 && !canApproveAlloc)
            _box('Waiting for approval. A reviewer will check this allocation.',
                bg: attAmberBg, fg: attAmberFg, icon: Icons.schedule),
          if (allocationStatus == 'pending' && pendAlloc == 0 && canApproveAlloc)
            _firstDecisionCard(),
          if (allocationStatus == 'pending' && pendAlloc > 0 && canApproveAlloc)
            _changeReviewCard(),
          if (allocationStatus != null) ...[
            if (none > 0)
              _box(
                  '$none ${none == 1 ? 'person is' : 'people are'} on work but not allocated to any task.',
                  bg: const Color(0xFFFFF4EC),
                  fg: const Color(0xFF8C3F06),
                  icon: Icons.warning_amber_rounded,
                  action: _mayChange
                      ? TextButton(
                          onPressed: () => setState(() => filter = 'none'),
                          child: const Text('Show them'))
                      : null),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in filters)
                  _pill(f[1], filter == f[0], () => setState(() => filter = f[0])),
              ]),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                  hintText: 'Search worker',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
            if (_mayChange)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: shown.isEmpty
                      ? null
                      : () => setState(() {
                            final all = shown.every((r) => sel.contains(r.id));
                            if (all) {
                              sel.clear();
                            } else {
                              sel.addAll(shown.map((r) => r.id));
                            }
                          }),
                  child: Text(shown.isNotEmpty && shown.every((r) => sel.contains(r.id))
                      ? 'Clear selection'
                      : 'Select all shown'),
                ),
              ),
            const SizedBox(height: 4),
            if (shown.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No one here.'))),
            for (final r in shown) _sheetRow(r),
            const SizedBox(height: 6),
            _card(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Summary',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: attDark)),
                const SizedBox(height: 4),
                _kv('Pay of people on work', attRs(wageTotal)),
                _kv('Allocated', attRs(allocated)),
                if (byFarm.isNotEmpty) ...[
                  const Divider(height: 16),
                  for (final en in byFarm.entries)
                    _kv(en.key, attRs(attRound2(en.value))),
                ],
              ]),
            ),
            if (!canCorrectDay && _tracked)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                    'You can view this day. Changing an approved day needs the "Correct approved day" permission.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sheetRow(({Map<String, dynamic> p, int id, List<Map<String, dynamic>> tasks, double wage, double total, Map<String, dynamic>? change}) r) {
    final kind = '${r.p['kind'] ?? 'present'}';
    final diff = r.tasks.isNotEmpty && (r.total - r.wage).abs() > 0.005;
    final on = sel.contains(r.id);
    final ch = r.change;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
      decoration: BoxDecoration(
          color: ch != null
              ? const Color(0xFFFFF8E8)
              : (on ? const Color(0xFFEEF6E8) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? attGreen : const Color(0xFFE0E7D8))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_mayChange)
          Checkbox(
              value: on,
              activeColor: attGreen,
              onChanged: (_) => _toggle(r.id))
        else
          const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(tl(context, '${r.p['name']}'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              if (attIsPerm(r.p)) const AttPermTag(),
              const Spacer(),
              Text(attRs(r.total),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
              if (diff)
                Text(' of ${attRs(r.wage)}',
                    style: const TextStyle(fontSize: 11.5, color: attAmberFg)),
            ]),
            if (kind != 'present')
              Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AttChip.kind(kind)),
            if (r.tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: AttChip(
                    text: 'Not allocated',
                    bg: Color(0xFFFDE6D2),
                    fg: Color(0xFF8C3F06)),
              ),
            for (final a in r.tasks)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Expanded(
                      child: Text(_taskLine(a),
                          style: const TextStyle(fontSize: 13))),
                  if (r.tasks.length > 1)
                    Text(attRs(attNum(a['total_wage'] ?? a['wage_snapshot'])),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                ]),
              ),
            if (ch != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${(ch['reason'] ?? '').toString().isNotEmpty ? '"${ch['reason']}"' : ''}${ch['created_by_name'] != null ? ' · ${ch['created_by_name']}' : ''} · waiting approval',
                    style: const TextStyle(fontSize: 12, color: attAmberFg)),
              ),
            if (_mayChange)
              Wrap(spacing: 6, children: [
                TextButton(
                    onPressed: busy != null ? null : () => _changeSheet(r.id),
                    child: const Text('Change')),
                if (ch != null)
                  TextButton.icon(
                      onPressed: busy != null ? null : () => _undo(ch),
                      icon: const Icon(Icons.undo, size: 15),
                      label: const Text('Undo')),
              ]),
          ]),
        ),
      ]),
    );
  }

  Widget? _bulkBar() {
    if (!_mayChange || sel.isEmpty || loading || !_attOpen || _canBuild) return null;
    final rows = _rows().where((r) => sel.contains(r.id)).toList();
    final any = rows.any((r) => r.tasks.isNotEmpty);
    return Material(
      elevation: 8,
      color: attDark,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            Text('${sel.length} selected',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton(
                onPressed: busy != null ? null : _bulkAssign,
                child: const Text('Assign to task…',
                    style: TextStyle(color: Colors.white))),
            TextButton(
                onPressed: (busy != null || !any) ? null : _bulkRemove,
                child: Text('Remove',
                    style: TextStyle(
                        color: any ? Colors.white : Colors.white38))),
            IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFCFE3C0)),
                onPressed: () => setState(() => sel.clear())),
          ]),
        ),
      ),
    );
  }

  // ── approver: first submission ──
  Widget _firstDecisionCard() {
    return _card(
      border: const Color(0xFFEEC46B),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Approve this allocation?',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: attDark)),
        const SizedBox(height: 4),
        const Text(
            'Check who did which work and the amounts. Approve to finish the day. Return sends it back to be corrected, say what is wrong.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC0392B),
                  side: const BorderSide(color: Color(0xFFC0392B))),
              onPressed: busy != null
                  ? null
                  : () async {
                      final n = await attAskReason(context,
                          title: 'Return for correction',
                          help: 'Say what is wrong, so it can be fixed.',
                          confirm: 'Return',
                          danger: true,
                          quick: const []);
                      if (n != null) _decide('reject', note: n);
                    },
              child: const Text('Return'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: attGreen),
              onPressed: busy != null ? null : () => _decide('approve'),
              child: const Text('Approve',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── approver: changes after approval ──
  String _amendText(Map a) {
    final now = a['alloc_now'];
    if (now is! List || now.isEmpty) return 'Taken off work allocation';
    String wn(dynamic id) {
      for (final w in workTypes) {
        if (w is Map && w['id'] == id) return '${w['name']}';
      }
      return 'Work';
    }

    String fn(dynamic id) {
      for (final f in farms) {
        if (f is Map && f['id'] == id) return '${f['name']}';
      }
      return 'farm';
    }

    return now
        .whereType<Map>()
        .map((x) =>
            '${wn(x['work_type_id'])} @ ${fn(x['farm_id'])} ${attRs(attNum(x['amount']))}')
        .join(' + ');
  }

  Widget _changeReviewCard() {
    final blocked = pendAtt > 0;
    return _card(
      border: const Color(0xFFEEC46B),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Changes to approve · ${amendments.length}',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: attDark)),
        if (blocked) ...[
          const SizedBox(height: 6),
          Text(
              'Attendance changes are waiting too. Decide those first (step 1).',
              style: const TextStyle(fontSize: 12.5, color: attAmberFg)),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go to attendance'))),
        ],
        const SizedBox(height: 6),
        for (final a in amendments)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFFAF0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0DBA6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tl(context, '${a['worker_name'] ?? ''}'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text(_amendText(a), style: const TextStyle(fontSize: 13)),
              if ((a['reason'] ?? '').toString().isNotEmpty)
                Text(
                    '"${a['reason']}"${a['created_by_name'] != null ? ' · ${a['created_by_name']}' : ''}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: (busy != null || blocked)
                        ? null
                        : () => _rejectIds([_int(a['id'])]),
                    child: const Text('Reject',
                        style: TextStyle(color: Color(0xFFC0392B)))),
                TextButton(
                    onPressed: (busy != null || blocked)
                        ? null
                        : () => _decide('approve', ids: [_int(a['id'])]),
                    child: const Text('Approve')),
              ]),
            ]),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC0392B),
                  side: const BorderSide(color: Color(0xFFC0392B))),
              onPressed: (busy != null || blocked) ? null : () => _rejectIds(null),
              child: const Text('Reject all'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: attGreen),
              onPressed: (busy != null || blocked) ? null : () => _decide('approve'),
              child: const Text('Approve all',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _rejectIds(List<int>? ids) async {
    final n = await attAskReason(context,
        title: 'Reject ${ids == null ? 'all changes' : 'this change'}',
        help: 'Say why, so the person knows what to fix.',
        confirm: 'Reject',
        danger: true,
        quick: const []);
    if (n != null) _decide('reject', note: n, ids: ids);
  }

  Future<void> _decide(String decision, {String? note, List<int>? ids}) async {
    setState(() {
      busy = 'decide';
      error = null;
    });
    try {
      final res = await Api.patch('/attendance/day/$_dateStr/allocation-decision',
          body: {
            'decision': decision,
            if (note != null) 'note': note,
            if (ids != null) 'ids': ids,
          });
      if (res.statusCode == 200) {
        await _loadDay();
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = '${AppLocalizations.of(context)!.faErrServer}: ${Api.errorText(e)}');
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> _undo(Map<String, dynamic> ch) async {
    setState(() {
      busy = 'save';
      error = null;
    });
    try {
      final res = await Api.post(
          '/attendance/day/$_dateStr/amendments/${_int(ch['id'])}/undo');
      if (res.statusCode == 200) {
        sel.clear();
        await _loadDay();
      } else {
        setState(() => error = Api.responseError(res));
      }
    } catch (e) {
      setState(() => error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<bool> _postAmend(String reason, List<Map<String, dynamic>> changes) async {
    setState(() {
      busy = 'save';
      error = null;
      notice = null;
    });
    try {
      final res = await Api.post('/attendance/day/$_dateStr/allocation-amend',
          body: {'reason': reason, 'changes': changes});
      if (res.statusCode == 200) {
        sel.clear();
        await _loadDay();
        if (mounted) setState(() => notice = 'Saved. The changed people go back to the approver.');
        return true;
      }
      setState(() => error = Api.responseError(res));
    } catch (e) {
      setState(() => error = Api.errorText(e));
    } finally {
      if (mounted) setState(() => busy = null);
    }
    return false;
  }

  Map<String, dynamic> _taskMap(_Spec s, {bool withAmount = false}) => {
        'farm_id': s.farmId,
        'work_type_id': s.workTypeId,
        'work_detail': s.detail.text.trim().isEmpty ? null : s.detail.text.trim(),
        if (withAmount) 'amount': attNum(s.amount.text),
        ..._cycleFields(s.crop, s.farmId),
      };

  // One person: edit their tasks and amounts.
  Future<void> _changeSheet(int workerId) async {
    final r = _rows().firstWhere((x) => x.id == workerId);
    final wage = r.wage;
    final specs = r.tasks.isNotEmpty
        ? [
            for (final a in r.tasks)
              _Spec(
                  farmId: _int(a['farm_id']),
                  workTypeId: a['work_type_id'] == null ? null : _int(a['work_type_id']),
                  workTypeName: a['work_type_name']?.toString(),
                  crop: '${a['cycle_type'] ?? ''}'.isEmpty
                      ? ''
                      : (a['cycle_type'] == 'none'
                          ? 'none:x'
                          : '${a['cycle_type']}:${a['cycle_id'] ?? ''}'),
                  detailText: '${a['work_detail'] ?? ''}',
                  amountText: attFmt(attNum(a['total_wage'] ?? a['wage_snapshot'])))
          ]
        : [_Spec(amountText: attFmt(wage))];
    final reason = TextEditingController();
    String? err;
    final go = await _sheet<bool>((ctx, setSheet) {
      final total = attRound2(specs.fold<double>(0, (s, x) => s + attNum(x.amount.text)));
      final bal = attRound2(wage - total);
      return [
        Text('Change work · ${tl(context, '${r.p['name']}')}',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
        const SizedBox(height: 4),
        Text(
            'Pay for the day is ${attRs(wage)}. Put them in one task, or several (same or different farms) and type the amount for each. It goes back to the approver; the rest of the day stays approved.',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
        const SizedBox(height: 12),
        for (var i = 0; i < specs.length; i++)
          Container(
            key: ObjectKey(specs[i]),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0E7D8))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _TaskFields(
                  key: ObjectKey(specs[i]),
                  spec: specs[i],
                  farms: farms,
                  workTypes: workTypes,
                  loadCrops: _cropsOn,
                  showErr: err != null,
                  onChanged: () => setSheet(() => err = null)),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: specs[i].amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (_) => setSheet(() => err = null),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                        prefixText: '₹',
                        labelText: 'Amount',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8))),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setSheet(() {
                    specs.removeAt(i);
                    if (specs.length == 1) specs[0].amount.text = attFmt(wage);
                  }),
                  icon: const Icon(Icons.close, size: 16),
                  label: Text(specs.length == 1 ? 'Take off work' : 'Remove task'),
                ),
              ]),
            ]),
          ),
        Wrap(spacing: 6, children: [
          OutlinedButton.icon(
            onPressed: () => setSheet(() {
              specs.add(_Spec());
              final p = attEqualSplit(wage, specs.length);
              for (var i = 0; i < specs.length; i++) {
                specs[i].amount.text = p[i];
              }
            }),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add another task'),
          ),
          if (specs.length > 1)
            OutlinedButton(
              onPressed: () => setSheet(() {
                final p = attEqualSplit(wage, specs.length);
                for (var i = 0; i < specs.length; i++) {
                  specs[i].amount.text = p[i];
                }
              }),
              child: const Text('Split equally'),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
            '${attRs(total)} of ${attRs(wage)}${bal.abs() >= 0.005 ? ' · ${bal > 0 ? 'left' : 'over'} ${attRs(bal.abs())}' : ' · balanced'}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: bal.abs() < 0.005 ? attGreen : attAmberFg)),
        const SizedBox(height: 10),
        _reasonField(reason, setSheet, null),
        if (err != null) _errText(err!),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'))),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: attGreen),
              onPressed: () async {
                if (reason.text.trim().isEmpty) {
                  setSheet(() => err = 'Write a short reason first.');
                  return;
                }
                for (final s in specs) {
                  final e = await _checkSpec(s);
                  if (e != null) {
                    setSheet(() => err = e);
                    return;
                  }
                  if (s.amount.text.trim().isEmpty ||
                      double.tryParse(s.amount.text.trim()) == null) {
                    setSheet(() => err = 'Type an amount for every task.');
                    return;
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save change',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ];
    });
    if (go == true && mounted) {
      await _postAmend(reason.text.trim(), [
        {
          'worker_id': workerId,
          'tasks': [for (final s in specs) _taskMap(s, withAmount: true)],
        }
      ]);
    }
  }

  // Many people to one task (replaces what they had, at their full pay).
  Future<void> _bulkAssign() async {
    final ids = sel.toList();
    final spec = _Spec();
    final reason = TextEditingController();
    String? err;
    final replacing = _rows().where((r) => sel.contains(r.id) && r.tasks.isNotEmpty).length;
    final go = await _sheet<bool>((ctx, setSheet) => [
          Text('Assign ${ids.length} ${ids.length == 1 ? 'person' : 'people'} to a task',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
          const SizedBox(height: 4),
          Text(
              'Each person gets this one task for their full pay. ${replacing > 0 ? '$replacing ${replacing == 1 ? 'person' : 'people'} already had work; it is replaced. ' : ''}For a split between tasks, use Change on that person.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
          const SizedBox(height: 12),
          _TaskFields(
              spec: spec,
              farms: farms,
              workTypes: workTypes,
              loadCrops: _cropsOn,
              showErr: err != null,
              onChanged: () => setSheet(() => err = null)),
          const SizedBox(height: 10),
          _reasonField(reason, setSheet, null),
          if (err != null) _errText(err!),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: attGreen,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () async {
              final e = await _checkSpec(spec);
              if (e != null) {
                setSheet(() => err = e);
                return;
              }
              if (reason.text.trim().isEmpty) {
                setSheet(() => err = 'Write a short reason first.');
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Assign',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ]);
    if (go == true && mounted) {
      final task = _taskMap(spec);
      await _postAmend(reason.text.trim(), [
        for (final id in ids) {'worker_id': id, 'tasks': [task]}
      ]);
    }
  }

  Future<void> _bulkRemove() async {
    final ids = _rows()
        .where((r) => sel.contains(r.id) && r.tasks.isNotEmpty)
        .map((r) => r.id)
        .toList();
    if (ids.isEmpty) return;
    final reason = await attAskReason(context,
        title: 'Remove ${ids.length == 1 ? _nameOf(ids.first) : '${ids.length} people'} from work',
        help:
            "Their work is taken out of the allocation. They stay on today's attendance, so allocate them again or remove them in step 1.",
        confirm: 'Remove from work',
        danger: true,
        quick: const ['Wrong entry', 'Went home', 'Not well']);
    if (reason == null || !mounted) return;
    await _postAmend(reason, [
      for (final id in ids) {'worker_id': id, 'tasks': <Map<String, dynamic>>[]}
    ]);
  }
}
