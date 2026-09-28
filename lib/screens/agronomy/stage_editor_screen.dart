// lib/screens/agronomy/stage_editor_screen.dart
//
// Full-screen editor for one growth stage of a crop plan: name and day
// range (from sowing, or from flowering / pruning / harvest for
// orchards). Pops `true` when something was saved or deleted.

import 'package:flutter/material.dart';
import 'agronomy_common.dart';

class StageEditorScreen extends StatefulWidget {
  final Map variety;
  final Map? stage;
  final List<Map> steps; // numbered steps, to show which fall in this stage
  final bool canEdit;
  const StageEditorScreen({super.key, required this.variety, this.stage, required this.steps, required this.canEdit});
  @override
  State<StageEditorScreen> createState() => _StageEditorScreenState();
}

class _StageEditorScreenState extends State<StageEditorScreen> {
  late bool seasonal;
  late String trigger;
  final nameCtrl = TextEditingController();
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  String age = '';
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    seasonal = widget.variety['crop_type'] != 'perennial';
    final g = widget.stage;
    trigger = g?['trigger_type'] ?? (seasonal ? 'DAS' : 'DAF');
    nameCtrl.text = g?['stage_name'] ?? '';
    fromCtrl.text = g == null ? '' : '${g['trigger_days_start']}';
    toCtrl.text = g == null ? '' : '${g['trigger_days_end']}';
    notesCtrl.text = g?['notes'] ?? '';
    age = g?['tree_age_bracket'] ?? '';
  }

  Future<void> _save() async {
    final a = int.tryParse(fromCtrl.text.trim());
    final b = int.tryParse(toCtrl.text.trim());
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => error = 'Write the stage name.');
      return;
    }
    if (a == null || b == null || a < 0 || b < a) {
      setState(() => error = 'Write the day range — “to” can’t be before “from”.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final body = {
        'stage_name': nameCtrl.text.trim(),
        'trigger_type': trigger,
        'trigger_days_start': a,
        'trigger_days_end': b,
        'tree_age_bracket': seasonal || age.isEmpty ? null : age,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      };
      if (widget.stage == null) {
        await AgriApi.post('/agri/crop-stage-templates', {...body, 'crop_variety_id': widget.variety['id']});
      } else {
        await AgriApi.patch('/agri/crop-stage-templates/${widget.stage!['id']}', body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete the “${widget.stage!['stage_name']}” stage?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => saving = true);
    try {
      await AgriApi.delete('/agri/crop-stage-templates/${widget.stage!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        saving = false;
        error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.stage;
    final ed = widget.canEdit;
    final anchor = seasonal ? 'DAS' : 'DAF';
    final inside = g == null
        ? <Map>[]
        : widget.steps
            .where((s) =>
                s['est'] != null &&
                g['trigger_type'] == anchor &&
                (s['est'] as int) >= (toI(g['trigger_days_start']) ?? 0) &&
                (s['est'] as int) <= (toI(g['trigger_days_end']) ?? 0))
            .toList();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: agDark,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g == null ? 'New stage' : g['stage_name'], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('${widget.variety['crop_name']} · ${widget.variety['name']}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          if (g != null && ed) IconButton(tooltip: 'Delete stage', onPressed: saving ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
            child: Text(error!, style: TextStyle(color: Colors.red.shade900)),
          ),
        TextField(controller: nameCtrl, enabled: ed, decoration: agInput('Stage name', hint: 'e.g. Flowering')),
        if (!seasonal) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: trigger,
            decoration: agInput('Counted from'),
            items: [for (final k in anchorOptions(false, withPrev: false)) DropdownMenuItem(value: k, child: Text(anchorWords[k]!))],
            onChanged: ed ? (v) => setState(() => trigger = v!) : null,
          ),
        ],
        const SizedBox(height: 14),
        agLabel('Days after ${anchorWords[trigger]}'),
        Row(children: [
          Expanded(child: TextField(controller: fromCtrl, enabled: ed, keyboardType: TextInputType.number, decoration: agInput('From day'))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('to', style: TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: TextField(controller: toCtrl, enabled: ed, keyboardType: TextInputType.number, decoration: agInput('To day'))),
        ]),
        if (!seasonal) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: age,
            decoration: agInput('Tree age'),
            items: [
              const DropdownMenuItem(value: '', child: Text('All ages')),
              for (final a in agAgeBrackets) DropdownMenuItem(value: a, child: Text('$a years')),
            ],
            onChanged: ed ? (v) => setState(() => age = v ?? '') : null,
          ),
        ],
        if (g != null) ...[
          const SizedBox(height: 18),
          agLabel('Steps during this stage'),
          if (inside.isEmpty) const Text('None', style: TextStyle(color: agMuted)),
          for (final s in inside)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                CircleAvatar(radius: 12, backgroundColor: agDark, child: Text('${s['no']}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${whenText(s, s['no'] as int)} · ${((s['products'] as List?) ?? []).map((p) => p['name']).join(' + ')}',
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
        ],
        const SizedBox(height: 14),
        TextField(controller: notesCtrl, enabled: ed, decoration: agInput('Notes (optional)')),
      ]),
      bottomNavigationBar: !ed
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: agBorder))),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: agGreen, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
                      onPressed: saving ? null : _save,
                      icon: Icon(g == null ? Icons.add : Icons.check),
                      label: Text(saving ? 'Saving…' : (g == null ? 'Add stage' : 'Save stage')),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
