// lib/screens/farm_tractor_day_screen.dart
//
// Farm tractor › Day sheet (Sep 2026 redesign, same as the web):
//   - per tractor: hour meter at the start of the day (filled from the
//     previous day's end) and at the end, when it is back in the garage
//   - its jobs: farm, work, hours on the job (should add up to the
//     meter hours), acres (optional), estimated diesel
//   - "Continue unfinished work" for jobs that run over several days
//   - estimated diesel left in the tank
// Diesel fill-ups and Setup open from the app bar.
//
// API: GET /farm-tractor/day, PUT /farm-tractor/day-meter,
//      POST/PATCH/DELETE /farm-tractor/jobs, GET /farm-tractor/diesel/summary

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/responsive.dart';
import 'agronomy/agronomy_common.dart';
import 'farm_tractor_diesel_screen.dart';
import 'admin/farm_tractor_master_screen.dart';

const _loadLabel = {'heavy': 'Heavy', 'medium': 'Medium', 'light': 'Light'};
const _loadColors = {
  'heavy': [Color(0xFFFBE2DF), Color(0xFF9E2419)],
  'medium': [Color(0xFFFCEFD2), Color(0xFF7A4D00)],
  'light': [Color(0xFFE3F0DA), Color(0xFF2C5E17)],
};
const _sourceText = {'fixed': 'fixed figure', 'own': "this tractor's own", 'standard': 'standard'};

String _f1(dynamic v) {
  final d = toD(v);
  if (d == null) return '—';
  return trimNum(d, 1);
}

String _tractorLabel(Map t) => [t['name'], t['model']].where((x) => x != null && '$x'.isNotEmpty).join(' ');

Widget _loadChip(String? level) {
  final c = _loadColors[level] ?? _loadColors['medium']!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20)),
    child: Text(_loadLabel[level] ?? 'Medium', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c[1])),
  );
}

Widget _box(String text, {bool warn = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: warn ? const Color(0xFFFFF7EA) : const Color(0xFFF3F8EE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: warn ? const Color(0xFFF3D7A6) : const Color(0xFFCFE3C0))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(warn ? Icons.warning_amber_rounded : Icons.check, size: 16, color: warn ? const Color(0xFFB8660B) : agGreen),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: warn ? const Color(0xFF7A4D00) : const Color(0xFF2C5E17)))),
      ]),
    );

class FarmTractorDayScreen extends StatefulWidget {
  const FarmTractorDayScreen({super.key});
  @override
  State<FarmTractorDayScreen> createState() => _FarmTractorDayScreenState();
}

class _FarmTractorDayScreenState extends State<FarmTractorDayScreen> {
  DateTime date = DateTime.now();
  Map? data;
  Map<String, Map> lph = {}; // "tractorId:workTypeId" -> rate
  List farms = [];
  List workTypes = [];
  List rateCard = [];
  bool loading = true;
  bool canWrite = false;
  String? error;

  String get ds => DateFormat('yyyy-MM-dd').format(date);

  @override
  void initState() {
    super.initState();
    ApiService.canEdit('farm_tractor').then((v) {
      if (mounted) setState(() => canWrite = v);
    });
    _loadLookups();
    _load();
  }

  Future<void> _loadLookups() async {
    try {
      final r = await Future.wait([
        AgriApi.get('/farms'),
        AgriApi.get('/work-types?applies_to=tractor'),
        AgriApi.get('/farm-tractor/rate-card'),
      ]);
      if (mounted) {
        setState(() {
          farms = r[0] as List;
          workTypes = r[1] as List;
          rateCard = r[2] as List;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        AgriApi.get('/farm-tractor/day?date=$ds'),
        AgriApi.get('/farm-tractor/diesel/summary?date=$ds'),
      ]);
      final m = <String, Map>{};
      for (final t in ((r[1] as Map)['tractors'] as List? ?? [])) {
        for (final x in (t['rates'] as List? ?? [])) {
          m['${t['tractor']['id']}:${x['work_type_id']}'] = x as Map;
        }
      }
      if (!mounted) return;
      setState(() {
        data = r[0] as Map;
        lph = m;
        error = null;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void _moveDay(int n) {
    final next = date.add(Duration(days: n));
    if (next.isAfter(DateTime.now())) return;
    setState(() => date = next);
    _load();
  }

  Future<void> _openJob({Map? job, Map? tractor, Map? continues}) async {
    final tractors = ((data?['tractors'] as List?) ?? []).cast<Map>();
    if (tractors.isEmpty) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _JobForm(
          date: ds,
          tractors: tractors,
          farms: farms,
          workTypes: workTypes,
          rateCard: rateCard,
          lph: lph,
          unfinished: ((data?['unfinished'] as List?) ?? []).cast<Map>(),
          job: job,
          tractorId: toI(job?['tractor_id'] ?? continues?['tractor_id'] ?? tractor?['id'] ?? tractors.first['id']),
          continues: continues,
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final tractors = ((data?['tractors'] as List?) ?? []).cast<Map>();
    final unfinished = ((data?['unfinished'] as List?) ?? []).cast<Map>();
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == ds;
    return Scaffold(
      backgroundColor: agBg,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Farm tractor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Diesel',
            icon: const Icon(Icons.local_gas_station_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmTractorDieselScreen()));
              _load();
            },
          ),
          IconButton(
            tooltip: 'Setup',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const FarmTractorMasterScreen()));
              _loadLookups();
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: !canWrite || tractors.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: agGreen,
              foregroundColor: Colors.white,
              onPressed: () => _openJob(),
              icon: const Icon(Icons.add),
              label: const Text('Add job'),
            ),
      body: Responsive.constrainedContent(
        context,
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 96), children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
              child: Row(children: [
                IconButton(onPressed: () => _moveDay(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final p = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2023), lastDate: DateTime.now());
                      if (p != null) {
                        setState(() => date = p);
                        _load();
                      }
                    },
                    child: Column(children: [
                      Text(DateFormat('EEE, d MMM yyyy').format(date), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                      if (!isToday) const Text('tap to pick a date', style: TextStyle(fontSize: 11, color: agMuted)),
                    ]),
                  ),
                ),
                IconButton(onPressed: isToday ? null : () => _moveDay(1), icon: const Icon(Icons.chevron_right)),
              ]),
            ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: _box(error!, warn: true)),
            if (loading && data == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: agGreen))),
            if (unfinished.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: agBorder)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Continue unfinished work', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  for (final u in unfinished)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size.fromHeight(42)),
                        onPressed: canWrite ? () => _openJob(continues: u) : null,
                        icon: const Icon(Icons.replay, size: 18),
                        label: Text('${u['work_type_name']} · ${u['farm_name']} · ${u['tractor_name']} (day ${(toI(u['days']) ?? 1) + 1})',
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ]),
              ),
            ],
            for (final t in tractors) ...[
              const SizedBox(height: 12),
              _TractorCard(t: t, date: ds, canWrite: canWrite, onChanged: _load, onOpenJob: (j) => _openJob(job: j), onAdd: () => _openJob(tractor: t)),
            ],
            if (data != null && tractors.isEmpty)
              const Padding(padding: EdgeInsets.all(30), child: Text('No tractors yet — add them in Setup.', textAlign: TextAlign.center)),
          ]),
        ),
      ),
    );
  }
}

class _TractorCard extends StatefulWidget {
  final Map t;
  final String date;
  final bool canWrite;
  final VoidCallback onChanged;
  final void Function(Map job) onOpenJob;
  final VoidCallback onAdd;
  const _TractorCard({required this.t, required this.date, required this.canWrite, required this.onChanged, required this.onOpenJob, required this.onAdd});
  @override
  State<_TractorCard> createState() => _TractorCardState();
}

class _TractorCardState extends State<_TractorCard> {
  final startCtrl = TextEditingController();
  final endCtrl = TextEditingController();
  bool saving = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void didUpdateWidget(covariant _TractorCard old) {
    super.didUpdateWidget(old);
    if (old.t != widget.t) _fill();
  }

  void _fill() {
    final day = widget.t['day'] as Map?;
    final s = day?['meter_start'] ?? widget.t['suggested_start'];
    startCtrl.text = s == null ? '' : _f1(s);
    endCtrl.text = day?['meter_end'] == null ? '' : _f1(day!['meter_end']);
  }

  Future<void> _saveMeter() async {
    final ms = double.tryParse(startCtrl.text.trim());
    final me = double.tryParse(endCtrl.text.trim());
    if (ms != null && me != null && me < ms) {
      setState(() => err = "Meter end can't be less than meter start.");
      return;
    }
    setState(() {
      saving = true;
      err = null;
    });
    try {
      await AgriApi.put('/farm-tractor/day-meter', {'tractor_id': widget.t['id'], 'work_date': widget.date, 'meter_start': ms, 'meter_end': me});
      widget.onChanged();
      if (mounted) agSnack(context, 'Meter saved');
    } catch (e) {
      setState(() => err = e.toString());
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final jobs = ((t['jobs'] as List?) ?? []).cast<Map>();
    final tank = (t['tank'] as Map?) ?? {};
    final ms = double.tryParse(startCtrl.text.trim());
    final me = double.tryParse(endCtrl.text.trim());
    final run = ms != null && me != null ? me - ms : toD(t['hours_run']);
    final alloc = toD(t['allocated_hours']) ?? 0;
    final sugg = toD(t['suggested_start']);
    final gap = sugg != null && ms != null && (ms - sugg).abs() >= 0.1;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: agBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Row(children: [
            const CircleAvatar(radius: 20, backgroundColor: Color(0xFFE3F0DA), child: Icon(Icons.agriculture, color: agGreen)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_tractorLabel(t), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                Text([if (t['hp'] != null) '${_f1(t['hp'])} HP', if (t['registration_number'] != null) t['registration_number']].join(' · '),
                    style: const TextStyle(fontSize: 12, color: agMuted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Ran', style: TextStyle(fontSize: 11.5, color: agMuted)),
              Text(run == null ? '—' : '${_f1(run)} h', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: startCtrl,
                enabled: widget.canWrite,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
                decoration: agInput('Meter start'),
                onChanged: (_) => setState(() {}),
                onEditingComplete: _saveMeter,
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→', style: TextStyle(color: agMuted))),
            Expanded(
              child: TextField(
                controller: endCtrl,
                enabled: widget.canWrite,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
                decoration: agInput('Meter end (garage)'),
                onChanged: (_) => setState(() {}),
                onEditingComplete: _saveMeter,
              ),
            ),
            if (widget.canWrite)
              IconButton(tooltip: 'Save meter', onPressed: saving ? null : _saveMeter, icon: const Icon(Icons.check_circle, color: agGreen)),
          ]),
        ),
        if (err != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: _box(err!, warn: true)),
        if (gap)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: _box('The last day ended at ${_f1(sugg)}; this starts at ${_f1(ms)} — ${_f1((ms! - sugg!).abs())} hours ${ms > sugg ? 'not recorded in between' : 'overlap'}.', warn: true),
          ),
        for (final j in jobs)
          InkWell(
            onTap: () => widget.onOpenJob(j),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF1EA)))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${j['work_type_name']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      _loadChip(j['load_level']),
                      if (j['is_finished'] == 0 || j['is_finished'] == false) const SmallChip('Continues', bg: Color(0xFFFCEFD2), fg: Color(0xFF7A4D00)),
                    ]),
                    Text('${j['farm_name']}', style: const TextStyle(fontSize: 12.5, color: agMuted)),
                    if (j['job_total'] != null)
                      Text('↻ Day ${j['job_total']['days']} of this job · so far ${_f1(j['job_total']['hours'])} h${j['job_total']['acres'] != null ? ', ${_f1(j['job_total']['acres'])} acres' : ''}',
                          style: const TextStyle(fontSize: 12, color: agGreen, fontWeight: FontWeight.w600)),
                    Text('${_f1(j['total_hours'])} h · ${j['acres_worked'] != null ? '${_f1(j['acres_worked'])} acres' : 'no acres'}',
                        style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Est. diesel', style: TextStyle(fontSize: 11, color: agMuted)),
                  Text(j['est_diesel_l'] == null ? '—' : '${_f1(j['est_diesel_l'])} L', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ]),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: const BoxDecoration(color: Color(0xFFFCFCFA), border: Border(top: BorderSide(color: Color(0xFFEEF1EA))), borderRadius: BorderRadius.vertical(bottom: Radius.circular(14))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (run == null)
              (jobs.isNotEmpty ? _box('Meter end not entered yet — jobs have ${_f1(alloc)} h.', warn: true) : const Text('No jobs yet.', style: TextStyle(color: agMuted)))
            else if ((run - alloc).abs() < 0.05)
              _box('${_f1(alloc)} of ${_f1(run)} hours given to jobs')
            else
              _box('${_f1(alloc)} of ${_f1(run)} hours given to jobs — ${alloc < run ? 'add the other job or correct the hours' : 'jobs have more hours than the meter'}', warn: true),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Diesel in tank (est.): ${tank['balance'] == null ? '—' : '${_f1(tank['balance'])} L'}${tank['capacity'] != null ? ' of ${_f1(tank['capacity'])}' : ''}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: ((toD(tank['pct']) ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                      minHeight: 8,
                      backgroundColor: const Color(0xFFEEF1EA),
                      color: tank['low'] == true || tank['negative'] == true ? const Color(0xFFF4A340) : agGreen,
                    ),
                  ),
                ]),
              ),
              if (widget.canWrite) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(onPressed: widget.onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('Add job')),
              ],
            ]),
            if (tank['negative'] == true)
              Padding(padding: const EdgeInsets.only(top: 8), child: _box('Below zero — a fill-up is probably not entered.', warn: true))
            else if (tank['low'] == true)
              Padding(padding: const EdgeInsets.only(top: 8), child: _box('Running low on diesel.', warn: true)),
          ]),
        ),
      ]),
    );
  }
}

// ── Add / change a job ────────────────────────────────────────────────
class _JobForm extends StatefulWidget {
  final String date;
  final List<Map> tractors;
  final List farms;
  final List workTypes;
  final List rateCard;
  final Map<String, Map> lph;
  final List<Map> unfinished;
  final Map? job;
  final int? tractorId;
  final Map? continues;
  const _JobForm({required this.date, required this.tractors, required this.farms, required this.workTypes, required this.rateCard, required this.lph, required this.unfinished, this.job, this.tractorId, this.continues});
  @override
  State<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends State<_JobForm> {
  int? tractorId;
  int? farmId;
  int? workTypeId;
  int? continuesJobId;
  String? billingUnit;
  bool finished = true;
  final hoursCtrl = TextEditingController();
  final acresCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  bool saving = false;
  String? err;

  bool get editing => widget.job != null;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    final c = widget.continues;
    tractorId = widget.tractorId;
    farmId = toI(j?['farm_id'] ?? c?['farm_id']);
    workTypeId = toI(j?['work_type_id'] ?? c?['work_type_id']);
    continuesJobId = toI(c?['job_id']);
    billingUnit = j?['billing_unit'];
    finished = j == null ? true : (j['is_finished'] == 1 || j['is_finished'] == true);
    if (j?['total_hours'] != null) hoursCtrl.text = _f1(j!['total_hours']);
    if (j?['acres_worked'] != null) acresCtrl.text = _f1(j!['acres_worked']);
    if (j != null && j['billing_unit'] != null && j['billing_unit'] != 'hour' && j['billing_unit'] != 'acre' && j['quantity'] != null) qtyCtrl.text = _f1(j['quantity']);
    notesCtrl.text = j?['notes'] ?? '';
    hoursCtrl.addListener(() => setState(() {}));
    acresCtrl.addListener(() => setState(() {}));
  }

  Map? get tractor {
    for (final t in widget.tractors) {
      if (toI(t['id']) == tractorId) return t;
    }
    return null;
  }

  List<Map> get units => widget.rateCard
      .where((r) => toI(r['tractor_id']) == tractorId && toI(r['work_type_id']) == workTypeId)
      .map((r) => r as Map)
      .toList();

  String? get unit => units.length == 1 ? units.first['billing_unit'] : billingUnit;

  Future<void> _save() async {
    final hours = double.tryParse(hoursCtrl.text.trim());
    final acres = double.tryParse(acresCtrl.text.trim());
    final qty = double.tryParse(qtyCtrl.text.trim());
    String? e;
    if (tractorId == null || farmId == null || workTypeId == null) {
      e = 'Choose the tractor, farm and work.';
    } else if (hours == null || hours <= 0) {
      e = 'Write the hours spent on this job.';
    } else if (units.length > 1 && unit == null) {
      e = 'Choose how this job is paid.';
    } else if (unit == 'acre' && acres == null) {
      e = 'This work is paid per acre — write the acres worked.';
    } else if (unit != null && unit != 'hour' && unit != 'acre' && qty == null) {
      e = 'This work is paid per $unit — write how many.';
    }
    if (e != null) {
      setState(() => err = e);
      return;
    }
    setState(() {
      saving = true;
      err = null;
    });
    final body = {
      'tractor_id': tractorId,
      'farm_id': farmId,
      'work_type_id': workTypeId,
      'work_date': widget.job?['work_date'] ?? widget.date,
      'hours': hours,
      'acres': acres,
      'quantity': qty,
      'billing_unit': unit,
      'is_finished': finished,
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    };
    try {
      if (editing) {
        await AgriApi.patch('/farm-tractor/jobs/${widget.job!['id']}', body);
      } else {
        await AgriApi.post('/farm-tractor/jobs', {...body, 'continues_job_id': continuesJobId});
      }
      if (mounted) Navigator.pop(context, true);
    } catch (ex) {
      setState(() {
        saving = false;
        err = ex.toString();
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this job?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await AgriApi.delete('/farm-tractor/jobs/${widget.job!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (ex) {
      setState(() {
        saving = false;
        err = ex.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final openForTractor = widget.unfinished.where((u) => toI(u['tractor_id']) == tractorId).toList();
    final rate = widget.lph['$tractorId:$workTypeId'];
    final hours = double.tryParse(hoursCtrl.text.trim());
    final lphV = toD(rate?['lph']);
    final est = lphV != null && hours != null ? lphV * hours : null;
    final t = tractor;
    final otherHours = t == null
        ? 0.0
        : ((t['jobs'] as List?) ?? []).where((j) => j['id'] != widget.job?['id']).fold<double>(0, (s, j) => s + (toD(j['total_hours']) ?? 0));
    final run = toD(t?['hours_run']);
    Map? unitRow;
    for (final u in units) {
      if (u['billing_unit'] == unit) unitRow = u;
    }
    final unitRate = toD(unitRow?['rate']);
    final acres = double.tryParse(acresCtrl.text.trim());
    final qty = unit == 'hour' ? hours : (unit == 'acre' ? acres : double.tryParse(qtyCtrl.text.trim()));
    final locked = continuesJobId != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(editing ? 'Change job' : 'Add job', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(DateFormat('EEE d MMM').format(DateTime.parse(widget.job?['work_date'] ?? widget.date)), style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          if (editing) IconButton(tooltip: 'Delete job', onPressed: saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!editing && openForTractor.isNotEmpty) ...[
          agLabel('Continue earlier work?'),
          for (final u in openForTractor)
            RadioListTile<int?>(
              contentPadding: EdgeInsets.zero,
              value: toI(u['job_id']),
              groupValue: continuesJobId,
              activeColor: agGreen,
              title: Text('${u['work_type_name']} · ${u['farm_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Started ${u['started']} · so far ${_f1(u['hours'])} h${u['acres'] != null ? ', ${_f1(u['acres'])} acres' : ''}'),
              onChanged: (v) => setState(() {
                continuesJobId = v;
                farmId = toI(u['farm_id']);
                workTypeId = toI(u['work_type_id']);
              }),
            ),
          RadioListTile<int?>(
            contentPadding: EdgeInsets.zero,
            value: null,
            groupValue: continuesJobId,
            activeColor: agGreen,
            title: const Text('New work', style: TextStyle(fontWeight: FontWeight.w700)),
            onChanged: (_) => setState(() => continuesJobId = null),
          ),
          const SizedBox(height: 8),
        ],
        DropdownButtonFormField<int>(
          value: tractorId,
          isExpanded: true,
          decoration: agInput('Tractor'),
          items: [for (final x in widget.tractors) DropdownMenuItem(value: toI(x['id']), child: Text(_tractorLabel(x)))],
          onChanged: locked ? null : (v) => setState(() {
                tractorId = v;
                continuesJobId = null;
                billingUnit = null;
              }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: farmId,
          isExpanded: true,
          decoration: agInput('Farm'),
          items: [for (final f in widget.farms) DropdownMenuItem(value: toI(f['id']), child: Text('${f['name']}'))],
          onChanged: locked ? null : (v) => setState(() => farmId = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: workTypeId,
          isExpanded: true,
          decoration: agInput('Work'),
          items: [for (final w in widget.workTypes) DropdownMenuItem(value: toI(w['id']), child: Text('${w['name']}'))],
          onChanged: locked ? null : (v) => setState(() {
                workTypeId = v;
                billingUnit = null;
              }),
        ),
        if (rate != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [const Text('How hard: ', style: TextStyle(fontSize: 12, color: agMuted)), _loadChip(rate['load_level']), const Text('  — set in Setup', style: TextStyle(fontSize: 12, color: agMuted))]),
          ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: hoursCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: agInput('Hours on this job',
                  helper: run != null ? 'Day meter ${_f1(run)} h · ${_f1(otherHours)} h in other jobs' : '${_f1(otherHours)} h in other jobs today'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: acresCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: agInput('Acres (optional)'),
            ),
          ),
        ]),
        if (units.length > 1) ...[
          const SizedBox(height: 14),
          agLabel('How is this job paid?'),
          Wrap(spacing: 8, children: [
            for (final u in units)
              ChoiceChip(
                label: Text('Per ${u['billing_unit']} · ₹${_f1(u['rate'])}'),
                selected: unit == u['billing_unit'],
                selectedColor: agDark,
                labelStyle: TextStyle(color: unit == u['billing_unit'] ? Colors.white : const Color(0xFF3A4833), fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => billingUnit = u['billing_unit']),
              ),
          ]),
        ],
        if (unit != null && unit != 'hour' && unit != 'acre') ...[
          const SizedBox(height: 12),
          TextField(
            controller: qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: agInput('Number of ${unit}s'),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: 14),
        if (est != null)
          _box('Estimated diesel ${_f1(est)} L — ${_f1(hours)} h × ${_f1(lphV)} L/h (${_sourceText[rate?['source']] ?? ''})')
        else if (t != null && t['hp'] == null && workTypeId != null)
          const Text("Set this tractor's HP in Setup to estimate diesel.", style: TextStyle(fontSize: 12, color: agMuted)),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: finished,
          activeColor: agGreen,
          onChanged: (v) => setState(() => finished = v ?? true),
          title: const Text('This work is finished', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Untick if it continues tomorrow'),
        ),
        TextField(controller: notesCtrl, decoration: agInput('Notes (optional)', hint: 'e.g. east side remaining')),
        const SizedBox(height: 12),
        Text(
          units.isEmpty && workTypeId != null
              ? 'No rate set for this tractor and work — the job saves without pay. Add a rate in Setup.'
              : unitRate != null
                  ? 'Paid per $unit: ₹${_f1(unitRate)}${qty != null ? ' × ${_f1(qty)} = ₹${_f1(unitRate * qty)}' : ''}'
                  : '',
          style: const TextStyle(fontSize: 12.5, color: agMuted),
        ),
        if (err != null) ...[const SizedBox(height: 12), _box(err!, warn: true)],
      ]),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: agBorder))),
          child: Row(children: [
            Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                onPressed: saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(saving ? 'Saving…' : 'Save job'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
