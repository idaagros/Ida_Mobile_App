// lib/screens/agri/cycle_common.dart
//
// Shared pieces for Crop cycles and the crop calendar on the phone
// (Sep 2026, group C) — the same as the website's pages/agri/cycleParts.jsx:
//  - number formats (₹, quintals: harvest is entered in kg, 1 qtl = 100 kg)
//  - progress bar (stage, day N of the variety's days to harvest)
//  - Record labour sheet: work NOT in Farm attendance (picking paid per kg,
//    a contractor, outside labour); daily farm workers are counted from
//    Farm attendance by themselves. Several workers at once, or "someone
//    else". Admins can correct or delete an entry.
//  - Record harvest sheet (kg), Cancel cycle sheet (admin, reason needed).
// API: /agri/cycles…, /agri/labor-entries, /agri/harvest-records

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../agronomy/agronomy_common.dart' show AgriApi;

const Color cGreen = Color(0xFF3B7A28);
const Color cDark = Color(0xFF1E4012);
const Color cBg = Color(0xFFF4F7F2);
const Color cBorder = Color(0xFFE0E7D8);
const Color cMuted = Color(0xFF5F6A58);
const Color cRed = Color(0xFF9E2419);
const Color cAmber = Color(0xFF7A4D00);

final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');
String inr(dynamic n) => '₹${_inr.format((double.tryParse('$n') ?? 0).round())}';
String qtlText(dynamic kg) {
  final q = ((double.tryParse('$kg') ?? 0).round()) / 100;
  return '${q.toStringAsFixed(q == q.roundToDouble() ? 0 : 2).replaceAll(RegExp(r'0$'), '').replaceAll(RegExp(r'\.$'), '')} qtl';
}
String kgText(dynamic kg) {
  final k = double.tryParse('$kg') ?? 0;
  return '${k == k.roundToDouble() ? _inr.format(k.round()) : k.toStringAsFixed(2)} kg';
}
String dayMonth(dynamic d) {
  final t = DateTime.tryParse('${d ?? ''}'.length >= 10 ? '$d'.substring(0, 10) : '');
  return t == null ? '' : DateFormat('d MMM').format(t);
}
String todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());
int toInt(dynamic v) => (double.tryParse('${v ?? ''}') ?? 0).round();

const Map<String, String> stateLabel = {'running': 'Running', 'finished': 'Finished', 'cancelled': 'Cancelled'};

String whereText(Map c) {
  final orchard = c['cycle_type'] == 'orchard';
  final size = orchard ? (c['trees'] != null ? '${c['trees']} trees' : null) : (c['area_acre'] != null ? '${c['area_acre']} ac' : null);
  final when = orchard ? [if (c['bahar_name'] != null) '${c['bahar_name']} bahar', if (c['cycle_year'] != null) '${c['cycle_year']}'].join(' ') : c['season'];
  return [c['farm_name'], size, when].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
}

class JobText {
  final String text;
  final String when;
  final Color color;
  const JobText(this.text, this.when, this.color);
}

JobText nextJobText(Map? j) {
  if (j == null) return const JobText('—', '', cMuted);
  final kind = j['kind'] == 'pruning' ? 'Pruning' : j['activity_type'] == 'fertilizer' ? 'Fertiliser' : 'Spray';
  final t = todayStr();
  final d = '${j['date'] ?? ''}';
  final late = j['status'] == 'overdue' || d.compareTo(t) < 0;
  final when = late ? 'was due ${dayMonth(d)}' : d == t ? 'today' : dayMonth(d);
  return JobText('$kind · ${j['label'] ?? ''}', when, late ? cRed : d == t ? cAmber : cMuted);
}

// (text, background, foreground)
(String, Color, Color) jobsChip(Map c) {
  final jobs = Map<String, dynamic>.from(c['jobs'] ?? {});
  if (toInt(jobs['overdue']) > 0) return ('${jobs['overdue']} overdue', const Color(0xFFFBE2DF), cRed);
  if (toInt(jobs['today']) > 0) return ('${jobs['today']} due today', const Color(0xFFFCEFD2), cAmber);
  if (c['state'] != 'running') return (stateLabel[c['state']] ?? '', const Color(0xFFECEEE8), const Color(0xFF4A5643));
  if (c['next_job'] == null) return (toInt(jobs['done']) > 0 ? 'all done' : 'no jobs', const Color(0xFFE3F0DA), const Color(0xFF2C5E17));
  return ('on time', const Color(0xFFE3F0DA), const Color(0xFF2C5E17));
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, this.bg, this.fg, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

class CycleProgress extends StatelessWidget {
  final Map c;
  const CycleProgress(this.c, {super.key});
  @override
  Widget build(BuildContext context) {
    final of = toInt(c['days_to_harvest']);
    final day = c['day'] == null ? null : toInt(c['day']);
    final pct = of > 0 && day != null ? (day / of).clamp(0.0, 1.0) : null;
    final stage = (c['stage'] is Map ? c['stage']['name'] : null) ?? (c['state'] == 'running' ? 'Growing' : stateLabel[c['state']]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('$stage', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        if (day != null) Text('day $day${of > 0 ? ' of $of' : ''}', style: const TextStyle(fontSize: 12, color: cMuted)),
      ]),
      if (pct != null) ...[
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: pct, minHeight: 7, backgroundColor: const Color(0xFFEEF1EA),
            valueColor: AlwaysStoppedAnimation(day != null && day > of ? const Color(0xFFC77A14) : const Color(0xFF6FA04A)),
          ),
        ),
      ],
    ]);
  }
}

// ── Bottom sheets ─────────────────────────────────────────────────────
Future<bool?> _sheet(BuildContext context, Widget child) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => child,
    );

Widget _sheetFrame(BuildContext context, {required String title, String? sub, required List<Widget> children, required Widget actions}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cDark)),
        if (sub != null) Text(sub, style: const TextStyle(fontSize: 13, color: cMuted)),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 12),
        actions,
      ]),
    ),
  );
}

InputDecoration _dec(String label, {String? hint, String? helper}) => InputDecoration(
      labelText: label, hintText: hint, helperText: helper, helperMaxLines: 2,
      border: const OutlineInputBorder(), isDense: true,
    );

Widget _err(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(padding: const EdgeInsets.only(top: 8), child: Text(e, style: const TextStyle(color: cRed, fontSize: 13)));

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime.now());

// Record labour (new) or correct / delete an entry (admin).
Future<bool?> showLabourSheet(BuildContext context, {required Map cycle, Map? entry, bool canDelete = false}) {
  return _sheet(context, _LabourSheet(cycle: cycle, entry: entry, canDelete: canDelete));
}

class _LabourSheet extends StatefulWidget {
  final Map cycle;
  final Map? entry;
  final bool canDelete;
  const _LabourSheet({required this.cycle, this.entry, this.canDelete = false});
  @override
  State<_LabourSheet> createState() => _LabourSheetState();
}

class _LabourSheetState extends State<_LabourSheet> {
  late DateTime date;
  final work = TextEditingController();
  final party = TextEditingController();
  final people = TextEditingController();
  final kg = TextEditingController();
  final rate = TextEditingController();
  final days = TextEditingController();
  final wage = TextEditingController();
  final amount = TextEditingController();
  String mode = 'piece_rate';
  String who = 'workers';
  List workers = [];
  final Set<int> picked = {};
  String? error;
  bool saving = false;
  bool get isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    date = DateTime.tryParse('${e?['date'] ?? ''}') ?? DateTime.now();
    if (e != null) {
      work.text = '${e['work'] ?? ''}';
      mode = '${e['payment_mode'] ?? 'piece_rate'}';
      who = e['worker_id'] != null ? 'workers' : 'party';
      party.text = '${e['party_name'] ?? ''}';
      people.text = e['workers_count'] != null ? '${e['workers_count']}' : '';
      kg.text = e['quantity_harvested_kg'] != null ? '${e['quantity_harvested_kg']}' : '';
      rate.text = e['rate_applied_per_kg'] != null ? '${e['rate_applied_per_kg']}' : '';
      days.text = e['days_worked'] != null ? '${e['days_worked']}' : '';
      wage.text = mode == 'daily' && e['daily_wage_amount'] != null ? '${e['daily_wage_amount']}' : '';
      amount.text = mode == 'contract' ? '${e['daily_wage_amount'] ?? e['cost'] ?? ''}' : '';
    } else {
      AgriApi.get('/farm-workers').then((w) {
        if (!mounted) return;
        setState(() => workers = (w as List? ?? [])..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase())));
      }).catchError((_) {
        if (mounted) setState(() => who = 'party');
      });
    }
  }

  double _n(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;
  double get each => mode == 'piece_rate' ? _n(kg) * _n(rate) : mode == 'daily' ? _n(days) * _n(wage) : _n(amount);
  int get count => isNew && who == 'workers' ? (picked.isEmpty ? 1 : picked.length) : 1;

  Future<void> _save() async {
    setState(() => error = null);
    if (work.text.trim().isEmpty) return setState(() => error = 'Write the work done, e.g. Cotton picking.');
    if (isNew && who == 'workers' && picked.isEmpty) return setState(() => error = 'Pick the workers, or choose "Someone else" for a contractor.');
    if (who == 'party' && party.text.trim().isEmpty) return setState(() => error = 'Write who did the work, e.g. the contractor\'s name.');
    setState(() => saving = true);
    final body = <String, dynamic>{
      'entry_date': DateFormat('yyyy-MM-dd').format(date), 'activity_type': work.text.trim(), 'payment_mode': mode,
      'quantity_harvested_kg': kg.text.trim(), 'rate_applied_per_kg': rate.text.trim(), 'days_worked': days.text.trim(),
      'daily_wage_amount': wage.text.trim(), 'amount': amount.text.trim(),
      if (who == 'party') 'party_name': party.text.trim(),
      if (who == 'party' && people.text.trim().isNotEmpty) 'workers_count': people.text.trim(),
    };
    try {
      if (isNew) {
        await AgriApi.post('/agri/labor-entries', {
          ...body, 'cycle_type': widget.cycle['cycle_type'], 'cycle_id': widget.cycle['cycle_id'],
          if (who == 'workers') 'worker_ids': picked.toList(),
        });
      } else {
        await AgriApi.patch('/agri/labor-entries/${widget.entry!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { error = '$e'; saving = false; });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this labour entry?'),
        content: const Text('Its cost is taken off this crop.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: cRed)))],
      ),
    );
    if (ok != true) return;
    try {
      await AgriApi.delete('/agri/labor-entries/${widget.entry!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Widget _seg(List<(String, String)> opts, String value, void Function(String) onPick) => SegmentedButton<String>(
        segments: [for (final o in opts) ButtonSegment(value: o.$1, label: Text(o.$2, style: const TextStyle(fontSize: 13)))],
        selected: {value},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => onPick(s.first)),
      );

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _dec(label), onChanged: (_) => setState(() {}));

  @override
  Widget build(BuildContext context) {
    final each2 = count > 1 ? ' (each)' : '';
    return _sheetFrame(context,
        title: isNew ? 'Record labour' : 'Labour entry',
        sub: '${widget.cycle['label'] ?? ''}',
        children: [
          if (isNew)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF6F8F3), borderRadius: BorderRadius.circular(10)),
              child: const Text('For picking paid per kg, a contractor or outside labour. Daily farm workers are counted from Farm attendance by themselves.',
                  style: TextStyle(fontSize: 12.5, color: cMuted)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async { final d = await _pickDate(context, date); if (d != null) setState(() => date = d); },
                icon: const Icon(Icons.event, size: 18),
                label: Text(DateFormat('d MMM yyyy').format(date)),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: work, decoration: _dec('Work', hint: 'e.g. Picking'))),
          ]),
          const SizedBox(height: 12),
          if (isNew) ...[
            _seg([('workers', 'Farm workers'), ('party', 'Someone else')], who, (v) => who = v),
            const SizedBox(height: 10),
          ],
          if (isNew && who == 'workers') ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final w in workers)
                FilterChip(
                  label: Text('${w['name']}'),
                  selected: picked.contains(toInt(w['id'])),
                  onSelected: (on) => setState(() => on ? picked.add(toInt(w['id'])) : picked.remove(toInt(w['id']))),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(picked.isEmpty ? 'Tap the workers who did this work.' : '${picked.length} picked — one entry is saved for each worker.',
                  style: const TextStyle(fontSize: 12, color: cMuted)),
            ),
            const SizedBox(height: 10),
          ],
          if (who == 'party') ...[
            Row(children: [
              Expanded(flex: 2, child: TextField(controller: party, decoration: _dec('Name', hint: 'e.g. contractor'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: people, keyboardType: TextInputType.number, decoration: _dec('People'))),
            ]),
            const SizedBox(height: 12),
          ],
          _seg([('piece_rate', 'By kg'), ('contract', 'Fixed'), ('daily', 'By day')], mode, (v) => mode = v),
          const SizedBox(height: 12),
          if (mode == 'piece_rate') Row(children: [Expanded(child: _num(kg, 'Kg picked$each2')), const SizedBox(width: 10), Expanded(child: _num(rate, 'Rate per kg (₹)'))]),
          if (mode == 'daily') Row(children: [Expanded(child: _num(days, 'Days$each2')), const SizedBox(width: 10), Expanded(child: _num(wage, 'Wage per day (₹)'))]),
          if (mode == 'contract') _num(amount, 'Amount paid (₹)$each2'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF6F8F3), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Text(count > 1 ? '$count workers × ${inr(each)}' : 'Cost', style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(inr(each * count), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
          _err(error),
        ],
        actions: Row(children: [
          if (!isNew && widget.canDelete) ...[
            OutlinedButton(onPressed: saving ? null : _delete, style: OutlinedButton.styleFrom(foregroundColor: cRed, minimumSize: const Size(0, 48)), child: const Text('Delete')),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: cGreen, minimumSize: const Size.fromHeight(48)),
              child: Text(saving ? 'Saving…' : isNew ? 'Save labour' : 'Save changes'),
            ),
          ),
        ]));
  }
}

// Record harvest (kg) or correct / delete a record (admin).
Future<bool?> showHarvestSheet(BuildContext context, {required Map cycle, Map? record, bool canDelete = false}) {
  return _sheet(context, _HarvestSheet(cycle: cycle, record: record, canDelete: canDelete));
}

class _HarvestSheet extends StatefulWidget {
  final Map cycle;
  final Map? record;
  final bool canDelete;
  const _HarvestSheet({required this.cycle, this.record, this.canDelete = false});
  @override
  State<_HarvestSheet> createState() => _HarvestSheetState();
}

class _HarvestSheetState extends State<_HarvestSheet> {
  late DateTime date;
  final kg = TextEditingController();
  final grade = TextEditingController();
  final notes = TextEditingController();
  String? error;
  bool saving = false;
  bool get isNew => widget.record == null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    date = DateTime.tryParse('${r?['harvest_date'] ?? ''}'.length >= 10 ? '${r!['harvest_date']}'.substring(0, 10) : '') ?? DateTime.now();
    if (r != null) {
      kg.text = '${r['quantity_kg'] ?? ''}';
      grade.text = '${r['quality_grade'] ?? ''}';
      notes.text = '${r['remarks'] ?? ''}';
    }
  }

  Future<void> _save() async {
    final k = double.tryParse(kg.text.trim()) ?? 0;
    if (k <= 0) return setState(() => error = 'Write the kg harvested.');
    setState(() { saving = true; error = null; });
    final body = {'harvest_date': DateFormat('yyyy-MM-dd').format(date), 'quantity_kg': k, 'quality_grade': grade.text.trim(), 'remarks': notes.text.trim()};
    try {
      if (isNew) {
        await AgriApi.post('/agri/harvest-records', {...body, 'cycle_type': widget.cycle['cycle_type'], 'cycle_id': widget.cycle['cycle_id']});
      } else {
        await AgriApi.patch('/agri/harvest-records/${widget.record!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { error = '$e'; saving = false; });
    }
  }

  Future<void> _delete() async {
    try {
      await AgriApi.delete('/agri/harvest-records/${widget.record!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = double.tryParse(kg.text.trim()) ?? 0;
    return _sheetFrame(context,
        title: isNew ? 'Record harvest' : 'Harvest record',
        sub: '${widget.cycle['label'] ?? ''}',
        children: [
          OutlinedButton.icon(
            onPressed: () async { final d = await _pickDate(context, date); if (d != null) setState(() => date = d); },
            icon: const Icon(Icons.event, size: 18),
            label: Text(DateFormat('d MMM yyyy').format(date)),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: kg, autofocus: isNew, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _dec('Harvested (kg)', helper: k > 0 ? '= ${qtlText(k)}' : 'Weigh in kg; it is shown in quintals.'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(controller: grade, decoration: _dec('Grade (optional)', hint: 'e.g. A')),
          const SizedBox(height: 12),
          TextField(controller: notes, decoration: _dec('Notes (optional)')),
          _err(error),
        ],
        actions: Row(children: [
          if (!isNew && widget.canDelete) ...[
            OutlinedButton(onPressed: saving ? null : _delete, style: OutlinedButton.styleFrom(foregroundColor: cRed, minimumSize: const Size(0, 48)), child: const Text('Delete')),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: cGreen, minimumSize: const Size.fromHeight(48)),
              child: Text(saving ? 'Saving…' : isNew ? 'Save harvest' : 'Save changes'),
            ),
          ),
        ]));
  }
}

// Cancel a cycle (admin). Returns true when cancelled.
Future<bool?> showCancelCycleSheet(BuildContext context, Map cycle) => _sheet(context, _CancelSheet(cycle: cycle));

class _CancelSheet extends StatefulWidget {
  final Map cycle;
  const _CancelSheet({required this.cycle});
  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final reason = TextEditingController();
  String? error;
  bool saving = false;
  static const reasons = ['Sown by mistake', 'Entered twice', 'Crop failed, ploughed out'];

  Future<void> _save() async {
    if (reason.text.trim().isEmpty) return setState(() => error = 'Write why it is being cancelled.');
    setState(() { saving = true; error = null; });
    try {
      await AgriApi.post('/agri/cycles/${widget.cycle['cycle_type']}/${widget.cycle['cycle_id']}/cancel', {'reason': reason.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { error = '$e'; saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cycle;
    final money = Map<String, dynamic>.from(c['money'] ?? {});
    final jobs = Map<String, dynamic>.from(c['jobs'] ?? {});
    return _sheetFrame(context,
        title: 'Cancel ${c['crop_name'] ?? 'this crop'} on ${c['farm_name'] ?? ''}?',
        children: [
          const Text('It will no longer show in Crop cycles, the crop calendar jobs, Weather or reminders, and its coming jobs are dropped.', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Text('Nothing recorded is deleted: ${toInt(jobs['done'])} jobs done and ${inr(money['total'])} spent stay, and still count in Crop reports.',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in reasons) ChoiceChip(label: Text(r), selected: reason.text == r, onSelected: (_) => setState(() => reason.text = r)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: reason, decoration: _dec('Why? (needed)'), onChanged: (_) => setState(() {})),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('A cancelled cycle can be brought back from the Cancelled list.', style: TextStyle(fontSize: 12, color: cMuted))),
          _err(error),
        ],
        actions: Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Keep it'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB0342A), minimumSize: const Size.fromHeight(48)),
              child: Text(saving ? 'Saving…' : 'Cancel cycle'),
            ),
          ),
        ]));
  }
}
