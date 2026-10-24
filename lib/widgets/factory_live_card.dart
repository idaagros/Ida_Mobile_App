// lib/widgets/factory_live_card.dart
//
// Factory run + breaks entered AS THEY HAPPEN (phone).
//   Start  ->  Break / Break over  ->  Stop     (each with the time, default now, any time can be chosen)
// or press the microphone and say it: "started", "lunch break", "break over", "power cut, feeder belt problem",
// "stopped at 1:15", "lunch from 1 to 1:30" (Hindi or English). What was heard is shown to be checked first.
// A stopped run goes to the normal approval list, exactly like a run added the old way.
// Server: /factory-live (routes/factoryLive.js).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'voice_allocation_sheet.dart';

const Color _green = Color(0xFF3B7A28);
const Color _dark = Color(0xFF1E4012);
const Color _amberBg = Color(0xFFFFF4E5);
const Color _amberFg = Color(0xFF7A4A00);

const _reasonLabels = {
  'lunch': 'Lunch break',
  'dinner': 'Dinner break',
  'power_failure': 'Power failure',
  'maintenance': 'Maintenance',
  'breakdown': 'Breakdown',
  'raw_material_shortage': 'No raw material',
  'other': 'Other',
};

class FactoryLiveCard extends StatefulWidget {
  final VoidCallback? onChanged; // called after a run is stopped, so the list below refreshes
  const FactoryLiveCard({super.key, this.onChanged});

  @override
  State<FactoryLiveCard> createState() => _FactoryLiveCardState();
}

class _Ev {
  String type; // start | break_start | break_end | stop
  String? time; // HH:MM, null = now
  String? reason;
  String? note;
  _Ev(this.type, {this.time, this.reason, this.note});
  Map<String, dynamic> toJson() => {'type': type, if (time != null) 'time': time, if (reason != null) 'reason_type': reason, if (note != null && note!.isNotEmpty) 'reason_note': note};
}

class _FactoryLiveCardState extends State<FactoryLiveCard> {
  Map<String, dynamic>? _state;
  String? _error;
  bool _busy = false;
  String _date = ''; // the day the live run is on (today)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? date}) async {
    try {
      final r = Map<String, dynamic>.from(await Api.json('GET', '/factory-live/state', query: date == null ? null : {'date': date}) as Map);
      if (!mounted) return;
      setState(() {
        _state = r;
        _date = '${r['date']}';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = Api.errorText(e));
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Map<String, dynamic>? get _open => _state?['open'] == null ? null : Map<String, dynamic>.from(_state!['open'] as Map);

  String _label(_Ev e) {
    final t = e.time ?? 'now';
    switch (e.type) {
      case 'start':
        return 'Factory started · $t';
      case 'break_start':
        return 'Break (${_reasonLabels[e.reason] ?? 'Other'}) starts · $t';
      case 'break_end':
        return 'Break over · $t';
      default:
        return 'Factory stopped · $t';
    }
  }

  Future<bool> _apply(List<_Ev> events, {String? date}) async {
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await Api.json('POST', '/factory-live/apply', body: {'date': date ?? _date, 'events': [for (final e in events) e.toJson()]}) as Map);
      if (!mounted) return true;
      final stopped = events.any((e) => e.type == 'stop');
      setState(() {
        _state = r;
        _date = '${r['date']}';
      });
      if (stopped) widget.onChanged?.call();
      return true;
    } catch (e) {
      _toast(Api.errorText(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickTime(String? initial) async {
    TimeOfDay start = TimeOfDay.now();
    if (initial != null && initial.contains(':')) {
      final p = initial.split(':');
      start = TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
    }
    final t = await showTimePicker(context: context, initialTime: start);
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // One step with the time (default now) and, for a break, the reason.
  Future<void> _step(String type, {String? date, String? mustBeAfter}) async {
    String? time; // null = now
    String reason = 'lunch';
    final noteCtrl = TextEditingController();
    final title = {'start': 'Factory started', 'break_start': 'Break starts', 'break_end': 'Break over', 'stop': 'Factory stopped'}[type]!;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _dark)),
              const SizedBox(height: 10),
              Row(children: [
                ChoiceChip(label: const Text('Now'), selected: time == null && date == null, onSelected: date != null ? null : (_) => setS(() => time = null)),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(time == null ? (date == null ? 'Other time' : 'Choose the time') : 'At $time'),
                  onPressed: () async {
                    final t = await _pickTime(time);
                    if (t != null) setS(() => time = t);
                  },
                ),
              ]),
              if (type == 'break_start') ...[
                const SizedBox(height: 12),
                const Text('Why', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in _reasonLabels.entries)
                    ChoiceChip(label: Text(e.value), selected: reason == e.key, onSelected: (_) => setS(() => reason = e.key)),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  maxLength: 255,
                  decoration: const InputDecoration(labelText: 'Note (optional, e.g. machine and problem)', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _green, minimumSize: const Size.fromHeight(50)),
                onPressed: (date != null && time == null) ? null : () => Navigator.pop(ctx, true),
                child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ]),
          ),
        );
      }),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;
    await _apply([_Ev(type, time: time, reason: type == 'break_start' ? reason : null, note: type == 'break_start' ? note : null)], date: date);
  }

  // ── voice ──────────────────────────────────────────────────────────
  Future<void> _voice() async {
    final res = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => VoiceAllocationSheet(
        dateStr: _date,
        idaGreen: _green,
        endpoint: '/factory-live/parse',
        title: 'Speak what happened',
        hint: 'Say "started", "lunch break", "break over", "power cut, feeder belt problem" or "stopped". '
            'You can say the time too: "stopped at 1:15", "lunch from 1 to 1:30".',
      ),
    );
    if (res == null || !mounted) return;
    final events = <_Ev>[
      for (final e in (res['events'] as List? ?? []))
        _Ev('${e['type']}', time: e['time'] as String?, reason: e['reason_type'] as String?, note: e['reason_note'] as String?)
    ];
    if (events.isEmpty) {
      _toast('I could not tell what happened. Try "started", "break" or "stopped".');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) {
        return AlertDialog(
          title: const Text('Check what was heard'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in events)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        DropdownButton<String>(
                          isExpanded: true,
                          value: e.type,
                          items: const [
                            DropdownMenuItem(value: 'start', child: Text('Factory started')),
                            DropdownMenuItem(value: 'break_start', child: Text('Break starts')),
                            DropdownMenuItem(value: 'break_end', child: Text('Break over')),
                            DropdownMenuItem(value: 'stop', child: Text('Factory stopped')),
                          ],
                          onChanged: (v) => setD(() {
                            e.type = v ?? e.type;
                            if (e.type == 'break_start') e.reason ??= 'other';
                          }),
                        ),
                        Row(children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 6),
                          TextButton(
                            onPressed: () async {
                              final t = await _pickTime(e.time);
                              if (t != null) setD(() => e.time = t);
                            },
                            child: Text(e.time == null ? 'Now' : e.time!),
                          ),
                          if (e.time != null) TextButton(onPressed: () => setD(() => e.time = null), child: const Text('Use now')),
                        ]),
                        if (e.type == 'break_start') ...[
                          DropdownButton<String>(
                            isExpanded: true,
                            value: _reasonLabels.containsKey(e.reason) ? e.reason : 'other',
                            items: [for (final r in _reasonLabels.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                            onChanged: (v) => setD(() => e.reason = v),
                          ),
                          TextFormField(
                            initialValue: e.note ?? '',
                            decoration: const InputDecoration(labelText: 'Note', isDense: true),
                            onChanged: (v) => e.note = v,
                          ),
                        ],
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: () => setD(() => events.remove(e)), child: const Text('Remove')),
                        ),
                      ]),
                    ),
                  ),
                const Text('Nothing is saved until you tap Save.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            TextButton(onPressed: events.isEmpty ? null : () => Navigator.pop(dctx, true), child: const Text('Save')),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    await _apply(events);
  }

  // ── build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_error != null && _state == null) {
      return const SizedBox.shrink(); // older server without live runs: the normal screen still works
    }
    final st = _state;
    if (st == null) return const SizedBox.shrink();
    final open = _open;
    final onBreak = open != null && open['status'] == 'on_break';
    final breaks = open == null ? <Map>[] : (open['breaks'] as List).map((e) => Map.from(e as Map)).toList();
    final runs = (st['runs'] as List? ?? []).map((e) => Map.from(e as Map)).toList();
    final stale = (st['stale_open'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final today = '${st['today']}';

    final bg = open == null ? Colors.white : (onBreak ? _amberBg : const Color(0xFFE8F5E2));
    String headline;
    if (open == null) {
      headline = 'Factory is not running';
    } else if (onBreak) {
      final b = breaks.last;
      headline = 'On break since ${b['start_time']} (${_reasonLabels[b['reason_type']] ?? 'Other'})';
    } else {
      headline = 'Running since ${open['start_time']}';
    }

    Widget big(String label, IconData icon, Color c, VoidCallback onTap) => Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: c,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _busy ? null : onTap,
            icon: Icon(icon, color: Colors.white),
            label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFCFDDC3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(open == null ? Icons.power_settings_new : (onBreak ? Icons.pause_circle_outline : Icons.play_circle_outline), color: onBreak ? _amberFg : _green),
          const SizedBox(width: 8),
          Expanded(child: Text(headline, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: _dark))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.refresh, size: 20), onPressed: () => _load()),
        ]),
        if (open != null && breaks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [for (final b in breaks) '${b['start_time']}–${b['end_time'] ?? '…'} ${_reasonLabels[b['reason_type']] ?? ''}${(b['reason_note'] ?? '').toString().isEmpty ? '' : ' (${b['reason_note']})'}'].join('\n'),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A5643)),
            ),
          ),
        if (open == null && runs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Today: ${[for (final r in runs) '${r['start']}–${r['end']} (${r['run_display']})'].join(', ')}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A5643)),
            ),
          ),
        for (final s in stale)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFDE8E6), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Text('The run of ${s['date']} that began at ${s['start_time']} was never stopped.',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF9E2419), fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        // that day's run: say when it stopped (and the breaks if needed through the normal Add Entry)
                        await _load(date: '${s['date']}');
                        await _step('stop', date: '${s['date']}');
                        await _load(date: today);
                        widget.onChanged?.call();
                      },
                child: const Text('Enter stop time'),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Row(children: [
          if (open == null) big('Start', Icons.play_arrow, _green, () => _step('start')),
          if (open != null && !onBreak) big('Break', Icons.pause, const Color(0xFFD98200), () => _step('break_start')),
          if (open != null && onBreak) big('Break over', Icons.play_arrow, _green, () => _step('break_end')),
          if (open != null) ...[const SizedBox(width: 8), big('Stop', Icons.stop, const Color(0xFFB3261E), () => _step('stop'))],
          if (!kIsWeb) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _dark, padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _busy ? null : _voice,
                child: const Icon(Icons.mic, color: Colors.white),
              ),
            ),
          ],
        ]),
        if (open != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final okd = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Throw away this run?'),
                          content: const Text('Use this only if it was started by mistake. Nothing will be saved for it.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
                            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Throw away')),
                          ],
                        ),
                      );
                      if (okd != true) return;
                      try {
                        await Api.json('DELETE', '/factory-live/open/${open['id']}');
                      } catch (e) {
                        _toast(Api.errorText(e));
                      }
                      await _load();
                    },
              child: const Text('Started by mistake?', style: TextStyle(fontSize: 12, color: Color(0xFF5F6A58))),
            ),
          ),
      ]),
    );
  }
}
