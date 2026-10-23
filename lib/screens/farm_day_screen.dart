// lib/screens/farm_day_screen.dart
//
// "Today's work": farm attendance + work allocation on ONE screen, ONE save, ONE approval.
//
//   * You add workers to a farm + work. Anyone placed is present; anyone not placed is absent.
//   * A worker can be split between two places in rupees (e.g. 200 + 100 of 300), or marked half day.
//   * Submit sends the whole day to the approver, who approves or sends back the whole day at once.
//
// It sits BESIDE the old Attendance / Work allocation screens and saves to the same data, so
// reports and the old "Change after approval" flow keep working. Server: /farm-day (routes/farmDay.js).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_client.dart';
import '../services/responsive.dart';
import '../widgets/att_parts.dart';

const Color _bgMen = Color(0xFFF1F6EC);
const Color _bgWomen = Color(0xFFFBF2F4);
const Color _line = Color(0xFFCFDDC3);
const Color _muted = Color(0xFF5F6A58);

class _Line {
  final int w;
  double a;
  _Line(this.w, this.a);
}

class _Task {
  final int id;
  int farmId;
  int workId;
  String? cycleType; // 'seasonal' | 'orchard' | 'none' | null
  int? cycleId;
  String detail;
  final List<_Line> lines;
  _Task({
    required this.id,
    required this.farmId,
    required this.workId,
    this.cycleType,
    this.cycleId,
    this.detail = '',
    List<_Line>? lines,
  }) : lines = lines ?? [];

  bool sameAs(int farm, int work, String? ct, int? ci) =>
      farmId == farm && workId == work && cycleType == ct && cycleId == ci;
}

class _Opt {
  final int id;
  final String label;
  const _Opt(this.id, this.label);
}

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

class FarmDayScreen extends StatefulWidget {
  final String? initialDate; // yyyy-MM-dd
  const FarmDayScreen({super.key, this.initialDate});

  @override
  State<FarmDayScreen> createState() => _FarmDayScreenState();
}

class _FarmDayScreenState extends State<FarmDayScreen> {
  late DateTime _date;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  // from the server
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _farms = [];
  List<Map<String, dynamic>> _works = [];
  List<int> _recentFarms = [];
  List<int> _recentWorks = [];
  String? _status; // null | pending | approved | returned | mixed
  String? _adminNote;
  String? _lockReason;
  bool _canEdit = false;
  bool _canApprove = false;
  List<Map<String, dynamic>> _notPlacedOld = [];

  // the day being built
  final List<_Task> _tasks = [];
  int _nextId = 1;
  final Set<int> _collapsed = {};
  int? _farmFilter;

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse(widget.initialDate ?? '') ?? DateTime.now();
    _date = DateTime(_date.year, _date.month, _date.day);
    _load();
  }

  // ── lookups ─────────────────────────────────────────────────────────
  Map<String, dynamic>? _worker(int id) {
    for (final w in _workers) {
      if (_i(w['id']) == id) return w;
    }
    return null;
  }

  String _workerName(int id) => '${_worker(id)?['name'] ?? 'Worker $id'}';
  double _wage(int id) => _d(_worker(id)?['daily_wage']);
  bool _isWoman(int id) => '${_worker(id)?['gender']}' == 'F';

  Map<String, dynamic>? _farm(int id) {
    for (final f in _farms) {
      if (_i(f['id']) == id) return f;
    }
    return null;
  }

  String _farmName(int id) => '${_farm(id)?['name'] ?? 'Farm $id'}';

  String _workName(int id) {
    for (final w in _works) {
      if (_i(w['id']) == id) return '${w['name']}';
    }
    return 'Work $id';
  }

  List<Map<String, dynamic>> _cropsOf(int farmId) =>
      ((_farm(farmId)?['crops'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  String? _cropLabel(_Task t) {
    if (t.cycleType == 'none') return 'General farm work';
    if (t.cycleType == null || t.cycleId == null) return null;
    for (final c in _cropsOf(t.farmId)) {
      if ('${c['cycle_type']}' == t.cycleType && _i(c['cycle_id']) == t.cycleId) return '${c['label']}';
    }
    return null;
  }

  // ── load ────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = Map<String, dynamic>.from(await Api.json('GET', '/farm-day/$_dateStr') as Map);
      List<Map<String, dynamic>> list(String k) =>
          ((r[k] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _workers = list('workers');
      _farms = list('farms');
      _works = list('work_types');
      _recentFarms = ((r['recent_farm_ids'] as List?) ?? []).map(_i).toList();
      _recentWorks = ((r['recent_work_type_ids'] as List?) ?? []).map(_i).toList();
      _status = r['status'] as String?;
      _adminNote = r['admin_note'] as String?;
      _lockReason = r['lock_reason'] as String?;
      _canEdit = r['can_edit'] == true;
      _canApprove = r['can_approve'] == true;
      _notPlacedOld = list('present_not_placed');
      _tasks.clear();
      for (final t in (r['tasks'] as List? ?? [])) {
        final task = _Task(
          id: _nextId++,
          farmId: _i(t['farm_id']),
          workId: _i(t['work_type_id']),
          cycleType: t['cycle_type'] as String?,
          cycleId: t['cycle_id'] == null ? null : _i(t['cycle_id']),
          detail: '${t['work_detail'] ?? ''}',
        );
        for (final l in (t['lines'] as List? ?? [])) {
          task.lines.add(_Line(_i(l['worker_id']), _d(l['amount'])));
        }
        _tasks.add(task);
      }
      _collapsed.clear();
      _farmFilter = null;
      _dirty = false;
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Api.errorText(e);
      });
    }
  }

  // ── derived ─────────────────────────────────────────────────────────
  Set<int> get _placed => {for (final t in _tasks) for (final l in t.lines) l.w};

  double get _total => _tasks.fold(0.0, (s, t) => s + t.lines.fold(0.0, (a, l) => a + l.a));

  List<({_Task task, _Line line})> _placements(int wid) => [
        for (final t in _tasks)
          for (final l in t.lines)
            if (l.w == wid) (task: t, line: l)
      ];

  bool get _editable => _canEdit;

  void _touch() {
    _dirty = true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── adding people ───────────────────────────────────────────────────
  // The worker is already at one other place: the day is shared between the two.
  void _addWorkers(_Task t, List<int> ids) {
    final skipped = <String>[];
    for (final wid in ids) {
      if (t.lines.any((l) => l.w == wid)) continue;
      final wage = _wage(wid);
      final others = _placements(wid);
      if (others.isEmpty) {
        t.lines.add(_Line(wid, wage));
      } else if (others.length == 1) {
        final existing = others.first.line;
        if (existing.a >= wage && wage > 0) {
          final half = attRound2(wage / 2);
          existing.a = attRound2(wage - half);
          t.lines.add(_Line(wid, half));
        } else {
          final rest = attRound2(wage - existing.a);
          t.lines.add(_Line(wid, rest > 0 ? rest : 0));
        }
      } else {
        skipped.add(_workerName(wid));
      }
    }
    _touch();
    if (skipped.isNotEmpty) _toast('${skipped.join(', ')}: already shared between two places. Change it from the name.');
  }

  Future<void> _newTask() async {
    if (!_editable) return;
    final farmOpts = [for (final f in _farms) _Opt(_i(f['id']), '${f['name']}')];
    final workOpts = [for (final w in _works) _Opt(_i(w['id']), '${w['name']}')];
    if (farmOpts.isEmpty || workOpts.isEmpty) {
      _toast('Add farms and work types in Farm Masters first.');
      return;
    }
    final farmId = await _choose(
      title: 'New task: which farm?',
      subtitle: 'Step 1 of 3',
      items: farmOpts,
      recentIds: _recentFarms,
      allLabel: 'All farms',
    );
    if (farmId == null || !mounted) return;
    final workId = await _choose(
      title: 'New task: which work?',
      subtitle: 'Step 2 of 3 · ${_farmName(farmId)}',
      items: workOpts,
      recentIds: _recentWorks,
      allLabel: 'All work (tractor work left out)',
    );
    if (workId == null || !mounted) return;

    String? cType;
    int? cId;
    final crops = _cropsOf(farmId);
    if (crops.length == 1) {
      cType = '${crops.first['cycle_type']}';
      cId = _i(crops.first['cycle_id']);
    } else if (crops.length > 1) {
      final opts = [for (var k = 0; k < crops.length; k++) _Opt(k, '${crops[k]['label']}'), _Opt(crops.length, 'General farm work')];
      final k = await _choose(
        title: 'Which crop?',
        subtitle: '${_farmName(farmId)} has more than one crop',
        items: opts,
        recentIds: const [],
        allLabel: 'Crops on this farm',
        search: false,
      );
      if (k == null || !mounted) return;
      if (k == crops.length) {
        cType = 'none';
      } else {
        cType = '${crops[k]['cycle_type']}';
        cId = _i(crops[k]['cycle_id']);
      }
    }

    _Task? existing;
    for (final t in _tasks) {
      if (t.sameAs(farmId, workId, cType, cId)) existing = t;
    }
    final target = existing ?? _Task(id: _nextId++, farmId: farmId, workId: workId, cycleType: cType, cycleId: cId);
    final ids = await _pickWorkers(target, step3: true);
    if (ids == null || ids.isEmpty || !mounted) return;
    setState(() {
      if (existing == null) _tasks.add(target);
      _addWorkers(target, ids);
      _farmFilter = null;
    });
  }

  Future<void> _addToTask(_Task t) async {
    final ids = await _pickWorkers(t);
    if (ids == null || ids.isEmpty || !mounted) return;
    setState(() => _addWorkers(t, ids));
  }

  Future<int?> _choose({
    required String title,
    required String subtitle,
    required List<_Opt> items,
    required List<int> recentIds,
    required String allLabel,
    bool search = true,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ChooseSheet(
        title: title,
        subtitle: subtitle,
        items: items,
        recentIds: recentIds,
        allLabel: allLabel,
        search: search,
      ),
    );
  }

  Future<List<int>?> _pickWorkers(_Task t, {bool step3 = false}) {
    // 0 = free, 1 = already in this task, 2 = at one other place (day will be split), 3 = already split (blocked)
    int status(int wid) {
      if (t.lines.any((l) => l.w == wid)) return 1;
      final others = _placements(wid).where((e) => e.task != t).toList();
      if (others.isEmpty) return 0;
      return others.length == 1 ? 2 : 3;
    }

    String noteOf(int wid) {
      switch (status(wid)) {
        case 1:
          return 'already here';
        case 2:
          final e = _placements(wid).firstWhere((e) => e.task != t);
          return 'at ${_farmName(e.task.farmId)} (will split)';
        case 3:
          return 'split in two places';
        default:
          return 'free';
      }
    }

    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _WorkersSheet(
        title: '${_farmName(t.farmId)} · ${_workName(t.workId)}',
        subtitle: step3 ? 'Step 3 of 3 · choose workers' : 'Choose workers',
        workers: _workers,
        statusOf: status,
        noteOf: noteOf,
      ),
    );
  }

  // ── worker sheet: split / half day / change amount / remove ─────────
  Future<void> _workerSheet(int wid) async {
    if (!_editable) return;
    int? target;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final ls = _placements(wid);
        if (ls.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          });
          return const SizedBox(height: 40);
        }
        final wage = _wage(wid);
        final split = ls.length >= 2;
        final single = ls.length == 1;
        final total = ls.fold(0.0, (s, e) => s + e.line.a);
        final others = single ? _tasks.where((t) => t != ls.first.task).toList() : <_Task>[];
        _Task? tgt;
        for (final t in others) {
          if (t.id == target) tgt = t;
        }

        void change(VoidCallback fn) {
          setState(fn);
          _touch();
          setSheet(() {});
        }

        void shift(int idx, double delta) {
          if (ls.length != 2) return;
          final a = ls[idx].line.a + delta;
          if (a < 50 || a > total - 50) return;
          change(() {
            ls[idx].line.a = attRound2(a);
            ls[1 - idx].line.a = attRound2(total - a);
          });
        }

        Widget outBtn(String label, VoidCallback onTap, {Color color = attDark, Color border = const Color(0xFFB8C9AC)}) =>
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  side: BorderSide(color: border, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                onPressed: onTap,
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
            );

        final presets = <List<double>>[];
        if (single && tgt != null) {
          final half = attRound2(total / 2);
          presets.add([attRound2(total - half), half]);
          if (total >= 200) {
            presets.add([attRound2(total - 100), 100]);
            presets.add([100, attRound2(total - 100)]);
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_workerName(wid), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: attDark)),
                    Text("Day's pay ${attRs(wage)}", style: const TextStyle(fontSize: 12.5, color: _muted)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
              ]),
              const SizedBox(height: 8),
              for (var k = 0; k < ls.length; k++)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFF4F7F2), borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_farmName(ls[k].task.farmId), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(_workName(ls[k].task.workId), style: const TextStyle(fontSize: 12, color: _muted)),
                      ]),
                    ),
                    if (split) _stepBtn(Icons.remove, () => shift(k, -50)),
                    Container(
                      constraints: const BoxConstraints(minWidth: 64),
                      alignment: Alignment.center,
                      child: Text(attRs(ls[k].line.a), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    if (split) _stepBtn(Icons.add, () => shift(k, 50)),
                  ]),
                ),
              if (single && others.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text('Also worked at (split the day)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF34422D))),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in others)
                    ChoiceChip(
                      label: Text('${_farmName(t.farmId)} · ${_workName(t.workId)}'),
                      selected: target == t.id,
                      onSelected: (_) {
                        target = t.id;
                        setSheet(() {});
                      },
                    ),
                ]),
                if (tgt != null) ...[
                  const SizedBox(height: 8),
                  Text('${_farmName(ls.first.task.farmId)} gets the first amount, ${_farmName(tgt.farmId)} the second.',
                      style: const TextStyle(fontSize: 12, color: _muted)),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (var k = 0; k < presets.length; k++) ...[
                      if (k > 0) const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: attGreen,
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          onPressed: () {
                            final p = presets[k];
                            final to = tgt!;
                            change(() {
                              ls.first.line.a = p[0];
                              to.lines.add(_Line(wid, p[1]));
                            });
                          },
                          child: FittedBox(
                            child: Text('${attRs(presets[k][0])} + ${attRs(presets[k][1])}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ],
                const SizedBox(height: 8),
                const Text('For another split, choose the place, tap a preset, then fine-tune with − / + (₹50 steps).',
                    style: TextStyle(fontSize: 11.5, color: _muted)),
              ],
              if (single && others.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('Add this person to another task to split the day between two places.',
                      style: TextStyle(fontSize: 11.5, color: _muted)),
                ),
              const SizedBox(height: 10),
              Row(children: [
                if (split) ...[
                  outBtn('Back to one place', () {
                    change(() {
                      final keep = ls.first;
                      keep.line.a = attRound2(total);
                      for (var k = 1; k < ls.length; k++) {
                        ls[k].task.lines.remove(ls[k].line);
                      }
                      _tasks.removeWhere((t) => t.lines.isEmpty);
                    });
                  }),
                  const SizedBox(width: 8),
                ],
                if (single && wage > 0 && (ls.first.line.a - wage / 2).abs() > 0.01) ...[
                  outBtn('Half day', () => change(() => ls.first.line.a = attRound2(wage / 2))),
                  const SizedBox(width: 8),
                ],
                if (single && wage > 0 && (ls.first.line.a - wage).abs() > 0.01) ...[
                  outBtn('Full day', () => change(() => ls.first.line.a = wage)),
                  const SizedBox(width: 8),
                ],
                if (single) ...[
                  outBtn('Amount', () async {
                    final v = await _askAmount(ctx, ls.first.line.a);
                    if (v != null) change(() => ls.first.line.a = v);
                  }),
                  const SizedBox(width: 8),
                ],
                outBtn('Remove', () {
                  change(() {
                    for (final t in _tasks) {
                      t.lines.removeWhere((l) => l.w == wid);
                    }
                    _tasks.removeWhere((t) => t.lines.isEmpty);
                  });
                }, color: const Color(0xFF9E2419), border: const Color(0xFFEFB9B3)),
              ]),
            ]),
          ),
        );
      }),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: 44,
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: const BorderSide(color: Color(0xFFB8C9AC), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onTap,
            child: Icon(icon, color: attDark),
          ),
        ),
      );

  Future<double?> _askAmount(BuildContext ctx, double current) async {
    final c = TextEditingController(text: attFmt(current));
    final v = await showDialog<double>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Amount for the day'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '₹ ', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final n = double.tryParse(c.text.trim());
              if (n == null || n <= 0) return;
              Navigator.pop(dctx, attRound2(n));
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
    c.dispose();
    return v;
  }

  // ── work detail remark ──────────────────────────────────────────────
  Future<void> _editDetail(_Task t) async {
    List<String> options = [];
    for (final w in _works) {
      if (_i(w['id']) == t.workId) options = ((w['detail_options'] as List?) ?? []).map((e) => '$e').toList();
    }
    final c = TextEditingController(text: t.detail);
    final v = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Work detail'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              maxLength: 255,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'Optional remark for this task', border: OutlineInputBorder()),
            ),
            if (options.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in options) ActionChip(label: Text(o), onPressed: () => c.text = o),
              ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (v != null && mounted) {
      setState(() {
        t.detail = v;
        _touch();
      });
    }
  }

  Future<void> _removeTask(_Task t) async {
    final ok = await _confirm('Remove this task?', 'Everyone in ${_farmName(t.farmId)} · ${_workName(t.workId)} will be taken off it.', 'Remove');
    if (ok != true || !mounted) return;
    setState(() {
      _tasks.remove(t);
      _touch();
    });
  }

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: Text(yes)),
          ],
        ),
      );

  // ── save / submit / decide ──────────────────────────────────────────
  List<Map<String, dynamic>> _payload() => [
        for (final t in _tasks)
          {
            'farm_id': t.farmId,
            'work_type_id': t.workId,
            'cycle_type': t.cycleType,
            'cycle_id': t.cycleId,
            'work_detail': t.detail,
            'lines': [
              for (final l in t.lines) {'worker_id': l.w, 'amount': l.a}
            ],
          }
      ];

  Future<void> _save({required bool submit}) async {
    if (_busy) return;
    if (submit) {
      if (_tasks.isEmpty) {
        _toast('Add workers to a task first.');
        return;
      }
      for (final t in _tasks) {
        for (final l in t.lines) {
          if (l.a <= 0) {
            _toast('${_workerName(l.w)} has no amount. Tap the name and set it.');
            return;
          }
        }
        if (_cropsOf(t.farmId).length > 1 && t.cycleType == null) {
          _toast('${_farmName(t.farmId)} has more than one crop. Remove the task and add it again to pick the crop.');
          return;
        }
      }
      final men = _placed.where((w) => !_isWoman(w)).length;
      final women = _placed.length - men;
      final ok = await _confirm('Send for approval?',
          '${_placed.length} workers ($men men, $women women) · ${attRs(_total)}\n${_tasks.length} task${_tasks.length == 1 ? '' : 's'}. The approver decides the whole day at once.', 'Submit');
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await Api.json('POST', '/farm-day/$_dateStr/save', body: {'tasks': _payload(), 'submit': submit});
      _toast(submit ? 'Sent for approval' : 'Draft saved');
      await _load();
    } catch (e) {
      _toast(Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(bool approve) async {
    String? note;
    if (!approve) {
      final c = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Send back'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                if (c.text.trim().isEmpty) return;
                Navigator.pop(dctx, c.text.trim());
              },
              child: const Text('Send back'),
            ),
          ],
        ),
      );
      c.dispose();
      if (note == null) return;
    } else {
      final ok = await _confirm('Approve the day?', '${_placed.length} workers · ${attRs(_total)}', 'Approve');
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await Api.json('PATCH', '/farm-day/$_dateStr/decision', body: {'decision': approve ? 'approve' : 'reject', if (note != null) 'note': note});
      _toast(approve ? 'Approved' : 'Sent back');
      await _load();
    } catch (e) {
      _toast(Api.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    if (_dirty) {
      final ok = await _confirm('Leave unsaved work?', 'What you added on this day has not been saved.', 'Discard');
      if (ok != true) return;
    }
    setState(() => _date = DateTime(d.year, d.month, d.day));
    await _load();
  }

  Future<void> _onBack() async {
    if (!_dirty || !_editable) {
      Navigator.of(context).pop();
      return;
    }
    final r = await showDialog<String>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Unsaved work'),
        content: const Text('Save what you have as a draft before leaving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, 'stay'), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(dctx, 'discard'), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(dctx, 'save'), child: const Text('Save draft')),
        ],
      ),
    );
    if (r == 'discard') {
      if (mounted) Navigator.of(context).pop();
    } else if (r == 'save') {
      await _save(submit: false);
      if (mounted && !_dirty) Navigator.of(context).pop();
    }
  }

  // ── build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8F3),
        appBar: AppBar(
          backgroundColor: attGreen,
          foregroundColor: Colors.white,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Today's work", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(DateFormat('EEE, d MMM yyyy').format(_date), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            IconButton(tooltip: 'Change date', icon: const Icon(Icons.calendar_month), onPressed: _busy ? null : _pickDate),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _busy ? null : _confirmReload),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _load, child: const Text('Try again')),
                      ]),
                    ),
                  )
                : Responsive.constrainedContent(
                    context,
                    Column(children: [
                      Expanded(child: _body()),
                      _bottomBar(),
                    ]),
                    maxWidth: 820,
                  ),
      ),
    );
  }

  Future<void> _confirmReload() async {
    if (_dirty) {
      final ok = await _confirm('Reload?', 'Unsaved changes on this screen will be lost.', 'Reload');
      if (ok != true) return;
    }
    await _load();
  }

  Widget _body() {
    final placed = _placed;
    final men = placed.where((w) => !_isWoman(w)).length;
    final women = placed.length - men;
    final farmIds = <int>[];
    for (final t in _tasks) {
      if (!farmIds.contains(t.farmId)) farmIds.add(t.farmId);
    }
    final shown = _tasks.where((t) => _farmFilter == null || t.farmId == _farmFilter).toList();
    final notPlaced = [
      for (final w in _workers)
        if (!placed.contains(_i(w['id'])) && !(w['paid_when_absent'] == true)) '${w['name']}'
    ];
    final onLeave = [
      for (final w in _workers)
        if (!placed.contains(_i(w['id'])) && w['paid_when_absent'] == true) '${w['name']}'
    ];

    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 16), children: [
      _statusBanner(),
      if (_notPlacedOld.isNotEmpty)
        _note(
          'Marked present in the old screen but not placed here: ${_notPlacedOld.map((e) => e['name']).join(', ')}. '
          'Add them to a task, or they will count as absent when you save.',
          attAmberBg,
          attAmberFg,
        ),
      // counters
      Row(children: [
        _stat('Working', '${placed.length}'),
        _stat('Men', '$men'),
        _stat('Women', '$women'),
        _stat('Total', attRs(_total)),
      ]),
      const SizedBox(height: 10),
      if (farmIds.length >= 2)
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _filterChip('All (${_tasks.length})', _farmFilter == null, () => setState(() => _farmFilter = null)),
            for (final f in farmIds)
              _filterChip('${_farmName(f)} (${_tasks.where((t) => t.farmId == f).length})', _farmFilter == f, () => setState(() => _farmFilter = f)),
          ]),
        ),
      if (_tasks.isEmpty)
        Container(
          margin: const EdgeInsets.only(top: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
          child: Column(children: [
            const Icon(Icons.agriculture_outlined, size: 40, color: attGreen),
            const SizedBox(height: 8),
            Text(_editable ? 'No work added yet' : 'Nothing was recorded for this day', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text(_editable ? 'Tap "+ New task", choose the farm and the work, then add the workers.' : '', textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
          ]),
        ),
      for (final t in shown) _taskCard(t),
      const SizedBox(height: 8),
      if (_tasks.isNotEmpty || _workers.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Not placed today (${notPlaced.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: attDark)),
            const SizedBox(height: 4),
            Text(notPlaced.isEmpty ? 'nobody' : notPlaced.join(', '), style: const TextStyle(fontSize: 12.5, color: _muted)),
            if (onLeave.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Leave with pay: ${onLeave.join(', ')}', style: const TextStyle(fontSize: 12.5, color: attAmberFg)),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _statusBanner() {
    String? text;
    Color bg = const Color(0xFFEFF3EA);
    Color fg = attDark;
    switch (_status) {
      case 'pending':
        text = 'Waiting for approval';
        bg = attAmberBg;
        fg = attAmberFg;
        break;
      case 'approved':
        text = 'Approved';
        bg = const Color(0xFFE3F0DA);
        break;
      case 'returned':
        text = 'Sent back${_adminNote == null ? '' : ': $_adminNote'}';
        bg = const Color(0xFFFDE8E6);
        fg = const Color(0xFF9E2419);
        break;
      case 'mixed':
        text = 'Part of this day was handled in the old screens';
        break;
    }
    final extra = (_lockReason != null && _status != 'returned') ? _lockReason : null;
    if (text == null && extra == null) return const SizedBox.shrink();
    return _note([if (text != null) text, if (extra != null) extra].join('\n'), bg, fg);
  }

  Widget _note(String text, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _line)),
          child: Column(children: [
            FittedBox(child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: attDark))),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ]),
        ),
      );

  Widget _filterChip(String label, bool on, VoidCallback tap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: tap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? attGreen : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: on ? attGreen : _line, width: 1.5),
            ),
            child: Text(label, style: TextStyle(color: on ? Colors.white : attDark, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ),
      );

  Widget _taskCard(_Task t) {
    final collapsed = _collapsed.contains(t.id);
    final sum = t.lines.fold(0.0, (s, l) => s + l.a);
    final crop = _cropLabel(t);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => collapsed ? _collapsed.remove(t.id) : _collapsed.add(t.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_farmName(t.farmId), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: attDark)),
                  Text(_workName(t.workId) + (crop == null ? '' : ' · $crop'), style: const TextStyle(fontSize: 13, color: _muted)),
                  if (collapsed)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(t.lines.map((l) => _workerName(l.w)).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                    ),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${t.lines.length} workers', style: const TextStyle(fontSize: 12, color: _muted)),
                Text(attRs(sum), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              ]),
              Icon(collapsed ? Icons.expand_more : Icons.expand_less, color: attDark),
            ]),
          ),
        ),
        if (!collapsed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [for (final l in t.lines) _workerChip(l)]),
              if (t.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Detail: ${t.detail}', style: const TextStyle(fontSize: 12.5, color: _muted)),
                ),
              if (_editable)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    TextButton.icon(onPressed: () => _addToTask(t), icon: const Icon(Icons.person_add_alt_1, size: 18), label: const Text('Add workers')),
                    TextButton(onPressed: () => _editDetail(t), child: Text(t.detail.isEmpty ? 'Work detail' : 'Edit detail')),
                    TextButton(onPressed: () => _removeTask(t), child: const Text('Remove task', style: TextStyle(color: Color(0xFF9E2419)))),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _workerChip(_Line l) {
    final wage = _wage(l.w);
    final partial = (l.a - wage).abs() > 0.01;
    final shared = _placements(l.w).length > 1;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _editable ? () => _workerSheet(l.w) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isWoman(l.w) ? _bgWomen : _bgMen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: l.a <= 0 ? Colors.red : (partial ? const Color(0xFFE8CF93) : _line)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_workerName(l.w), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(attRs(l.a), style: TextStyle(fontSize: 12.5, fontWeight: partial ? FontWeight.w800 : FontWeight.w500, color: partial ? attAmberFg : _muted)),
          if (shared) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.call_split, size: 14, color: attAmberFg)),
        ]),
      ),
    );
  }

  Widget _bottomBar() {
    Widget wrap(Widget child) => Container(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _line))),
          child: child,
        );
    if (_editable) {
      return wrap(Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: const BorderSide(color: attGreen, width: 1.5)),
            onPressed: _busy || !_dirty ? null : () => _save(submit: false),
            child: const Text('Draft', style: TextStyle(color: attDark, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: const BorderSide(color: attGreen, width: 1.5)),
            onPressed: _busy ? null : _newTask,
            icon: const Icon(Icons.add, color: attDark),
            label: const Text('New task', style: TextStyle(color: attDark, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: attGreen, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : () => _save(submit: true),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ]));
    }
    if (_canApprove) {
      return wrap(Row(children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), side: const BorderSide(color: Color(0xFFEFB9B3), width: 1.5)),
            onPressed: _busy ? null : () => _decide(false),
            child: const Text('Send back', style: TextStyle(color: Color(0xFF9E2419), fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: attGreen, minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : () => _decide(true),
            child: const Text('Approve', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ]));
    }
    return wrap(Text(
      _lockReason ?? 'View only',
      textAlign: TextAlign.center,
      style: const TextStyle(color: _muted, fontSize: 13),
    ));
  }
}

// ── pick one thing from a list (farm / work / crop) ────────────────────
class _ChooseSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<_Opt> items;
  final List<int> recentIds;
  final String allLabel;
  final bool search;
  const _ChooseSheet({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.recentIds,
    required this.allLabel,
    required this.search,
  });

  @override
  State<_ChooseSheet> createState() => _ChooseSheetState();
}

class _ChooseSheetState extends State<_ChooseSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.items.where((o) => q.isEmpty || o.label.toLowerCase().contains(q)).toList();
    final recent = [
      for (final id in widget.recentIds)
        for (final o in widget.items)
          if (o.id == id) o
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.max, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: attDark)),
              Text(widget.subtitle, style: const TextStyle(fontSize: 12.5, color: _muted)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        if (widget.search) ...[
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ],
        Expanded(
          child: ListView(padding: const EdgeInsets.only(top: 10), children: [
            if (q.isEmpty && recent.isNotEmpty) ...[
              const Text('Used recently', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in recent)
                  ActionChip(
                    backgroundColor: const Color(0xFFE3F0DA),
                    label: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700, color: attDark)),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onPressed: () => Navigator.pop(context, o.id),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            Text(q.isEmpty ? '${widget.allLabel} (${widget.items.length})' : 'Matches (${list.length})',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
            const SizedBox(height: 4),
            for (final o in list)
              ListTile(
                dense: false,
                minVerticalPadding: 10,
                title: Text(o.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, o.id),
              ),
            if (list.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing matches.', style: TextStyle(color: _muted))),
          ]),
        ),
      ]),
    );
  }
}

// ── choose workers: Men / Women tabs ───────────────────────────────────
class _WorkersSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<Map<String, dynamic>> workers;
  final int Function(int) statusOf; // 0 free, 1 here, 2 elsewhere (will split), 3 blocked
  final String Function(int) noteOf;
  const _WorkersSheet({
    required this.title,
    required this.subtitle,
    required this.workers,
    required this.statusOf,
    required this.noteOf,
  });

  @override
  State<_WorkersSheet> createState() => _WorkersSheetState();
}

class _WorkersSheetState extends State<_WorkersSheet> {
  bool _women = false;
  final Set<int> _sel = {};
  String _q = '';

  List<Map<String, dynamic>> get _tabList => widget.workers.where((w) {
        final f = '${w['gender']}' == 'F';
        if (f != _women) return false;
        final q = _q.trim().toLowerCase();
        return q.isEmpty || '${w['name']}'.toLowerCase().contains(q);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final men = widget.workers.where((w) => '${w['gender']}' != 'F').length;
    final women = widget.workers.length - men;
    final list = _tabList;
    Widget tab(String label, bool on, VoidCallback tap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: tap,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? const Color(0xFFE3F0DA) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: on ? attGreen : _line, width: 1.5),
              ),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: attDark)),
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 12 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: attDark)),
              Text(widget.subtitle, style: const TextStyle(fontSize: 12.5, color: _muted)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          tab('Men ($men)', !_women, () => setState(() => _women = false)),
          const SizedBox(width: 8),
          tab('Women ($women)', _women, () => setState(() => _women = true)),
        ]),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search name', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => _q = v),
        ),
        Row(children: [
          TextButton(
            onPressed: () => setState(() {
              for (final w in _tabList) {
                final id = _i(w['id']);
                if (widget.statusOf(id) == 0) _sel.add(id);
              }
            }),
            child: const Text('Select all free'),
          ),
          TextButton(onPressed: () => setState(_sel.clear), child: const Text('Clear')),
        ]),
        Expanded(
          child: GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 3 : 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 3.0,
            children: [
              for (final w in list) _workerTile(w),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: attGreen, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: _sel.isEmpty ? null : () => Navigator.pop(context, _sel.toList()),
          child: Text(_sel.isEmpty ? 'Choose workers' : 'Add ${_sel.length} ${_sel.length == 1 ? 'worker' : 'workers'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ]),
    );
  }

  Widget _workerTile(Map<String, dynamic> w) {
    final id = _i(w['id']);
    final st = widget.statusOf(id);
    final on = _sel.contains(id);
    final disabled = st == 1 || st == 3;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: disabled
          ? null
          : () => setState(() {
                if (on) {
                  _sel.remove(id);
                } else {
                  _sel.add(id);
                }
              }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? const Color(0xFFE3F0DA) : (disabled ? const Color(0xFFF3F4F1) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? attGreen : const Color(0xFFDDE5D5), width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${w['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: disabled ? const Color(0xFF8A9283) : const Color(0xFF1F2A19))),
          Text(widget.noteOf(id), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: _muted)),
        ]),
      ),
    );
  }
}
